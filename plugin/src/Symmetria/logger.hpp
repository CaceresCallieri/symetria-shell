#pragma once

#include <qfile.h>
#include <qmutex.h>
#include <qobject.h>
#include <qqmlintegration.h>

namespace symmetria {

/// Unified debug logger for Symmetria shell.
///
/// Writes human-readable timestamped lines to ~/.local/state/symmetria/debug.log
/// (or $SYMMETRIA_DEBUG_LOG override). All sources (C++, QML, bash, Lua) converge
/// here for a single-timeline debug story.
///
/// Usage from QML:
///   Logger.log("qml", "stt", "toggle | state=" + _state)
/// Produces:
///   14:32:01.234 [qml:stt] toggle | state=idle
class Logger : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Logger(QObject* parent = nullptr);

    /// Append a line: "HH:MM:SS.mmm [source:module] message\n"
    Q_INVOKABLE void log(const QString& source, const QString& module, const QString& message);

private:
    QFile m_file;
    QMutex m_mutex;

    static QString resolveLogPath();
    void rotateIfNeeded();
};

} // namespace symmetria
