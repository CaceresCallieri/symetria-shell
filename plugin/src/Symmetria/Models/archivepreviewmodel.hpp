#pragma once

// ArchivePreviewModel — QML element for listing archive contents in a tree view.
//
// Reads archive headers via libarchive (supports zip, tar, 7z, rar, cpio, iso,
// deb, cab, xar, and all compressed variants). Parses flat entry paths into a
// sorted tree structure, then flattens depth-first into a QAbstractListModel
// with roles for name, fullPath, size, isDir, and depth.
//
// Key design decisions:
//
//   1. Plain struct entries (not QObject) — archive entries are read-once,
//      immutable data. A QVector<ArchiveEntryData> avoids QObject overhead
//      for potentially thousands of entries.
//
//   2. Async via QtConcurrent — libarchive must read/decompress headers
//      sequentially, which can take 100ms+ for large compressed archives.
//      A generation counter discards stale results when the user navigates
//      quickly between files.
//
//   3. Entry cap of 5000 — archives with 100K+ entries would create unusably
//      long lists. The model exposes `truncated` and `totalEntries` for a
//      "showing X of Y" indicator.

#include <qabstractitemmodel.h>
#include <qobject.h>
#include <qqmlintegration.h>

namespace symmetria::models {

struct ArchiveEntryData {
    QString name;      // filename component ("file.txt")
    QString fullPath;  // full archive path ("dir/subdir/file.txt")
    qint64  size;      // uncompressed size (0 for directories)
    bool    isDir;
    int     depth;     // 0 = top-level, 1 = one level deep, etc.
};

class ArchivePreviewModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT

    // Input property (set from QML)
    Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY filePathChanged)

    // Output metadata
    Q_PROPERTY(int fileCount READ fileCount NOTIFY dataReady)
    Q_PROPERTY(int dirCount READ dirCount NOTIFY dataReady)
    Q_PROPERTY(qint64 totalSize READ totalSize NOTIFY dataReady)
    Q_PROPERTY(int totalEntries READ totalEntries NOTIFY dataReady)
    Q_PROPERTY(bool truncated READ truncated NOTIFY dataReady)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole,
        FullPathRole,
        SizeRole,
        IsDirRole,
        DepthRole,
    };

    explicit ArchivePreviewModel(QObject* parent = nullptr);

    // QAbstractListModel overrides
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QString filePath() const;
    void setFilePath(const QString& path);

    [[nodiscard]] int fileCount() const;
    [[nodiscard]] int dirCount() const;
    [[nodiscard]] qint64 totalSize() const;
    [[nodiscard]] int totalEntries() const;
    [[nodiscard]] bool truncated() const;
    [[nodiscard]] bool loading() const;
    [[nodiscard]] QString error() const;

    static constexpr int MaxEntries = 5000;

signals:
    void filePathChanged();
    void dataReady();
    void loadingChanged();
    void errorChanged();

private:
    void readArchive();

    QString m_filePath;
    QVector<ArchiveEntryData> m_entries;
    int m_fileCount = 0;
    int m_dirCount = 0;
    int m_totalEntries = 0;
    qint64 m_totalSize = 0;
    bool m_truncated = false;
    bool m_loading = false;
    QString m_error;
    int m_generation = 0;
};

} // namespace symmetria::models
