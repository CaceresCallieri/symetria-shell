# This module also builds alone so a model update does not require the audio plugin.
cmake_minimum_required(VERSION 3.19)
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(symmetria-models VERSION 1.0 LANGUAGES CXX)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    find_package(Qt6 6.9 REQUIRED COMPONENTS Core Qml Gui Concurrent)
    qt_standard_project_setup(REQUIRES 6.9)
    set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")
    set(INSTALL_QMLDIR "lib/qt6/qml" CACHE STRING "QML install directory")
    include(CTest)
endif()

qt_add_qml_module(symmetria-models
    URI Symmetria.Models
    VERSION 1.0
    SOURCES filesystemmodel.hpp filesystemmodel.cpp
)
target_link_libraries(symmetria-models PRIVATE Qt6::Core Qt6::Qml Qt6::Gui Qt6::Concurrent)
set(module_dir "${INSTALL_QMLDIR}/Symmetria/Models")
install(TARGETS symmetria-models symmetria-modelsplugin LIBRARY DESTINATION "${module_dir}")
install(FILES "${QT_QML_OUTPUT_DIRECTORY}/Symmetria/Models/qmldir"
              "${QT_QML_OUTPUT_DIRECTORY}/Symmetria/Models/symmetria-models.qmltypes"
        DESTINATION "${module_dir}")

if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test)
    qt_add_executable(FileSystemModelTest tests/FileSystemModelTest.cpp)
    target_link_libraries(FileSystemModelTest PRIVATE symmetria-models Qt6::Test Qt6::Qml Qt6::Gui)
    add_test(NAME FileSystemModelTest COMMAND FileSystemModelTest)
    set_tests_properties(FileSystemModelTest PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
