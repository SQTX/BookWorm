#include <QApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QFile>
#include <QTextStream>
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
 * SIGTERM and SIGINT, turned into an ordinary Qt quit.
 *
 * Without this the process dies where it stands and the closing exchange never
 * happens. Closing the window is already handled; this covers being told to
 * stop by something else, which is how an application usually ends when a
 * machine shuts down.
 *
 * A signal handler may safely call almost nothing, and nothing in Qt. The
 * standard answer applies: write a byte to a pipe and let the event loop act.
 */
int g_signalPipe[2] = { -1, -1 };
SyncManager *g_shutdownSync = nullptr;
QCoreApplication *g_app = nullptr;

void onTerminationSignal(int)
{
    const char byte = 1;
    ssize_t ignored = ::write(g_signalPipe[1], &byte, 1);
    (void)ignored;
}

/**
 * Exchange, then quit — in that order.
 *
 * Not from aboutToQuit: that signal fires while the event loop is already
 * unwinding, and the exchange needs a live loop to receive its reply.
 */
void syncThenQuit()
{
    if (g_shutdownSync)
        g_shutdownSync->syncOnQuit();
    if (g_app)
        g_app->quit();
}

void installTerminationHandler(QCoreApplication *app)
{
    if (::pipe(g_signalPipe) != 0) {
        qWarning() << "No termination handler; a shutdown may skip the final sync";
        return;
    }

    auto *notifier = new QSocketNotifier(g_signalPipe[0], QSocketNotifier::Read, app);
    QObject::connect(notifier, &QSocketNotifier::activated, app, [notifier]() {
        notifier->setEnabled(false);
        char byte;
        ssize_t ignored = ::read(g_signalPipe[0], &byte, 1);
        (void)ignored;
        syncThenQuit();
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

    // Rows that arrived from the server are in the database but not in the
    // model: the model was filled before the exchange finished, and nothing
    // told it otherwise. Without this the only way to see another device's
    // edit is to restart the application, which is exactly how it behaved.
    //
    // The flag separates "the user changed something" from "the model was
    // rebuilt because the server did". Both emit booksChanged, and only the
    // first is worth an exchange — syncing on the second would answer every
    // pull with a push and never stop.
    static bool applyingRemoteChanges = false;
    QObject::connect(&syncManager, &SyncManager::remoteChangesApplied,
                     &bookController, [&bookController]() {
                         applyingRemoteChanges = true;
                         bookController.loadBooks();
                         applyingRemoteChanges = false;
                     });

    // An edit reaches the server on its own, a few seconds later. Before this,
    // the only way out was the button in Settings or waiting for the timer.
    QObject::connect(&bookController, &BookController::booksChanged,
                     &syncManager, [&syncManager]() {
                         if (!applyingRemoteChanges)
                             syncManager.syncSoon();
                     });

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

    // ── Automatic synchronisation ──
    //
    // Reaches the network only once a server has been connected; with sync off
    // both calls return immediately and nothing is attempted (D8).
    //
    // Neither direction can replace newer data with older. Every row carries
    // the time its user edited it and both sides apply the same rule, so a
    // machine that has been offline for a week cannot roll the server back to
    // what it remembers.
    g_app = &app;
    g_shutdownSync = &syncManager;

    syncManager.syncOnStart();

    // Closing the last window would otherwise quit immediately, leaving no live
    // event loop for the final exchange.
    app.setQuitOnLastWindowClosed(false);
    QObject::connect(&app, &QGuiApplication::lastWindowClosed, &app, []() { syncThenQuit(); });

    installTerminationHandler(&app);

    return app.exec();
}
