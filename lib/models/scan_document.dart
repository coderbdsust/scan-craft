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
  }) : tags = tags ?? [];

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

  int get pageCount => pages.length;

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
  });

  int defaultDpi;
  String defaultColorProfile;
  bool autoCapture;

  Map<String, dynamic> toJson() => {
        'defaultDpi': defaultDpi,
        'defaultColorProfile': defaultColorProfile,
        'autoCapture': autoCapture,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        defaultDpi: j['defaultDpi'] as int? ?? 300,
        defaultColorProfile:
            j['defaultColorProfile'] as String? ?? ColorProfile.color,
        autoCapture: j['autoCapture'] as bool? ?? true,
      );
}
