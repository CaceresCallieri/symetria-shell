qml_module(symmetria-models
    URI Symmetria.Models
    SOURCES
        filesystemmodel.hpp filesystemmodel.cpp
        previewimagehelper.hpp previewimagehelper.cpp
        syntaxhighlighthelper.hpp syntaxhighlighthelper.cpp
        archivepreviewmodel.hpp archivepreviewmodel.cpp
    LIBRARIES
        Qt::Gui
        Qt::Concurrent
        KF6::SyntaxHighlighting
        PkgConfig::LibArchive
)
