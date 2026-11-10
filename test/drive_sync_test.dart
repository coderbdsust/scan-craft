import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scancraft/services/document_store.dart';
import 'package:scancraft/services/sync/cloud_drive.dart';
import 'package:scancraft/services/sync/drive_sync_engine.dart';

class FakeNode {
  FakeNode({required this.name, this.parent, this.bytes, this.docId, this.isFolder = false});
  String name;
  final String? parent;
  List<int>? bytes;
  final String? docId;
  final bool isFolder;
  DateTime? modifiedAt;
  bool trashed = false;
}

/// In-memory stand-in for Google Drive.
class FakeCloud implements CloudDrive {
  final nodes = <String, FakeNode>{};
  var _next = 0;
  String _id() => 'f${_next++}';

  Iterable<MapEntry<String, FakeNode>> live() => nodes.entries.where((e) => !e.value.trashed);

  @override
  Future<String> ensureRootFolder(String name, {String? knownId}) async {
    if (knownId != null && nodes[knownId]?.trashed == false) return knownId;
    for (final e in live()) {
      if (e.value.isFolder && e.value.parent == null && e.value.name == name) return e.key;
    }
    final id = _id();
    nodes[id] = FakeNode(name: name, isFolder: true);
    return id;
  }

  @override
  Future<List<RemoteDocFolder>> listDocFolders(String rootId) async => [
        for (final e in live())
          if (e.value.isFolder && e.value.parent == rootId && e.value.docId != null)
            RemoteDocFolder(folderId: e.key, docId: e.value.docId!, modifiedAt: e.value.modifiedAt),
      ];

  @override
  Future<String> createDocFolder(String rootId, {required String docId, required String name}) async {
    final id = _id();
    nodes[id] = FakeNode(name: name, parent: rootId, docId: docId, isFolder: true);
    return id;
  }

  @override
  Future<void> commitDocFolder(String folderId, {required String name, required DateTime modifiedAt}) async {
    nodes[folderId]!
      ..name = name
      ..modifiedAt = modifiedAt;
  }

  @override
  Future<Map<String, String>> listFiles(String folderId) async => {
        for (final e in live())
          if (!e.value.isFolder && e.value.parent == folderId) e.value.name: e.key,
      };

  @override
  Future<String> putFile(String folderId, String name, List<int> bytes,
      {required String mimeType, String? fileId}) async {
    final existing = fileId == null ? null : nodes[fileId];
    if (existing != null && !existing.trashed) {
      existing
        ..name = name
        ..bytes = bytes;
      return fileId!;
    }
    final id = _id();
    nodes[id] = FakeNode(name: name, parent: folderId, bytes: bytes);
    return id;
  }

  @override
  Future<List<int>> download(String fileId) async => nodes[fileId]!.bytes!;

  @override
  Future<void> trash(String fileId) async {
    nodes[fileId]?.trashed = true;
    // Trashing a folder hides its contents too.
    for (final n in nodes.values) {
      if (n.parent == fileId) n.trashed = true;
    }
  }

  // Helpers for asserting / simulating another device.
  String? folderOf(String docId) =>
      live().where((e) => e.value.docId == docId).map((e) => e.key).firstOrNull;
  Map<String, String> filesOf(String docId) => {
        for (final e in live())
          if (e.value.parent == folderOf(docId)) e.value.name: e.key,
      };
  Map<String, dynamic> metaOf(String docId) =>
      jsonDecode(utf8.decode(nodes[filesOf(docId)['meta.json']]!.bytes!)) as Map<String, dynamic>;
  void writeMeta(String docId, Map<String, dynamic> meta, DateTime modifiedAt) {
    nodes[filesOf(docId)['meta.json']]!.bytes = utf8.encode(jsonEncode(meta));
    nodes[folderOf(docId)!]!.modifiedAt = modifiedAt;
  }
}

