#include "logger.hpp"

#include <qdatetime.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qlogging.h>
#include <qstandardpaths.h>

namespace symmetria {

static constexpr qint64 MAX_LOG_SIZE = 1024 * 1024; // 1 MB
static constexpr qint64 KEEP_TAIL = 512 * 1024;     // keep last ~500 KB after rotation

Logger::Logger(QObject* parent)
    : QObject(parent)
    , m_file(resolveLogPath()) {

    // Ensure parent directory exists
    const QFileInfo info(m_file.fileName());
    QDir().mkpath(info.absolutePath());

    rotateIfNeeded();

    if (!m_file.open(QIODevice::Append | QIODevice::Text)) {
        qWarning() << "Logger: failed to open" << m_file.fileName() << m_file.errorString();
        return;
    }

    // Startup marker
    const auto now = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"));
    const auto line = QStringLiteral("%1 [cpp:logger] === Symmetria shell started ===\n").arg(now);
    m_file.write(line.toUtf8());
    m_file.flush();
}

void Logger::log(const QString& source, const QString& module, const QString& message) {
    const auto now = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"));
    const auto bytes = QStringLiteral("%1 [%2:%3] %4\n").arg(now, source, module, message).toUtf8();

    QMutexLocker lock(&m_mutex);
    if (!m_file.isOpen())
        return;
    m_file.write(bytes);
    m_file.flush();
}

QString Logger::resolveLogPath() {
    // Environment override
    const auto envPath = qEnvironmentVariable("SYMMETRIA_DEBUG_LOG");
    if (!envPath.isEmpty())
        return envPath;

    // XDG_STATE_HOME / fallback
    auto stateDir = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation);
    if (stateDir.isEmpty())
        stateDir = QDir::homePath() + QStringLiteral("/.local/state");

    return stateDir + QStringLiteral("/symmetria/debug.log");
}

void Logger::rotateIfNeeded() {
    if (!m_file.exists())
        return;

    const qint64 size = m_file.size();
    if (size <= MAX_LOG_SIZE)
        return;

    // Read tail content before any destructive operation
    if (!m_file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "Logger: rotation read failed:" << m_file.errorString();
        return;
    }

    m_file.seek(size - KEEP_TAIL);
    m_file.readLine(); // skip partial line
    const QByteArray tail = m_file.readAll();
    m_file.close();

    // Write to temp file first, then rename atomically (no data loss on failure)
    const QString tmpPath = m_file.fileName() + QStringLiteral(".tmp");
    QFile tmp(tmpPath);
    if (!tmp.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        qWarning() << "Logger: rotation tmp write failed:" << tmp.errorString();
        return; // original file untouched
    }

    const auto now = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"));
    const auto marker = QStringLiteral("%1 [cpp:logger] === Log rotated (kept ~%2 KB) ===\n")
                            .arg(now)
                            .arg(tail.size() / 1024);
    tmp.write(marker.toUtf8());
    tmp.write(tail);
    tmp.close();

    // Atomic rename on Linux (same filesystem)
    QFile::remove(m_file.fileName());
    if (!QFile::rename(tmpPath, m_file.fileName())) {
        qWarning() << "Logger: rotation rename failed";
        QFile::remove(tmpPath);
    }
}

} // namespace symmetria
