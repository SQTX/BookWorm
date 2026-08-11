#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QDir>
#include <QLibraryInfo>

#include "constants.h"
#include "database/databasemanager.h"
#include "controllers/bookcontroller.h"
#include "statistics/statisticsprovider.h"
#include "backup/backupmanager.h"
#include "sync/syncmanager.h"

#include <QSocketNotifier>
#include <csignal>
#include <unistd.h>

namespace {

/**
 * Turn SIGTERM and SIGINT into an ordinary Qt quit.
 *
 * Without this the process dies where it stands: aboutToQuit never fires, so
 * the closing sync never runs. Closing the window is handled by Qt already —
 * this covers being told to stop by something other than the user, which on a
 * shared machine is how the application usually ends.
 *
 * A signal handler may call almost nothing safely, and certainly nothing in Qt.
 * The classic answer applies: write one byte to a pipe, and let the event loop
 * notice it and do the real work.
 */
int g_signalPipe[2] = { -1, -1 };

/** Set once the singleton exists, so the signal path can reach it. */
SyncManager *g_shutdownSync = nullptr;

void onTerminationSignal(int)
{
    const char byte = 1;
    // Return value ignored deliberately: there is nothing useful to do about a
    // failed write from inside a signal handler.
    ssize_t ignored = ::write(g_signalPipe[1], &byte, 1);
    (void)ignored;
}

/**
 * Run the closing sync, then quit.
 *
 * Not from aboutToQuit. That signal is emitted while the event loop is already
 * unwinding, and the sync needs a live loop to wait for its reply — the request
 * went out and the answer never arrived. Doing the exchange first and quitting
 * afterwards keeps the loop running for exactly as long as it is needed.
 */
void syncThenQuit(QCoreApplication *app, SyncManager *sync)
{
    if (sync)
        sync->syncOnQuit();
    app->quit();
}

void installTerminationHandler(QCoreApplication *app)
{
    if (::pipe(g_signalPipe) != 0) {
        qWarning() << "Could not install a termination handler; shutdown sync may be skipped";
        return;
    }

    auto *notifier = new QSocketNotifier(g_signalPipe[0], QSocketNotifier::Read, app);
    QObject::connect(notifier, &QSocketNotifier::activated, app, [app, notifier]() {
        notifier->setEnabled(false);
        char byte;
        ssize_t ignored = ::read(g_signalPipe[0], &byte, 1);
        (void)ignored;
        syncThenQuit(app, g_shutdownSync);
    });

    ::signal(SIGTERM, onTerminationSignal);
    ::signal(SIGINT, onTerminationSignal);
}

} // namespace

int main(int argc, char *argv[])
{
    // Ensure Homebrew Qt plugins and QML modules are found.
    // Resolved at runtime so a Homebrew Qt upgrade does not break plugin discovery.
    QCoreApplication::addLibraryPath(QLibraryInfo::path(QLibraryInfo::PluginsPath));
    QCoreApplication::addLibraryPath(QStringLiteral("/opt/homebrew/share/qt/plugins"));

    QApplication app(argc, argv);
    app.setApplicationName(BookWorm::Config::APP_NAME);
    app.setApplicationVersion(BookWorm::Config::APP_VERSION);
    app.setOrganizationName(BookWorm::Config::APP_ORG);
    app.setWindowIcon(QIcon(QStringLiteral(":/qt/qml/BookWorm/src/img/png/main_icon_radius.png")));

    QQuickStyle::setStyle("Material");
    qputenv("QT_QUICK_CONTROLS_MATERIAL_THEME", "Dark");
    qputenv("QT_QUICK_CONTROLS_MATERIAL_ACCENT", "#BB86FC");

    // Database connection
    auto &db = DatabaseManager::instance();
    if (!db.connect()) {
        qCritical() << "Failed to connect to PostgreSQL database" << BookWorm::Config::dbName();
        return 1;
    }
    db.initializeSchema();

    // Controllers
    BookController bookController;
    StatisticsProvider statsProvider;
    BackupManager backupManager;
    SyncManager syncManager;

    bookController.loadBooks();
    statsProvider.refresh();

    // Connect: refresh stats when books change
    QObject::connect(&bookController, &BookController::booksChanged,
                     &statsProvider, &StatisticsProvider::refresh);

    // QML engine
    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("/opt/homebrew/share/qt/qml"));

    engine.rootContext()->setContextProperty("bookController", &bookController);
    engine.rootContext()->setContextProperty("statsProvider", &statsProvider);
    engine.rootContext()->setContextProperty("backupManager", &backupManager);
    engine.rootContext()->setContextProperty("syncManager", &syncManager);

    using namespace Qt::StringLiterals;
    const QUrl url(u"qrc:/qt/qml/BookWorm/qml/Main.qml"_s);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    installTerminationHandler(&app);

    // ── Automatic synchronisation ──
    //
    // Only reaches the network when the user has connected a server; with sync
    // off these are no-ops and nothing is attempted (D8).
    //
    // Neither direction can overwrite newer data with older. Every row carries
    // the time its user edited it, and both sides apply the same rule: a row
    // older than the copy already stored is rejected rather than written. So
    // launching a machine that has been offline for a week cannot roll the
    // server back to what that machine remembers.
    // After load(), so a first exchange cannot race the windows into existence.
    syncManager.syncOnStart();

    // Closing the last window would normally quit immediately. Taking that over
    // means the exchange happens while the event loop is still running, which
    // is the difference between the reply arriving and not.
    app.setQuitOnLastWindowClosed(false);
    QObject::connect(&app, &QGuiApplication::lastWindowClosed, &app, [&app, &syncManager]() {
        syncThenQuit(&app, &syncManager);
    });

    g_shutdownSync = &syncManager;

    return app.exec();
}