void main() {
  late Directory root;
  late FakeCloud cloud;
  final store = DocumentStore.instance;

  DriveSyncEngine engine() => DriveSyncEngine(store: store, cloud: cloud);

  File page(String name) => File('${root.path}/$name')
    ..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scancraft_sync_');
    await store.init(root: root);
    await store.updateSettings((s) => s.syncPdfCopies = false); // keep tests fast
    cloud = FakeCloud();
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  test('uploads new documents with pages, meta and folder name', () async {
    final folder = await store.createFolder('Taxes');
    final doc = await store.createDocument([page('a.jpg'), page('b.jpg')], name: 'Invoice');
    await store.moveToFolder(doc.id, folder!.id);

    final report = await engine().run();

    expect(report.uploaded, 1);
    final files = cloud.filesOf(doc.id);
    expect(files.keys, containsAll(['meta.json', ...doc.pages]));
    expect(cloud.metaOf(doc.id)['folderName'], 'Taxes');
    expect(doc.hasUnsyncedChanges, isFalse);

    // Nothing changed -> nothing uploaded.
    expect((await engine().run()).uploaded, 0);
  });

  test('PDF copies are uploaded when enabled', () async {
    await store.updateSettings((s) => s.syncPdfCopies = true);
    final doc = await store.createDocument([page('a.jpg')], name: 'Lease');
    await engine().run();
    expect(cloud.filesOf(doc.id).keys, contains('Lease.pdf'));
  });

  test('local edits are pushed; replaced pages are swapped remotely', () async {
    final doc = await store.createDocument([page('a.jpg')]);
    await engine().run();
    final oldPage = doc.pages.first;

    await store.setStarred(doc.id, true);
    await store.replacePage(doc.id, 0, page('new.jpg'));
    expect(doc.hasUnsyncedChanges, isTrue);
    expect((await engine().run()).uploaded, 1);

    expect(cloud.metaOf(doc.id)['starred'], isTrue);
    final files = cloud.filesOf(doc.id);
    expect(files.keys, contains(doc.pages.first));
    expect(files.keys, isNot(contains(oldPage)));
  });

  test('deleting locally trashes the Drive copy', () async {
    final doc = await store.createDocument([page('a.jpg')]);
    await engine().run();
    await store.deleteDocument(doc.id);
    expect(store.pendingRemoteDeletes, isNotEmpty);

    final report = await engine().run();
    expect(report.deletedRemote, 1);
    expect(cloud.folderOf(doc.id), isNull);
    expect(store.pendingRemoteDeletes, isEmpty);
  });

  test('documents from another device are downloaded, including pages', () async {
    // Create on "this" device, sync, then wipe local state to act as phone #2.
    final doc = await store.createDocument([page('a.jpg'), page('b.jpg')], name: 'Passport scan');
    await store.addTag(doc.id, 'travel');
    await engine().run();
    final id = doc.id;
    final rootId = store.driveRootFolderId;

    final phone2 = await Directory.systemTemp.createTemp('scancraft_sync_phone2_');
    addTearDown(() => phone2.delete(recursive: true).catchError((_) => phone2));
    await store.init(root: phone2);
    store.driveRootFolderId = rootId;

    final report = await engine().run();
    expect(report.downloaded, 1);
    final copy = store.byId(id)!;
    expect(copy.name, 'Passport scan');
    expect(copy.tags, ['#travel']);
    expect(copy.pageCount, 2);
    expect(store.pageFile(copy, 1).existsSync(), isTrue);
    expect(copy.hasUnsyncedChanges, isFalse);
  });

  test('remote changes are pulled when the device copy is unchanged', () async {
    final doc = await store.createDocument([page('a.jpg')], name: 'Old name');
    await engine().run();

    final meta = cloud.metaOf(doc.id)..['name'] = 'Renamed elsewhere';
    cloud.writeMeta(doc.id, meta, DateTime.now().add(const Duration(minutes: 1)));

    expect((await engine().run()).downloaded, 1);
    expect(store.byId(doc.id)!.name, 'Renamed elsewhere');
  });

  test('conflict: the newest change wins', () async {
    final doc = await store.createDocument([page('a.jpg')], name: 'Base');
    await engine().run();

    await store.rename(doc.id, 'Local edit'); // modifiedAt = now
    final meta = cloud.metaOf(doc.id)..['name'] = 'Remote edit';
    cloud.writeMeta(doc.id, meta, DateTime.now().add(const Duration(hours: 1))); // newer

    await engine().run();
    expect(store.byId(doc.id)!.name, 'Remote edit');

    // Now the local side is newer.
    await store.rename(doc.id, 'Newest local');
    final meta2 = cloud.metaOf(doc.id)..['name'] = 'Stale remote';
    cloud.writeMeta(doc.id, meta2, DateTime.now().subtract(const Duration(hours: 1)));
    await engine().run();
    expect(store.byId(doc.id)!.name, 'Newest local');
    expect(cloud.metaOf(doc.id)['name'], 'Newest local');
  });

  test('deleted on another device and unchanged here -> deleted here', () async {
    final doc = await store.createDocument([page('a.jpg')]);
    // Another uploaded doc, so Drive isn't empty (that case is guarded below).
    final other = await store.createDocument([page('b.jpg')]);
    await engine().run();
    await cloud.trash(cloud.folderOf(doc.id)!);
    await engine().run();

    expect(store.byId(doc.id), isNull);
    expect(store.byId(other.id), isNotNull);
  });

  test('locked documents never stay in Drive', () async {
    final doc = await store.createDocument([page('a.jpg')]);
    await engine().run();
    expect(cloud.folderOf(doc.id), isNotNull);

    await store.setLocked(doc.id, true);
    await engine().run();
    expect(cloud.folderOf(doc.id), isNull);
    expect(store.byId(doc.id), isNotNull, reason: 'still on the device');

    final secret = await store.createDocument([page('s.jpg')]);
    await store.setLocked(secret.id, true);
    await engine().run();
    expect(cloud.folderOf(secret.id), isNull);
  });

  test('a deleted or emptied Drive folder never wipes the device', () async {
    final a = await store.createDocument([page('a.jpg')]);
    final b = await store.createDocument([page('b.jpg')]);
    await engine().run();

    await cloud.trash(store.driveRootFolderId!); // user deleted "ScanCraft"
    final report = await engine().run();

    expect(store.byId(a.id), isNotNull);
    expect(store.byId(b.id), isNotNull);
    expect(report.uploaded, 2, reason: 're-uploaded into a new folder');
    expect(cloud.folderOf(a.id), isNotNull);
  });
}
