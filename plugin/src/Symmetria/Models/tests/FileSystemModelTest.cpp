#include "../filesystemmodel.hpp"

#include <QAbstractItemModelTester>
#include <QFile>
#include <QImage>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using symmetria::models::FileSystemEntry;
using symmetria::models::FileSystemModel;

class FileSystemModelTest : public QObject {
    Q_OBJECT

    static void writeFile(const QString& path) {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write("text\n"), 5);
    }

    static void writeImage(const QString& path) {
        QImage image(8, 8, QImage::Format_ARGB32);
        image.fill(Qt::red);
        QVERIFY(image.save(path));
    }

    static FileSystemEntry* entryAt(FileSystemModel& model, int index) {
        return model.data(model.index(index), Qt::UserRole).value<FileSystemEntry*>();
    }

private slots:
    void initTestCase() {
        QLocale::setDefault(QLocale("en_US"));
    }

    void listsDialogMetadataAndDirectoriesFirst() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        QVERIFY(QDir(directory.path()).mkdir("z-directory"));
        writeFile(directory.filePath("a.tar.gz"));
        writeFile(directory.filePath(".hidden"));
        writeImage(directory.filePath("b.png"));
        FileSystemModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        model.setPath(directory.path());
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 3);
        QVERIFY(entryAt(model, 0)->isDir());
        const auto* file = entryAt(model, 1);
        QCOMPARE(file->path(), directory.filePath("a.tar.gz"));
        QCOMPARE(file->relativePath(), QString("a.tar.gz"));
        QCOMPARE(file->name(), QString("a.tar.gz"));
        QCOMPARE(file->baseName(), QString("a"));
        QCOMPARE(file->suffix(), QString("tar.gz"));
        QVERIFY(!file->mimeType().isEmpty());
        QVERIFY(entryAt(model, 2)->isImage());
        auto entries = model.entries();
        QCOMPARE(entries.count(&entries), 3);
        QCOMPARE(entries.at(&entries, 1), file);
    }

    void filtersImagesAndRecursesWithoutSymlinkLoops() {
        QTemporaryDir directory;
        QVERIFY(QDir(directory.path()).mkdir("nested"));
        writeImage(directory.filePath("first.png"));
        writeImage(directory.filePath("nested/second.png"));
        writeFile(directory.filePath("not-an-image.png"));
        QVERIFY(QFile::link(directory.path(), directory.filePath("nested/loop")));
        FileSystemModel model;
        model.setFilter(FileSystemModel::Images);
        model.setPath(directory.path());
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 1);
        model.setRecursive(true);
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(entryAt(model, 1)->relativePath(), QString("nested/second.png"));
    }

    void followsNewSubdirectoriesAndRecreation() {
        QTemporaryDir directory;
        FileSystemModel model;
        model.setRecursive(true);
        model.setFilter(FileSystemModel::Images);
        model.setPath(directory.filePath("walls"));
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 0);
        QVERIFY(QDir(directory.path()).mkpath("walls/nested"));
        writeImage(directory.filePath("walls/nested/a.png"));
        QTRY_COMPARE(model.rowCount(), 1);
        writeImage(directory.filePath("walls/nested/b.png"));
        QTRY_COMPARE(model.rowCount(), 2);
        QVERIFY(QDir(directory.filePath("walls")).removeRecursively());
        QTRY_COMPARE(model.rowCount(), 0);
        QVERIFY(QDir(directory.path()).mkdir("walls"));
        writeImage(directory.filePath("walls/new.png"));
        QTRY_COMPARE(model.rowCount(), 1);
        QCOMPARE(entryAt(model, 0)->name(), QString("new.png"));
    }

    void disablesAndReenablesWatching() {
        QTemporaryDir directory;
        writeFile(directory.filePath("a"));
        FileSystemModel model;
        model.setWatchChanges(false);
        model.setPath(directory.path());
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 1);
        writeFile(directory.filePath("b"));
        QTest::qWait(200);
        QCOMPARE(model.rowCount(), 1);
        model.setWatchChanges(true);
        QTRY_COMPARE(model.rowCount(), 2);
        QVERIFY(QFile::remove(directory.filePath("a")));
        QTRY_COMPARE(model.rowCount(), 1);
    }

    void clearsOldPathsAndDiscardsStaleScans() {
        QTemporaryDir first;
        QTemporaryDir second;
        writeFile(first.filePath("old"));
        writeFile(second.filePath("new"));
        FileSystemModel model;
        model.setPath(first.path());
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 1);
        model.setPath(second.path());
        QCOMPARE(model.rowCount(), 0);
        model.setPath(first.path());
        model.setPath(second.path());
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(entryAt(model, 0)->path(), second.filePath("new"));
        model.setPath("");
        QTRY_VERIFY(!model.loading());
        QCOMPARE(model.rowCount(), 0);
    }

    void exposesQmlTypesAndEntries() {
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Symmetria.Models
            Item {
                property FileSystemEntry selected: null
                property alias listing: listing
                FileSystemModel {
                    id: listing
                    recursive: true
                    filter: FileSystemModel.Images
                    watchChanges: true
                }
            }
        )", QUrl());
        QScopedPointer<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
    }
};

QTEST_MAIN(FileSystemModelTest)
#include "FileSystemModelTest.moc"
