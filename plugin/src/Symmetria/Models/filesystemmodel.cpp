#include "filesystemmodel.hpp"

#include <QCollator>
#include <QDirIterator>
#include <QImageReader>
#include <QMimeDatabase>
#include <QUrl>
#include <QtConcurrentRun>
#include <algorithm>

namespace symmetria::models {
namespace {

DirectoryScan scanDirectory(const QString& path, bool recursive, FileSystemModel::Filter filter) {
    DirectoryScan result;
    if (path.isEmpty() || !QFileInfo(path).isDir())
        return result;

    const QDir root(path);
    result.directories.append(root.absolutePath());
    QMimeDatabase mimeDatabase;
    QDirIterator iterator(path, QDir::AllEntries | QDir::NoDotAndDotDot,
                          recursive ? QDirIterator::Subdirectories : QDirIterator::NoIteratorFlags);
    while (iterator.hasNext()) {
        iterator.next();
        const QFileInfo info = iterator.fileInfo();
        FileEntryData entry;
        entry.path = info.absoluteFilePath();
        entry.relativePath = root.relativeFilePath(entry.path);
        entry.name = info.fileName();
        entry.baseName = info.baseName();
        entry.suffix = info.completeSuffix();
        entry.isDir = info.isDir();
        if (entry.isDir) {
            if (recursive && !info.isSymLink())
                result.directories.append(entry.path);
        } else {
            entry.mimeType = mimeDatabase.mimeTypeForFile(info).name();
            entry.isImage = QImageReader(entry.path).canRead();
        }
        if (filter != FileSystemModel::Images || entry.isImage)
            result.entries.append(std::move(entry));
    }

    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(result.entries.begin(), result.entries.end(), [&collator](const auto& left, const auto& right) {
        if (left.isDir != right.isDir)
            return left.isDir;
        return collator.compare(left.relativePath, right.relativePath) < 0;
    });
    return result;
}

} // namespace

FileSystemEntry::FileSystemEntry(FileEntryData data, QObject* parent)
    : QObject(parent), m_data(std::move(data)) {}

FileSystemModel::FileSystemModel(QObject* parent) : QAbstractListModel(parent) {
    m_rescanTimer.setSingleShot(true);
    m_rescanTimer.setInterval(50);
    connect(&m_rescanTimer, &QTimer::timeout, this, &FileSystemModel::startScan);
    connect(&m_scan, &QFutureWatcher<DirectoryScan>::finished, this, &FileSystemModel::finishScan);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        if (m_watchChanges)
            scheduleScan();
    });
}

int FileSystemModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : static_cast<int>(m_entries.size());
}

QVariant FileSystemModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size() || role != Qt::UserRole)
        return {};
    return QVariant::fromValue(m_entries.at(index.row()));
}

QHash<int, QByteArray> FileSystemModel::roleNames() const {
    return {{Qt::UserRole, "modelData"}};
}

void FileSystemModel::setPath(const QString& path) {
    const QUrl url(path);
    const QString localPath = url.isLocalFile() ? url.toLocalFile() : path;
    if (m_path == localPath)
        return;
    m_path = localPath;
    m_directories.clear();
    // Clear old rows before navigation completes so the dialog cannot accept a stale path.
    replaceEntries({});
    emit pathChanged();
    updateWatches();
    scheduleScan();
}

void FileSystemModel::setRecursive(bool recursive) {
    if (m_recursive == recursive)
        return;
    m_recursive = recursive;
    m_directories.clear();
    emit recursiveChanged();
    updateWatches();
    scheduleScan();
}

void FileSystemModel::setWatchChanges(bool watchChanges) {
    if (m_watchChanges == watchChanges)
        return;
    m_watchChanges = watchChanges;
    emit watchChangesChanged();
    updateWatches();
    scheduleScan();
}

void FileSystemModel::setFilter(Filter filter) {
    if (m_filter == filter)
        return;
    m_filter = filter;
    emit filterChanged();
    scheduleScan();
}

QQmlListProperty<FileSystemEntry> FileSystemModel::entries() {
    return {this, &m_entries};
}

void FileSystemModel::setLoading(bool loading) {
    if (m_loading == loading)
        return;
    m_loading = loading;
    emit loadingChanged();
}

void FileSystemModel::scheduleScan() {
    ++m_generation;
    setLoading(true);
    m_rescanTimer.start();
}

void FileSystemModel::startScan() {
    // Serialize scans. A finished stale scan starts the latest requested generation.
    if (m_scan.isRunning())
        return;
    m_scanGeneration = m_generation;
    m_scan.setFuture(QtConcurrent::run(scanDirectory, m_path, m_recursive, m_filter));
}

void FileSystemModel::finishScan() {
    if (m_scanGeneration != m_generation) {
        startScan();
        return;
    }
    const DirectoryScan result = m_scan.result();
    m_directories = result.directories;
    updateWatches();
    replaceEntries(result.entries);
    setLoading(false);
}

void FileSystemModel::updateWatches() {
    const QStringList previous = m_watcher.directories();
    if (!previous.isEmpty())
        m_watcher.removePaths(previous);
    if (!m_watchChanges || m_path.isEmpty())
        return;

    QStringList directories = m_directories;
    QFileInfo ancestor(m_path);
    // Watch the parent too: directory deletion drops its own watch, and a missing
    // wallpaper directory must become visible when the operator creates it later.
    while (!ancestor.isDir() && !ancestor.isRoot())
        ancestor.setFile(ancestor.absolutePath());
    if (ancestor.isDir()) {
        directories.append(ancestor.absoluteFilePath());
        directories.append(ancestor.absolutePath());
    }
    directories.removeDuplicates();
    if (!directories.isEmpty())
        m_watcher.addPaths(directories);
}

void FileSystemModel::replaceEntries(const QList<FileEntryData>& entries) {
    const bool unchanged = entries.size() == m_entries.size()
        && std::equal(entries.begin(), entries.end(), m_entries.begin(),
                      [](const auto& data, const auto* entry) { return data == entry->snapshot(); });
    if (unchanged)
        return;
    const auto previous = m_entries;
    beginResetModel();
    m_entries.clear();
    for (const auto& data : entries)
        m_entries.append(new FileSystemEntry(data, this));
    endResetModel();
    emit entriesChanged();
    for (auto* entry : previous)
        entry->deleteLater();
}

} // namespace symmetria::models
