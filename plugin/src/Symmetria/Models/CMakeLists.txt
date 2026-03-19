qml_module(symmetria-models
    URI Symmetria.Models
    SOURCES
        filesystemmodel.hpp filesystemmodel.cpp
        previewimagehelper.hpp previewimagehelper.cpp
    LIBRARIES
        Qt::Gui
        Qt::Concurrent
)
