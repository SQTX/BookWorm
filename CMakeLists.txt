cmake_minimum_required(VERSION 3.21)
project(BookWorm VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS
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
        qml/components/ChallengesView.qml
    RESOURCES
        src/img/png/main_icon.png
        src/img/png/main_icon_radius.png
        src/img/icons/library-view.svg
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
)

target_link_libraries(BookWorm PRIVATE
    Qt6::Core
    Qt6::Sql
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::Charts
    Qt6::ChartsQml
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
endif()
