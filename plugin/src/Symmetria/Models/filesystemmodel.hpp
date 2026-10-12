#pragma once

#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QQmlListProperty>
#include <QTimer>
#include <qqmlintegration.h>

namespace symmetria::models {

struct FileEntryData {
    QString path;
    QString relativePath;
    QString name;
    QString baseName;
    QString suffix;
    QString mimeType;
    bool isDir = false;
    bool isImage = false;
    bool operator==(const FileEntryData&) const = default;
};

class FileSystemEntry : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Entries belong to FileSystemModel")
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString relativePath READ relativePath CONSTANT)
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString baseName READ baseName CONSTANT)
    Q_PROPERTY(QString suffix READ suffix CONSTANT)
    Q_PROPERTY(QString mimeType READ mimeType CONSTANT)
    Q_PROPERTY(bool isDir READ isDir CONSTANT)
    Q_PROPERTY(bool isImage READ isImage CONSTANT)

public:
    explicit FileSystemEntry(FileEntryData data, QObject* parent = nullptr);
    QString path() const { return m_data.path; }
    QString relativePath() const { return m_data.relativePath; }
    QString name() const { return m_data.name; }
    QString baseName() const { return m_data.baseName; }
    QString suffix() const { return m_data.suffix; }
    QString mimeType() const { return m_data.mimeType; }
    bool isDir() const { return m_data.isDir; }
    bool isImage() const { return m_data.isImage; }
    const FileEntryData& snapshot() const { return m_data; }

private:
    const FileEntryData m_data;
};

struct DirectoryScan {
    QList<FileEntryData> entries;
    QStringList directories;
};

class FileSystemModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool recursive READ recursive WRITE setRecursive NOTIFY recursiveChanged)
    Q_PROPERTY(bool watchChanges READ watchChanges WRITE setWatchChanges NOTIFY watchChangesChanged)
    Q_PROPERTY(Filter filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QQmlListProperty<symmetria::models::FileSystemEntry> entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

public:
    enum Filter { NoFilter, Images };
    Q_ENUM(Filter)

    explicit FileSystemModel(QObject* parent = nullptr);
    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    QString path() const { return m_path; }
    void setPath(const QString& path);
    bool recursive() const { return m_recursive; }
    void setRecursive(bool recursive);
    bool watchChanges() const { return m_watchChanges; }
    void setWatchChanges(bool watchChanges);
    Filter filter() const { return m_filter; }
    void setFilter(Filter filter);
    QQmlListProperty<FileSystemEntry> entries();
    bool loading() const { return m_loading; }

signals:
    void pathChanged();
    void recursiveChanged();
    void watchChangesChanged();
    void filterChanged();
    void entriesChanged();
    void loadingChanged();

private:
    QString m_path;
    bool m_recursive = false;
    bool m_watchChanges = true;
    Filter m_filter = NoFilter;
    bool m_loading = false;
    quint64 m_generation = 0;
    quint64 m_scanGeneration = 0;
    QList<FileSystemEntry*> m_entries;
    QFileSystemWatcher m_watcher;
    QTimer m_rescanTimer;
    QFutureWatcher<DirectoryScan> m_scan;
    QStringList m_directories;

    void scheduleScan();
    void startScan();
    void finishScan();
    void setLoading(bool loading);
    void updateWatches();
    void replaceEntries(const QList<FileEntryData>& entries);
};

} // namespace symmetria::models
