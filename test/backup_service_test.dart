import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scancraft/services/backup_service.dart';
import 'package:scancraft/services/document_store.dart';

void main() {
  final store = DocumentStore.instance;
  final dirs = <Directory>[];

  Future<Directory> freshStore() async {
    final d = await Directory.systemTemp.createTemp('scancraft_backup_');
    dirs.add(d);
    await store.init(root: d);
    return d;
  }

  File page(Directory d, String name) =>
      File('${d.path}/$name')..writeAsBytesSync(img.encodeJpg(img.Image(width: 20, height: 30)));

  tearDown(() async {
    for (final d in dirs) {
      try {
        await d.delete(recursive: true);
      } on FileSystemException catch (_) {}
    }
    dirs.clear();
  });

  test('backup on one phone restores everything on another', () async {
    final phone1 = await freshStore();
    final folder = await store.createFolder('Taxes');
    final doc = await store.createDocument([page(phone1, 'a.jpg'), page(phone1, 'b.jpg')], name: 'Invoice');
    await store.moveToFolder(doc.id, folder!.id);
    await store.addTag(doc.id, 'q4');
    await store.setLocked(doc.id, true);

    final zip = await BackupService(store).createBackup();
    final saved = File('${Directory.systemTemp.path}/sc_test_${DateTime.now().microsecondsSinceEpoch}.zip');
    await zip.copy(saved.path);
    addTearDown(() => saved.delete());

    await freshStore(); // phone 2, empty
    final (added, skipped) = await BackupService(store).restore(saved);

    expect((added, skipped), (1, 0));
    final copy = store.byId(doc.id)!;
    expect(copy.name, 'Invoice');
    expect(copy.tags, ['#q4']);
    expect(copy.locked, isTrue, reason: 'lock survives restore');
    expect(copy.pageCount, 2);
    expect(store.pageFile(copy, 1).existsSync(), isTrue);
    expect(store.folderById(copy.folderId)!.name, 'Taxes');

    // Restoring again keeps what's already there.
    expect(await BackupService(store).restore(saved), (0, 1));
    expect(store.folders, hasLength(1));
  });

  test('rejects files that are not backups and ignores unexpected paths', () async {
    final d = await freshStore();

    final notBackup = Archive()..addFile(ArchiveFile.bytes('hello.txt', Uint8List.fromList([1, 2, 3])));
    final bad = File('${d.path}/bad.zip')..writeAsBytesSync(ZipEncoder().encode(notBackup));
    await expectLater(BackupService(store).restore(bad), throwsA(isA<FormatException>()));

    // A crafted backup trying to escape the restore folder.
    final evil = Archive()
      ..addFile(ArchiveFile.bytes('library.json', Uint8List.fromList('{"documents":[],"folders":[]}'.codeUnits)))
      ..addFile(ArchiveFile.bytes('../../escape.jpg', Uint8List.fromList([1])))
      ..addFile(ArchiveFile.bytes('docs/x/../../../escape2.jpg', Uint8List.fromList([1])));
    final evilZip = File('${d.path}/evil.zip')..writeAsBytesSync(ZipEncoder().encode(evil));
    expect(await BackupService(store).restore(evilZip), (0, 0));
    expect(File('${d.path}/escape.jpg').existsSync(), isFalse);
    expect(File('${store.tempDir.parent.path}/escape.jpg').existsSync(), isFalse);
    expect(File('${store.tempDir.path}/escape2.jpg').existsSync(), isFalse);
  });

  test('backup file name carries the date', () {
    expect(BackupService.fileName(DateTime(2026, 3, 7)), 'ScanCraft-backup-2026-03-07.zip');
  });
}
