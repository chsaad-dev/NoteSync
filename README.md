# NoteSync - Secure Offline-First Notes App

NoteSync is a production-grade, offline-first notes application with cloud synchronization built using Flutter, Riverpod, Isar, Firebase, and Cloudinary. Local data is encrypted at rest using AES-256, and Cloudinary media uploads are proxy-signed server-side via a Cloudflare Worker to protect secrets.

---

## Key Features
- **Offline-First CRUD**: All note writes immediately hit Isar local DB and update the UI reactively.
- **Background Sync**: Automatic two-way cloud syncing triggered on app resume, connection recovery, or via a 2-minute periodic timer.
- **Conflict Resolution**: Timestamps within 5 seconds trigger a conflict copy (older note appended with `(conflict copy)`); otherwise, Last-Write-Wins (LWW) applies.
- **Media Upload Proxy**: Images and videos are directly uploaded to Cloudinary via secure signed parameters from a Cloudflare Worker.
- **At-Rest Encryption**: Note bodies are encrypted locally in Isar using AES-256 (via the `encrypt` package) with keys stored in `FlutterSecureStorage`.
- **Biometric Application Lock**: Optional FaceID/Fingerprint/PIN lock via `local_auth`.
- **Account Data Purge**: Deleting an account triggers a secure worker endpoint to delete all Firestore documents and associated Cloudinary assets before signing out.

---

## Repository Architecture

```
lib/
├── core/
│   ├── di/            # Dependency injection (GetIt container)
│   ├── errors/        # Sealed Result type and Failure representations
│   ├── security/      # AES-256 Encryption Service
│   ├── theme/         # Modern Slate/Indigo design system theme tokens
│   └── utils/         # Quill JSON delta parser
├── data/
│   ├── local/         # Isar Note collections and DAOs
│   ├── remote/        # Firestore & Cloudinary media client sources
│   ├── repository/    # NoteRepositoryImpl coordinating local & remote sync
│   └── models/        # DTO converters (FirestoreNoteModel, IsarNoteModel)
├── domain/
│   ├── entities/      # Pure Dart domain classes (NoteEntity)
│   ├── repository/    # Abstract repository interfaces
│   └── usecases/      # Clean architecture business actions (CreateNote, SyncNotes)
├── presentation/
│   ├── screens/       # UI (Login, SignUp, Home Dashboard, Note Editor, Trash, Settings)
│   ├── widgets/       # Shared presentation widgets
│   └── providers/     # State management (Riverpod notifiers)
└── main.dart          # Main application setup and lifecycle observers
```

---

## Installation & Setup

### 1. Firebase Project Setup
1. Create a Firebase project in the [Firebase Console](https://console.firebase.google.com/).
2. Enable **Authentication** (Email/Password & Google Sign-in providers).
3. Enable **Cloud Firestore** and select a server location.
4. Copy [firestore.rules](file:///c:/Users/chsaa/Flutter%20Projects/firestore.rules) into your Firebase Console Rules tab or deploy using Firebase CLI.
5. Register your Flutter app by running `flutterfire configure` (requires Firebase CLI installed).

### 2. Cloudinary Account Setup
1. Register for a free account at [Cloudinary](https://cloudinary.com/).
2. Note down your **Cloud Name**, **API Key**, and **API Secret**.
3. In the Settings dashboard, configure an **Upload Preset**:
   - Mode: **Signed** (Do not use Unsigned uploads).
   - Enforce constraints like max file size or specific allowed formats (e.g. `jpg, png, webp, mp4`).

### 3. Deploying the Cloudflare Worker
The backend proxy manages credentials security, Cloudinary uploads, and account purging.

1. Navigate to the `cloudflare_worker` folder.
2. Initialize wrangler:
   ```bash
   npm install -g wrangler
   wrangler login
   ```
3. Create a KV namespace for rate limiting:
   ```bash
   wrangler kv:namespace create RATE_LIMIT_KV
   ```
   Add the returned `id` to your `wrangler.toml` file under `kv_namespaces`.
4. Deploy the worker:
   ```bash
   wrangler deploy
   ```
5. Set worker secret environment variables in Cloudflare dashboard or via Wrangler:
   ```bash
   wrangler secret put CLOUDINARY_API_KEY
   wrangler secret put CLOUDINARY_API_SECRET
   wrangler secret put CLOUDINARY_CLOUD_NAME
   wrangler secret put FIREBASE_PROJECT_ID
   ```

### 4. Running the Flutter App
1. Copy the `.env.example` to `.env` in the root directory:
   ```bash
   cp .env.example .env
   ```
2. Configure the variables inside `.env`:
   - `CLOUDFLARE_WORKER_URL`: The URL of your deployed Cloudflare Worker.
   - `CLOUDINARY_CLOUD_NAME`: Your Cloudinary Cloud Name.
   - `FIREBASE_PROJECT_ID`: Your Firebase Project ID.
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the code generator to generate database adapters:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
5. Run the app:
   ```bash
   flutter run
   ```

---

## Running Unit Tests

Run the full suite of unit tests verifying Note encryption/decryption, sync conflict LWW resolution, and offline repository merge behaviors:
```bash
flutter test
```
