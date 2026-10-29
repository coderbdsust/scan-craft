import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scancraft/main.dart';
import 'package:scancraft/services/document_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scancraft_widget_');
    await DocumentStore.instance.init(root: root);
  });

  tearDown(() async {
    // On Windows a thumbnail read may still hold the file open; a leftover
    // temp folder is harmless.
    try {
      await root.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  testWidgets('empty library shows the empty state and scan actions', (tester) async {
    await tester.pumpWidget(const ScanCraftApp());
    await tester.pump();

    expect(find.text('ScanCraft'), findsOneWidget);
    expect(find.text('No scans yet'), findsOneWidget);
    expect(find.text('Quick Scan'), findsOneWidget);
    expect(find.text('Import File'), findsOneWidget);
    expect(find.text('0 Folders'), findsOneWidget);
  });

  testWidgets('saved documents and folders are listed', (tester) async {
    final store = DocumentStore.instance;
    final page = File('${root.path}/src.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 20, height: 30)));
    late String docId;
    await tester.runAsync(() async {
      final doc = await store.createDocument([page], name: 'Electric bill');
      docId = doc.id;
      final folder = await store.createFolder('Utilities');
      await store.moveToFolder(doc.id, folder!.id);
    });

    await tester.pumpWidget(const ScanCraftApp());
    await tester.pump();

    expect(find.text('Electric bill'), findsOneWidget);
    // Folder card plus the document's folder subtitle.
    expect(find.text('Utilities'), findsNWidgets(2));
    expect(find.text('1 Folder'), findsOneWidget);

    // Search filters the list.
    await tester.enterText(find.byType(TextField), 'nothing-matches');
    await tester.pump();
    expect(find.text('Electric bill'), findsNothing);
    expect(find.text('No matching documents'), findsOneWidget);

    // Starred filter.
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Starred'));
    await tester.pump();
    expect(find.text('Electric bill'), findsNothing);
    await tester.runAsync(() => store.setStarred(docId, true));
    await tester.pump();
    expect(find.text('Electric bill'), findsOneWidget);
  });
}
