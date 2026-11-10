import 'dart:async';

import 'package:googleapis/drive/v3.dart' as drive;

/// A document folder found in the cloud.
class RemoteDocFolder {
  RemoteDocFolder({required this.folderId, required this.docId, this.modifiedAt});

  final String folderId;
  final String docId;

  /// The document's modifiedAt when it was last fully uploaded.
  final DateTime? modifiedAt;
}

/// The few cloud-storage operations sync needs. Implemented for Google Drive
/// below and by an in-memory fake in tests.
abstract class CloudDrive {
  /// Returns the app's root folder, reusing [knownId] when it still exists.
  Future<String> ensureRootFolder(String name, {String? knownId});

  Future<List<RemoteDocFolder>> listDocFolders(String rootId);

  Future<String> createDocFolder(String rootId, {required String docId, required String name});

  /// Renames the folder and records [modifiedAt]; called after all of the
  /// document's files are uploaded, so a half-finished upload never looks
  /// complete to other devices.
  Future<void> commitDocFolder(String folderId, {required String name, required DateTime modifiedAt});

  /// File name -> file id for the files directly inside [folderId].
  Future<Map<String, String>> listFiles(String folderId);

  /// Creates (or overwrites, when [fileId] is given and still exists) a file.
  Future<String> putFile(String folderId, String name, List<int> bytes,
      {required String mimeType, String? fileId});

  Future<List<int>> download(String fileId);

  /// Moves a file or folder to the trash. Missing ids are ignored.
  Future<void> trash(String fileId);
}

/// Google Drive (v3) backend. Uses the `drive.file` scope, so the app only
/// ever sees files and folders it created itself.
class GoogleDriveCloud implements CloudDrive {
  GoogleDriveCloud(this.api);

  final drive.DriveApi api;

  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _idKey = 'scancraftId';
  static const _modifiedKey = 'modifiedAt';

  static bool _isNotFound(Object e) => e is drive.DetailedApiRequestError && e.status == 404;

  @override
  Future<String> ensureRootFolder(String name, {String? knownId}) async {
    if (knownId != null) {
      try {
        final f = await api.files.get(knownId, $fields: 'id,trashed') as drive.File;
        if (f.trashed != true) return knownId;
      } catch (e) {
        if (!_isNotFound(e)) rethrow;
      }
    }
    final escaped = name.replaceAll("'", r"\'");
    final found = await api.files.list(
      q: "name = '$escaped' and mimeType = '$_folderMime' and 'root' in parents and trashed = false",
      $fields: 'files(id)',
      spaces: 'drive',
    );
    final existing = found.files;
    if (existing != null && existing.isNotEmpty) return existing.first.id!;
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = _folderMime,
      $fields: 'id',
    );
    return created.id!;
  }

  @override
  Future<List<RemoteDocFolder>> listDocFolders(String rootId) async {
    final result = <RemoteDocFolder>[];
    String? pageToken;
    do {
      final page = await api.files.list(
        q: "'$rootId' in parents and mimeType = '$_folderMime' and trashed = false",
        $fields: 'nextPageToken, files(id, appProperties)',
        pageSize: 200,
        pageToken: pageToken,
        spaces: 'drive',
      );
      for (final f in page.files ?? const <drive.File>[]) {
        final props = f.appProperties ?? const {};
        final docId = props[_idKey];
        if (docId == null) continue; // not one of ours
        final modified = props[_modifiedKey];
        result.add(RemoteDocFolder(
          folderId: f.id!,
          docId: docId,
          modifiedAt: modified == null ? null : DateTime.tryParse(modified),
        ));
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return result;
  }

  @override
  Future<String> createDocFolder(String rootId, {required String docId, required String name}) async {
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = _folderMime
        ..parents = [rootId]
        ..appProperties = {_idKey: docId},
      $fields: 'id',
    );
    return created.id!;
  }

  @override
  Future<void> commitDocFolder(String folderId, {required String name, required DateTime modifiedAt}) async {
    await api.files.update(
      drive.File()
        ..name = name
        ..appProperties = {_modifiedKey: modifiedAt.toIso8601String()},
      folderId,
    );
  }

  @override
  Future<Map<String, String>> listFiles(String folderId) async {
    final result = <String, String>{};
    String? pageToken;
    do {
      final page = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields: 'nextPageToken, files(id, name)',
        pageSize: 500,
        pageToken: pageToken,
        spaces: 'drive',
      );
      for (final f in page.files ?? const <drive.File>[]) {
        result[f.name!] = f.id!;
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return result;
  }

  @override
  Future<String> putFile(String folderId, String name, List<int> bytes,
      {required String mimeType, String? fileId}) async {
    drive.Media media() => drive.Media(Stream.value(bytes), bytes.length, contentType: mimeType);
    if (fileId != null) {
      try {
        final updated = await api.files.update(drive.File()..name = name, fileId, uploadMedia: media(), $fields: 'id');
        return updated.id!;
      } catch (e) {
        if (!_isNotFound(e)) rethrow;
      }
    }
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..parents = [folderId],
      uploadMedia: media(),
      $fields: 'id',
    );
    return created.id!;
  }

  @override
  Future<List<int>> download(String fileId) async {
    final media = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  @override
  Future<void> trash(String fileId) async {
    try {
      await api.files.update(drive.File()..trashed = true, fileId);
    } catch (e) {
      if (!_isNotFound(e)) rethrow;
    }
  }
}
