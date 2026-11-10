# ScanCraft

A document scanner built with Flutter. Pages are captured, cleaned, stored and
exported on the device. Nothing is uploaded unless you turn on Google Drive
sync.

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
<<<<<<< Updated upstream
- **Save to Google Drive (manual)**: on a document, *Save to Google Drive*
  builds the PDF and opens the system Save screen; pick Google Drive and a
  folder. In *Settings → Backup*, *Back up all documents* saves one `.zip` of
  the whole library the same way, and *Restore from backup* brings it back
  (e.g. after reinstalling or on a new phone). The upload is done by the Drive
  app with your own login: there is no automatic sync, and no Google Cloud setup
  is needed.
=======
- **Google Drive sync** (optional, off by default): two-way sync with a
  `ScanCraft` folder in your Drive. See below.
>>>>>>> Stashed changes

## Project layout

```
lib/
  models/          ScanDocument, folders, settings, in-progress ScanSession
  services/        DocumentStore (JSON + files on disk), export, biometric auth
  services/sync/   Google sign-in, Drive backend, sync engine, sync scheduling
  utils/           image pipeline (warp, filters, deskew, edge detection), formatters
  screens/         home, camera, crop, detail, sign, qr, storage, settings
  widgets/         shared dialogs and document actions
```

<<<<<<< Updated upstream
Documents live under the app's documents directory in `scancraft/`
(`library.json` plus one folder of page JPEGs per document). This is app-private
storage: **uninstalling the app deletes it**, so keep a backup in Drive.
=======
Documents live in the app's private storage under `scancraft/`
(`library.json` plus one folder of page JPEGs per document). **Uninstalling the
app deletes them** unless Drive sync is on.

## Google Drive sync

### How it works

- Turn it on in **Settings → Google Drive sync → Connect Google Drive**.
- Drive layout: `My Drive/ScanCraft/<document name>/` with one JPEG per page,
  `meta.json` (name, tags, notes, folder, …) and, optionally, a ready-to-read
  `<name>.pdf`.
- Permission: the `drive.file` scope only. ScanCraft can only see files it
  created, never the rest of your Drive.
- When it runs: on app start and resume, about 5 s after an edit, every 15
  minutes while the app is open, and on **Sync now**. Wi-Fi only by default.
  Sync runs while the app is open; there is no background sync when it is
  closed.
- Rules:
  - A change on one side is copied to the other.
  - When both sides changed, the newest edit wins.
  - Deleting a document here trashes it in Drive (recoverable from Drive's
    trash).
  - A document deleted on another device is deleted here, but only if it was
    unchanged here.
  - **Locked documents are never uploaded**; locking an uploaded document
    removes it from Drive.
  - If the `ScanCraft` folder disappears or is emptied in Drive, the app
    re-uploads instead of deleting anything on the phone.
- New phone: install, connect the same Google account, and everything
  downloads.
- **Disconnect** stops sync and revokes access; nothing is deleted on either
  side.

### Google Drive sync setup (one time, by the developer)

Sign-in needs OAuth clients from a Google Cloud project. Until they are
provided, Settings shows "Google Drive sync is not set up in this build" and the
rest of the app works normally.

1. In the [Google Cloud console](https://console.cloud.google.com/), create a
   project and **enable the Google Drive API**.
2. **OAuth consent screen**: choose External, fill in the app name and support
   email, and add the scope `.../auth/drive.file`. While the app is in
   *Testing*, add your Google account(s) as test users. `drive.file` is a
   non-sensitive scope, so publishing doesn't need Google's security review.
3. **Credentials → Create OAuth client ID**:
   - **Web application**: copy its client ID. This is the *server client
     ID* that Android sign-in requires.
   - **Android**: package name `com.scanner.scancraft` plus the **SHA-1** of
     each signing key you use. Get the debug one with
     `cd android && ./gradlew signingReport`, and add the release / Play
     App Signing SHA-1 later.
   - **iOS** (if you build for iPhone): bundle ID from Xcode; copy its client
     ID and its *iOS URL scheme* (reversed client ID).
4. iOS only: in `ios/Runner/Info.plist` add a `CFBundleURLTypes` entry whose
   URL scheme is the reversed iOS client ID.
5. Run or build with the IDs:

   ```bash
   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
   ```

   For iOS also pass `--dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>`.
   In Android Studio / VS Code, put the same `--dart-define` in the run
   configuration's additional arguments. These IDs are not secrets, but keep
   them out of git if you prefer.
>>>>>>> Stashed changes

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Platform notes: Android uses `FlutterFragmentActivity` and AppCompat themes
(required by `local_auth`), and compiles Kotlin non-incrementally
(`kotlin.incremental=false`) because the pub cache and project sit on different
drives on Windows. iOS declares camera, photo library and Face ID usage
strings in `Info.plist`.
