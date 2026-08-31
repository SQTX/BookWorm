cmake_minimum_required(VERSION 3.21)
project(BookWorm VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS
    Network
    Core
    Sql
    Qml
    Quick
    QuickControls2
    Widgets
    Charts
    ChartsQml
)

qt_standard_project_setup(REQUIRES 6.5)

# Theme singleton
set_source_files_properties(qml/theme/Theme.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_executable(BookWorm
    src/main.cpp
    src/database/databasemanager.h
    src/database/databasemanager.cpp
    src/models/book.h
    src/models/book.cpp
    src/models/bookmodel.h
    src/models/bookmodel.cpp
    src/controllers/bookcontroller.h
    src/controllers/bookcontroller.cpp
    src/statistics/statisticsprovider.h
    src/statistics/statisticsprovider.cpp
    src/sync/keychain.h
    src/sync/keychain.cpp
    src/sync/syncrepository.h
    src/sync/syncrepository.cpp
    src/sync/syncmanager.h
    src/sync/syncmanager.cpp
    src/sync/apiclient.h
    src/sync/apiclient.cpp
    src/backup/backupmanager.h
    src/backup/backupmanager.cpp
)

qt_add_qml_module(BookWorm
    URI BookWorm
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/theme/Theme.qml
        qml/theme/translations.js
        qml/components/BookCard.qml
        qml/components/BookForm.qml
        qml/components/BookDetails.qml
        qml/components/BookListView.qml
        qml/components/BookTableView.qml
        qml/components/StatisticsView.qml
        qml/components/StatisticsOverview.qml
        qml/components/StatisticsSessions.qml
        qml/components/ChallengesView.qml
        qml/components/SeriesView.qml
        qml/components/SettingsDialog.qml
        qml/components/common/Panel.qml
        qml/components/common/SectionLabel.qml
        qml/components/common/AppButton.qml
        qml/components/common/Chip.qml
        qml/components/common/IconButton.qml
        qml/components/common/PageHeader.qml
        qml/components/common/EmptyState.qml
    RESOURCES
        src/img/png/main_icon.png
        src/img/png/main_icon_radius.png
        src/img/icons/library-view.svg
        src/img/icons/synchronize.svg
        src/img/icons/sheet-view.svg
        src/img/icons/stat-view.svg
        src/img/icons/settings.svg
        src/img/icons/export.svg
        src/img/icons/inport.svg
        src/img/icons/add-book.svg
        src/img/icons/star-full.svg
        src/img/icons/star-empty.svg
        src/img/icons/challenges.svg
        src/img/icons/book-cover.svg
        src/img/icons/calendar.svg
        src/img/icons/tags.svg
        src/img/icons/techbook.svg
        src/img/icons/audiobook.svg
        src/img/icons/audobook-support.svg
        src/img/icons/status-reading.svg
        src/img/icons/status-read.svg
        src/img/icons/status-planed.svg
        src/img/icons/status-abondoned.svg
)

# Include directories so QML type registration can find headers
target_include_directories(BookWorm PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/models
    ${CMAKE_CURRENT_SOURCE_DIR}/src/controllers
    ${CMAKE_CURRENT_SOURCE_DIR}/src/statistics
    ${CMAKE_CURRENT_SOURCE_DIR}/src/database
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backup
    ${CMAKE_CURRENT_SOURCE_DIR}/src/sync
)

if(APPLE)
    # Keychain: tokens must not sit in QSettings, which on macOS is a plist in
    # the user's Library.
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
endif()

target_link_libraries(BookWorm PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::Sql
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::Charts
    Qt6::ChartsQml
    $<$<BOOL:${APPLE}>:${SECURITY_FRAMEWORK}>
    $<$<BOOL:${APPLE}>:${COREFOUNDATION_FRAMEWORK}>
)

if(APPLE)
    set(MACOSX_ICON "${CMAKE_CURRENT_SOURCE_DIR}/src/img/BookWorm.icns")
    set_source_files_properties(${MACOSX_ICON} PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    target_sources(BookWorm PRIVATE ${MACOSX_ICON})

    set_target_properties(BookWorm PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_GUI_IDENTIFIER com.sqtx.bookworm
        MACOSX_BUNDLE_BUNDLE_NAME BookWorm
        MACOSX_BUNDLE_ICON_FILE BookWorm.icns
    )

    # Re-sign the finished bundle, ad-hoc.
    #
    # The linker already emits a signature, but a minimal one: `codesign -dv`
    # reports it as "linker-signed", with the Info.plist not bound, no sealed
    # resources and no internal requirements. macOS uses a program's identity to
    # decide whether it may reuse a Keychain item it created earlier, and an
    # identity that thin gives it nothing durable to record — so the permission
    # panel returns on its own schedule, and with it the "Sign in required" that
    # sent the user back to Settings to retype a server password.
    #
    # `codesign --force --sign -` binds the identifier and seals the bundle,
    # which is the most a locally built application can offer without a real
    # signing certificate. It does not survive a rebuild — an ad-hoc identity is
    # a hash of the binary — so a rebuild still costs one re-authorisation.
    add_custom_command(TARGET BookWorm POST_BUILD
        COMMAND codesign --force --sign - --identifier com.sqtx.bookworm
                "$<TARGET_BUNDLE_DIR:BookWorm>"
        COMMENT "Signing the bundle ad-hoc so the Keychain can recognise it again"
        VERBATIM
    )
endif()
