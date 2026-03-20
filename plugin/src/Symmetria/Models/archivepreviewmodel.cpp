#include "archivepreviewmodel.hpp"

#include <qfuturewatcher.h>
#include <qtconcurrentrun.h>

#include <archive.h>
#include <archive_entry.h>

#include <map>
#include <memory>

namespace symmetria::models {

// Internal tree node used only during archive parsing. Builds a sorted
// directory tree from flat archive paths, then flattens depth-first into
// the QVector<ArchiveEntryData> that backs the model.
struct TreeNode {
    QString name;
    QString fullPath;
    qint64 size = 0;
    bool isDir = false;
    // std::map keeps keys sorted and supports move-only values (unique_ptr).
    // QMap cannot hold unique_ptr due to its copy-on-write internals.
    std::map<QString, std::unique_ptr<TreeNode>> children;
};

// Result struct returned from the async archive reading task.
struct ArchiveReadResult {
    QVector<ArchiveEntryData> entries;
    int fileCount = 0;
    int dirCount = 0;
    int totalEntries = 0;
    qint64 totalSize = 0;
    bool truncated = false;
    QString error;
};

// Recursively flatten a tree node depth-first into a flat list.
// Directories come before files at each level (QMap sorts by key, but we
// partition dirs-first within each parent for the Yazi-style listing).
static void flattenTree(
    const TreeNode& node, int depth, QVector<ArchiveEntryData>& out, int maxEntries)
{
    if (out.size() >= maxEntries)
        return;

    // Partition: directories first, then files — both groups sorted by name (std::map order)
    QVector<const TreeNode*> dirs;
    QVector<const TreeNode*> files;
    for (const auto& [key, child] : node.children) {
        if (child->isDir)
            dirs.append(child.get());
        else
            files.append(child.get());
    }

    auto emitNode = [&](const TreeNode* child) {
        if (out.size() >= maxEntries)
            return;
        out.append({child->name, child->fullPath, child->size, child->isDir, depth});
        if (child->isDir)
            flattenTree(*child, depth + 1, out, maxEntries);
    };

    for (const auto* d : dirs)
        emitNode(d);
    for (const auto* f : files)
        emitNode(f);
}

// Ensure all intermediate directories exist in the tree for a given path.
// Returns the leaf node (which may be a file or an explicit directory).
static TreeNode* ensurePath(TreeNode& root, const QStringList& parts, bool isDir) {
    TreeNode* current = &root;
    for (int i = 0; i < parts.size(); ++i) {
        const QString& part = parts[i];
        if (part.isEmpty())
            continue;

        auto it = current->children.find(part);
        if (it == current->children.end()) {
            auto node = std::make_unique<TreeNode>();
            node->name = part;
            // Build the full path from parts[0..i]
            QStringList pathParts;
            for (int j = 0; j <= i; ++j) {
                if (!parts[j].isEmpty())
                    pathParts.append(parts[j]);
            }
            node->fullPath = pathParts.join(u'/');
            // Intermediate nodes are always directories; leaf depends on isDir param
            node->isDir = (i < parts.size() - 1) || isDir;
            auto [insertedIt, _] = current->children.emplace(part, std::move(node));
            it = insertedIt;
        } else if (i < parts.size() - 1) {
            // Intermediate node must be a directory even if it wasn't created as one
            it->second->isDir = true;
        }
        current = it->second.get();
    }
    return current;
}

// Read archive headers and build the tree structure. Runs on a worker thread.
static ArchiveReadResult readArchiveContents(const QString& filePath) {
    ArchiveReadResult result;

    // RAII wrapper for libarchive's archive pointer
    struct ArchiveDeleter {
        void operator()(struct archive* a) const {
            archive_read_free(a);
        }
    };
    std::unique_ptr<struct archive, ArchiveDeleter> a(archive_read_new());

    archive_read_support_filter_all(a.get());
    archive_read_support_format_all(a.get());
    // Also support raw format for single-file compressed streams (.gz, .bz2, .xz)
    archive_read_support_format_raw(a.get());

    const QByteArray pathBytes = filePath.toUtf8();
    int r = archive_read_open_filename(a.get(), pathBytes.constData(), 10240);
    if (r != ARCHIVE_OK) {
        result.error = QString::fromUtf8(archive_error_string(a.get()));
        return result;
    }

    TreeNode root;
    root.isDir = true;

    struct archive_entry* entry;
    while (archive_read_next_header(a.get(), &entry) == ARCHIVE_OK) {
        const char* pathname = archive_entry_pathname_utf8(entry);
        const char* pathnameFallback = pathname ? nullptr : archive_entry_pathname(entry);
        if (!pathname && !pathnameFallback)
            continue;

        // Use UTF-8 path when available; fall back to locale-encoded bytes (best-effort
        // for Latin-1 / Shift-JIS archives — may produce replacement chars in exotic cases).
        QString path = pathname
            ? QString::fromUtf8(pathname)
            : QString::fromLocal8Bit(pathnameFallback);
        // Normalize: remove trailing slashes, skip empty/dot entries
        while (path.endsWith(u'/'))
            path.chop(1);
        if (path.isEmpty() || path == QStringLiteral("."))
            continue;

        const bool isDir = (archive_entry_filetype(entry) == AE_IFDIR);
        // archive_entry_size() returns 0 when unset (e.g. ZIP with data descriptors,
        // RAW compressed streams). Only add to totalSize when the value is known.
        const qint64 size = (!isDir && archive_entry_size_is_set(entry))
            ? archive_entry_size(entry)
            : 0;

        result.totalEntries++;
        if (isDir)
            result.dirCount++;
        else
            result.fileCount++;
        result.totalSize += size;

        // Build tree structure
        const QStringList parts = path.split(u'/');
        TreeNode* node = ensurePath(root, parts, isDir);
        node->size = size;
        node->isDir = isDir;
    }

    // Check for read errors (not just EOF).
    // Report errors even if some entries were read — a mid-archive failure means
    // the listing is partial. The caller sees both partial entries and an error string.
    if (archive_errno(a.get()) != 0) {
        result.error = QString::fromUtf8(archive_error_string(a.get()));
    }

    // Flatten the tree depth-first into the flat list
    flattenTree(root, 0, result.entries, ArchivePreviewModel::MaxEntries);
    // result.totalEntries is the raw scan count (uncapped); result.entries is capped
    // at MaxEntries by flattenTree. The two diverge iff more entries exist than the cap.
    result.truncated = result.entries.size() < result.totalEntries;

    return result;
}

ArchivePreviewModel::ArchivePreviewModel(QObject* parent)
    : QAbstractListModel(parent) {}

int ArchivePreviewModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return static_cast<int>(m_entries.size());
}

