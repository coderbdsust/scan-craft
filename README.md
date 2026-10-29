# ScanCraft

An offline document scanner built with Flutter. Pages are captured, cleaned,
stored and exported entirely on the device — nothing is uploaded.

## Features

- **Camera capture** with live page-edge detection and optional auto-capture
  (AUTO holds steady → shoots; MANUAL → tap the shutter), flash, and a
  rule-of-thirds grid.
- **Scan modes**: Single page, Batch / multi-page, ID card (front + back with a
  card-shaped guide), Book (each shot is split into left/right pages), and
  QR / barcode reading.
- **Crop & clean editor** for every page in a batch: corners pre-placed from edge
  detection, perspective correction, auto-deskew, rotation, Magic Color /
  Clean White / B&W / Grayscale filters, shadow removal, contrast and a
  finger eraser. Settings can be applied to all pages at once.
- **Library**: documents persist between launches; search (name, tags, notes,
  folder), filters (Starred, ID cards, Books, Locked), sorting, list/grid view,
  folders, and real storage usage.
- **Document detail**: rename, star, folders, tags, notes, add / reorder /
  re-edit / remove pages, export resolution (150/300/600 DPI) and colour
  profile.
- **Export & share**: PDF and JPG exports through the system share sheet.
- **Sign**: draw a signature and place it on any page.
- **Biometric lock**: locked documents need Face ID / fingerprint / device PIN
  to open, and only their name is searchable.

## Project layout

```
lib/
  models/      ScanDocument, folders, settings, in-progress ScanSession
  services/    DocumentStore (JSON + files on disk), export, biometric auth
  utils/       image pipeline (warp, filters, deskew, edge detection), formatters
  screens/     home, camera, crop, detail, sign, qr, storage, settings
  widgets/     shared dialogs and document actions
```

Documents live under the app's documents directory in `scancraft/`
(`library.json` plus one folder of page JPEGs per document).

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Platform notes: Android uses `FlutterFragmentActivity` and AppCompat themes
(required by `local_auth`); iOS declares camera, photo library and Face ID usage
strings in `Info.plist`.
