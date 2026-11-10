/// Colour profile applied when a document is exported.
class ColorProfile {
  static const String color = 'color';
  static const String grayscale = 'gray';
  static const String blackWhite = 'bw';

  static const List<String> values = [blackWhite, color, grayscale];

  static String label(String profile) {
    switch (profile) {
      case blackWhite:
        return 'B&W Doc';
      case grayscale:
        return 'Grayscale';
      default:
        return 'True Color';
    }
  }
}

/// What kind of capture produced a document.
class DocumentKind {
  static const String document = 'document';
  static const String idCard = 'id-card';
  static const String book = 'book';
}

/// Shape cropped pages are stretched to.
class PageShape {
  static const String a4 = 'a4';
  static const String letter = 'letter';
  static const String original = 'original';

  static const List<String> values = [a4, letter, original];

  static String label(String shape) => switch (shape) {
        a4 => 'A4',
        letter => 'US Letter',
        _ => 'Original (as cropped)',
      };

  /// Long/short side ratio for [shape], or 0 to keep the crop's own shape.
  /// ID cards always use the ID-1 card shape (85.6 x 54 mm).
  static double aspect(String shape, String kind) {
    if (shape == original) return 0;
    if (kind == DocumentKind.idCard) return 85.6 / 54;
    return shape == letter ? 11 / 8.5 : 297 / 210;
  }
}

/// A saved, multi-page scan. Page images live in the document's own folder
/// inside the store; [pages] holds their file names in reading order.
class ScanDocument {
  ScanDocument({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
    this.folderId,
    List<String>? tags,
    this.starred = false,
    this.notes = '',
    this.dpi = 300,
    this.colorProfile = ColorProfile.color,
    this.locked = false,
    this.signed = false,
    this.kind = DocumentKind.document,
    DateTime? modifiedAt,
    DocSyncInfo? sync,
  })  : tags = tags ?? [],
        modifiedAt = modifiedAt ?? updatedAt,
        sync = sync ?? DocSyncInfo();

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<String> pages;
  String? folderId;
  final List<String> tags;
  bool starred;
  String notes;
  int dpi;
  String colorProfile;
  bool locked;
  bool signed;
  String kind;

  /// Bumped on every change (including stars, tags, notes); drives sync.
  DateTime modifiedAt;

  /// Google Drive bookkeeping (local only, never uploaded).
  final DocSyncInfo sync;

  int get pageCount => pages.length;

  /// True when the document changed since it was last uploaded or downloaded.
  bool get hasUnsyncedChanges => sync.syncedModifiedAt != modifiedAt;

  /// Shareable metadata written to Drive as meta.json. Device-specific state
  /// (lock, sync ids) stays local; the folder travels by name.
  Map<String, dynamic> toRemoteMeta({String? folderName}) => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'pages': pages,
        'folderName': folderName,
        'tags': tags,
        'starred': starred,
        'notes': notes,
        'dpi': dpi,
        'colorProfile': colorProfile,
        'signed': signed,
        'kind': kind,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pages': pages,
        'folderId': folderId,
        'tags': tags,
        'starred': starred,
        'notes': notes,
        'dpi': dpi,
        'colorProfile': colorProfile,
        'locked': locked,
        'signed': signed,
        'kind': kind,
        'modifiedAt': modifiedAt.toIso8601String(),
        'sync': sync.toJson(),
      };

  factory ScanDocument.fromJson(Map<String, dynamic> j) => ScanDocument(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        pages: (j['pages'] as List).cast<String>().toList(),
        folderId: j['folderId'] as String?,
        tags: (j['tags'] as List? ?? const []).cast<String>().toList(),
        starred: j['starred'] as bool? ?? false,
        notes: j['notes'] as String? ?? '',
        dpi: j['dpi'] as int? ?? 300,
        colorProfile: j['colorProfile'] as String? ?? ColorProfile.color,
        locked: j['locked'] as bool? ?? false,
        signed: j['signed'] as bool? ?? false,
        kind: j['kind'] as String? ?? DocumentKind.document,
        modifiedAt: j['modifiedAt'] == null ? null : DateTime.parse(j['modifiedAt'] as String),
        sync: j['sync'] == null ? null : DocSyncInfo.fromJson(j['sync'] as Map<String, dynamic>),
      );
}

/// Where a document lives in Google Drive and what was last synced.
class DocSyncInfo {
  DocSyncInfo({this.folderId, Map<String, String>? pageFileIds, this.metaFileId, this.pdfFileId, this.syncedModifiedAt})
      : pageFileIds = pageFileIds ?? {};

  /// Drive folder holding this document's files (null = never uploaded).
  String? folderId;

  /// Local page file name -> Drive file id.
  final Map<String, String> pageFileIds;
  String? metaFileId;
  String? pdfFileId;

  /// [ScanDocument.modifiedAt] at the last successful sync.
  DateTime? syncedModifiedAt;

  void reset() {
    folderId = null;
    pageFileIds.clear();
    metaFileId = null;
    pdfFileId = null;
    syncedModifiedAt = null;
  }

  Map<String, dynamic> toJson() => {
        'folderId': folderId,
        'pageFileIds': pageFileIds,
        'metaFileId': metaFileId,
        'pdfFileId': pdfFileId,
        'syncedModifiedAt': syncedModifiedAt?.toIso8601String(),
      };

  factory DocSyncInfo.fromJson(Map<String, dynamic> j) => DocSyncInfo(
        folderId: j['folderId'] as String?,
        pageFileIds: (j['pageFileIds'] as Map? ?? const {}).cast<String, String>(),
        metaFileId: j['metaFileId'] as String?,
        pdfFileId: j['pdfFileId'] as String?,
        syncedModifiedAt: j['syncedModifiedAt'] == null ? null : DateTime.parse(j['syncedModifiedAt'] as String),
      );
}

class DocFolder {
  DocFolder({required this.id, required this.name, required this.createdAt});

  final String id;
  String name;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DocFolder.fromJson(Map<String, dynamic> j) => DocFolder(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

/// User defaults applied to new scans.
class AppSettings {
  AppSettings({
    this.defaultDpi = 300,
    this.defaultColorProfile = ColorProfile.color,
    this.autoCapture = true,
    this.pageShape = PageShape.a4,
    this.syncEnabled = false,
    this.syncWifiOnly = true,
    this.syncPdfCopies = true,
    this.driveAccount,
  });

  int defaultDpi;
  String defaultColorProfile;
  bool autoCapture;
  String pageShape;

  /// Google Drive sync (off until the user connects an account).
  bool syncEnabled;
  bool syncWifiOnly;
  bool syncPdfCopies;
  String? driveAccount; // email of the connected Google account

  Map<String, dynamic> toJson() => {
        'defaultDpi': defaultDpi,
        'defaultColorProfile': defaultColorProfile,
        'autoCapture': autoCapture,
        'pageShape': pageShape,
        'syncEnabled': syncEnabled,
        'syncWifiOnly': syncWifiOnly,
        'syncPdfCopies': syncPdfCopies,
        'driveAccount': driveAccount,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        defaultDpi: j['defaultDpi'] as int? ?? 300,
        defaultColorProfile:
            j['defaultColorProfile'] as String? ?? ColorProfile.color,
        autoCapture: j['autoCapture'] as bool? ?? true,
        pageShape: j['pageShape'] as String? ?? PageShape.a4,
        syncEnabled: j['syncEnabled'] as bool? ?? false,
        syncWifiOnly: j['syncWifiOnly'] as bool? ?? true,
        syncPdfCopies: j['syncPdfCopies'] as bool? ?? true,
        driveAccount: j['driveAccount'] as String?,
      );
}
