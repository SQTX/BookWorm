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

int main(int argc, char *argv[])
{
    // Ensure Homebrew Qt plugins and QML modules are found
    QCoreApplication::addLibraryPath(QStringLiteral("/opt/homebrew/Cellar/qtbase/6.10.2/share/qt/plugins"));
    QCoreApplication::addLibraryPath(QStringLiteral("/opt/homebrew/share/qt/plugins"));

    QApplication app(argc, argv);
    app.setApplicationName(WormBook::Config::APP_NAME);
    app.setApplicationVersion(WormBook::Config::APP_VERSION);
    app.setOrganizationName(WormBook::Config::APP_ORG);
    app.setWindowIcon(QIcon(QStringLiteral(":/qt/qml/WormBook/Priv/img/main_icon.png")));

    QQuickStyle::setStyle("Material");
    qputenv("QT_QUICK_CONTROLS_MATERIAL_THEME", "Dark");
    qputenv("QT_QUICK_CONTROLS_MATERIAL_ACCENT", "#BB86FC");

    // Database connection
    auto &db = DatabaseManager::instance();
    if (!db.connect()) {
        qCritical("Failed to connect to PostgreSQL database '%s'", WormBook::Config::DB_NAME);
        return 1;
    }
    db.initializeSchema();

    // Controllers
    BookController bookController;
    StatisticsProvider statsProvider;

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

    using namespace Qt::StringLiterals;
    const QUrl url(u"qrc:/qt/qml/WormBook/qml/Main.qml"_s);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
