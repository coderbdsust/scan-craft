import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scancraft/models/scan_document.dart';
import 'package:scancraft/services/document_store.dart';

void main() {
  late Directory root;
  final store = DocumentStore.instance;

  File makePage(String name, {int w = 40, int h = 60}) =>
      File('${root.path}/$name')..writeAsBytesSync(img.encodeJpg(img.Image(width: w, height: h)));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scancraft_store_');
    await store.init(root: root);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('documents persist across reloads with their pages copied in', () async {
    final src = makePage('a.jpg');
    final doc = await store.createDocument([src, makePage('b.jpg')], kind: DocumentKind.idCard);
    await store.rename(doc.id, '  Passport  ');
    await store.addTag(doc.id, 'Travel Docs');
    await store.setNotes(doc.id, 'renew 2030');
    await store.setDpi(doc.id, 600);
    await store.setColorProfile(doc.id, ColorProfile.grayscale);

    src.deleteSync(); // the store keeps its own copy
    await store.init(root: root);

    final loaded = store.byId(doc.id)!;
    expect(loaded.name, 'Passport');
    expect(loaded.kind, DocumentKind.idCard);
    expect(loaded.tags, ['#travel-docs']);
    expect(loaded.notes, 'renew 2030');
    expect(loaded.dpi, 600);
    expect(loaded.colorProfile, ColorProfile.grayscale);
    expect(loaded.pageCount, 2);
    expect(store.pageFile(loaded, 0).existsSync(), isTrue);
    expect(store.documentBytes(loaded), greaterThan(0));
  });

  test('page add / reorder / replace / remove', () async {
    final doc = await store.createDocument([makePage('1.jpg')]);
    await store.addPages(doc.id, [makePage('2.jpg'), makePage('3.jpg')]);
    expect(doc.pageCount, 3);

    final order = List.of(doc.pages);
    await store.reorderPages(doc.id, 0, 2);
    expect(doc.pages, [order[1], order[2], order[0]]);

    final oldFile = store.pageFile(doc, 1);
    await store.replacePage(doc.id, 1, makePage('new.jpg', w: 10, h: 10));
    expect(oldFile.existsSync(), isFalse);
    expect(doc.pages[1], isNot(order[2]));

    final removed = store.pageFile(doc, 0);
    await store.removePage(doc.id, 0);
    expect(doc.pageCount, 2);
    expect(removed.existsSync(), isFalse);
  });

  test('deleting a folder unfiles its documents; deleting a document removes files', () async {
    final doc = await store.createDocument([makePage('x.jpg')]);
    final folder = await store.createFolder('Taxes');
    await store.moveToFolder(doc.id, folder!.id);
    expect(store.documentsIn(folder.id), hasLength(1));

    await store.deleteFolder(folder.id);
    expect(store.folders, isEmpty);
    expect(store.byId(doc.id)!.folderId, isNull);

    final dir = store.docDir(doc);
    expect(dir.existsSync(), isTrue);
    await store.deleteDocument(doc.id);
    expect(store.byId(doc.id), isNull);
    expect(dir.existsSync(), isFalse);
  });

  test('new documents use the default settings', () async {
    await store.updateSettings((s) {
      s.defaultDpi = 150;
      s.defaultColorProfile = ColorProfile.blackWhite;
    });
    final doc = await store.createDocument([makePage('p.jpg')]);
    expect(doc.dpi, 150);
    expect(doc.colorProfile, ColorProfile.blackWhite);
  });
}