QVariant ArchivePreviewModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};

    const auto& entry = m_entries.at(index.row());
    switch (role) {
    case NameRole:     return entry.name;
    case FullPathRole: return entry.fullPath;
    case SizeRole:     return entry.size;
    case IsDirRole:    return entry.isDir;
    case DepthRole:    return entry.depth;
    default:           return {};
    }
}

QHash<int, QByteArray> ArchivePreviewModel::roleNames() const {
    return {
        {NameRole,     "name"},
        {FullPathRole, "fullPath"},
        {SizeRole,     "size"},
        {IsDirRole,    "isDir"},
        {DepthRole,    "depth"},
    };
}

QString ArchivePreviewModel::filePath() const { return m_filePath; }

void ArchivePreviewModel::setFilePath(const QString& path) {
    if (m_filePath == path)
        return;
    m_filePath = path;
    emit filePathChanged();
    readArchive();
}

int ArchivePreviewModel::fileCount() const { return m_fileCount; }
int ArchivePreviewModel::dirCount() const { return m_dirCount; }
qint64 ArchivePreviewModel::totalSize() const { return m_totalSize; }
int ArchivePreviewModel::totalEntries() const { return m_totalEntries; }
bool ArchivePreviewModel::truncated() const { return m_truncated; }
bool ArchivePreviewModel::loading() const { return m_loading; }
QString ArchivePreviewModel::error() const { return m_error; }

void ArchivePreviewModel::readArchive() {
    // Increment generation to invalidate any in-flight async results
    const int generation = ++m_generation;

    // Clear current state
    if (!m_entries.isEmpty()) {
        beginResetModel();
        m_entries.clear();
        endResetModel();
    }

    m_fileCount = 0;
    m_dirCount = 0;
    m_totalEntries = 0;
    m_totalSize = 0;
    m_truncated = false;

    const bool hadError = !m_error.isEmpty();
    m_error.clear();

    if (m_filePath.isEmpty()) {
        m_loading = false;
        emit loadingChanged();
        emit dataReady();
        if (hadError) emit errorChanged();
        return;
    }

    m_loading = true;
    emit loadingChanged();
    emit dataReady();
    if (hadError) emit errorChanged();

    const QString path = m_filePath;
    const auto future = QtConcurrent::run([path]() {
        return readArchiveContents(path);
    });

    auto* watcher = new QFutureWatcher<ArchiveReadResult>(this);
    connect(watcher, &QFutureWatcher<ArchiveReadResult>::finished, this,
        [this, generation, watcher]() {
            watcher->deleteLater();

            // Discard stale results — user navigated to a different file
            if (generation != m_generation)
                return;

            const auto result = watcher->result();

            beginResetModel();
            m_entries = result.entries;
            endResetModel();

            m_fileCount = result.fileCount;
            m_dirCount = result.dirCount;
            m_totalSize = result.totalSize;
            m_totalEntries = result.totalEntries;
            m_truncated = result.truncated;
            m_loading = false;

            const bool hasError = !result.error.isEmpty();
            if (hasError)
                m_error = result.error;

            emit loadingChanged();
            emit dataReady();
            if (hasError) emit errorChanged();
        });
    watcher->setFuture(future);
}

} // namespace symmetria::models
