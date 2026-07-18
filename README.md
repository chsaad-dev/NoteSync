# NoteSync

[![Flutter](https://img.shields.io/badge/Flutter-v3.22+-02569B.svg?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-v3.0+-0175C2.svg?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web-lightgrey.svg)](#)

A secure, offline-first note-taking and synchronization application built using Flutter. NoteSync provides end-to-end data safety by locally encrypting note contents at rest using AES-256 and synchronizing with Firestore through a proxy-signed, zero-trust backend architecture.

---

## Overview

NoteSync is a production-ready personal note-taking application designed for privacy-conscious users who need seamless multi-device synchronization without compromising data security. Unlike typical notes applications that sync plaintext user data to cloud databases, NoteSync operates on a local-first, zero-knowledge encryption model. All notes are fully encrypted on-device before ever being transmitted to the cloud, guaranteeing that only the user holds the keys to read their private thoughts.

Under the hood, NoteSync coordinates a local Isar database instance with a Firestore REST backend via a specialized sync engine. Media uploads (images and videos) are managed securely through a server-side Cloudflare Worker that dynamically generates signed upload tokens, preventing the leakage of API secrets inside the client binary. By combining hardware biometric authentication, active multi-device session management, and password-based offline encrypted ZIP archives, NoteSync sets a high standard for client-side security in mobile environments.

---

## Architecture & Data Flow

NoteSync strictly adheres to **Clean Architecture** principles decoupled into domain, data, and presentation layers, combined with the **MVVM (Model-View-ViewModel)** design pattern powered by Flutter Riverpod.

### Layer Separation
*   **Domain Layer**: Contains the core business entities (`NoteEntity`, `UserProfile`) and use cases (`CreateNote`, `SyncNotes`, `DeleteAccount`). It is written in pure Dart and has zero external dependencies on libraries, database frameworks, or UI systems.
*   **Data Layer**: Contains database adapters, API services, repositories, and data source implementations (`NoteLocalDataSource`, `NoteRemoteDataSource`). It translates remote and local models (DTOs) into clean domain entities.
*   **Presentation Layer**: Composed of reactive views (Screens, Widgets) and ViewModels (Riverpod Notifiers). Views bind directly to the StateNotifiers and reflect state updates reactively.

### Data Flow diagram (Local-First Offline Sync)

```
[ UI / Note Editor Screen ] 
           │ (Reacts to Streams)
           ▼
[ State Management: Riverpod Notifiers ]
           │ (Calls Use Cases)
           ▼
[ Domain Layer: NoteRepository Interface ]
           │
           ▼
[ Data Layer: NoteRepositoryImpl ]
    ├── Writes immediately to ──> [ Isar Local Database (Encrypted-at-Rest) ]
    │
    └── Background Sync Loop (Triggers on Resume, Connectivity, or Timer)
           │
           ├── Checks Firestore REST API via [ Cloudflare Worker Proxy ]
           ├── Resolves Conflicts (Last-Write-Wins or Conflict-Copy copies)
           └── Synchronizes changes back down to local Isar DB
```

---

## Implemented Features

### 1. Core Note Management
*   **Rich Text Editor**: Rich text editing with support for formatting (headers, bold, italics, checklists, lists) using the modern Flutter Quill editor.
*   **Organization**: Organize notes dynamically using folders and tags. Features real-time filtering, note searching, and note pinning.
*   **Soft Delete (Trash)**: Deleting a note moves it to the trash. Notes in the trash are excluded from active search results and local backups, allowing for permanent deletion or restoration.
*   **Private Vault**: A biometric-protected vault folder to lock highly sensitive notes behind native hardware authentication.

### 2. Offline-First Sync Engine
*   **Local-First Writes**: Notes are written immediately to the local Isar database, ensuring instantaneous user feedback.
*   **Two-Way Synchronization**: Automatically merges local database edits with Firestore records. The sync is triggered on application startup, network connectivity recovery, application resume, or via a 2-minute periodic background timer.
*   **Deterministic Conflict Resolution**:
    *   **Last-Write-Wins (LWW)**: Applies when timestamps differ by more than 5 seconds.
    *   **Conflict-Copy**: If changes occur on different devices within 5 seconds, a new note appended with `(conflict copy)` is created alongside the original note to prevent data loss.

### 3. Media Attachments via Cloudinary
*   **Signed Media Uploads**: Secure image and video attachments. Direct access keys are never stored on the client; instead, uploads are proxy-signed by the backend Cloudflare Worker using secure HMAC credentials.
*   **Dynamic Cloud Storage Quota**: User cloud storage limits are enforced dynamically (defaulting to 300MB, fetched from Firestore rules). The Worker validates files on `/sign-upload` and tracks usage inside Firestore on `/commit-upload` and `/delete-media` to prevent quota abuse.

### 4. Advanced Security Infrastructure
*   **AES-256 Client-Side Encryption**: Note bodies are encrypted locally in Isar using AES-256 (via the `encrypt` package). Secret keys are dynamically generated per user and stored securely in Android's Keystore or iOS's Keychain via `FlutterSecureStorage`.
*   **Biometric App Lock**: Secure app-entry lock using face/fingerprint scanners (via `local_auth`).
*   **Worker-Mediated Publishing**: Users can generate public read-only URLs for their notes. Publishing calls Worker POST `/publish-note` and `/unpublish-note` endpoints. These verify user permissions, decrypt the text, and write to a public collections directory using administrative RS256 Firebase tokens. Firestore rules deny direct client writes to public notes.
*   **App Check & Play Integrity**: Firebase App Check integrates with Google Play Integrity to ensure only official, untampered NoteSync app binaries can communicate with remote databases.

### 5. Encrypted Backups
*   **Password-Protected ZIP Exports**: Exports note archives to password-encrypted ZIP files. Encryption keys are derived using PBKDF2 (SHA-256, 600,000 iterations) from user-entered passwords, complying with OWASP security guidelines.
*   **Transaction Metrics**: Restoring from a backup displays transaction metrics (total restored notes, duplicates skipped).

### 6. Active Session Management
*   **Multi-Device Session Tracking**: Lists active login sessions (device model, OS version, last active time, unique ID) inside the settings panel.
*   **Remote Session Revocation**: Logging out of a device remotely immediately signals a live Firestore listener on the target device, triggering a local database wipe, secure storage purge, and account logout.

### 7. Custom Aesthetics
*   **Modern Theme System**: Features a sleek UI with slate/indigo color tokens, dynamic dark mode, OLED Pure Black mode, customizable accent colors, and custom typography configurations.

---

## Tech Stack

| Component | Technology | Version / Package |
| :--- | :--- | :--- |
| **Framework** | Flutter SDK | `^3.22.0` |
| **Language** | Dart | `^3.0.0` |
| **State Management** | Riverpod | `flutter_riverpod: ^2.5.1` |
| **Local Database** | Isar DB | `isar: ^3.1.0` |
| **Authentication** | Firebase Auth | `firebase_auth: ^5.4.0` |
| **Cloud Database** | Cloud Firestore | `cloud_firestore: ^5.4.0` |
| **Secure Key Storage** | Flutter Secure Storage | `flutter_secure_storage: ^10.3.1` |
| **Cryptography** | Dart Encrypt & Crypto | `encrypt: ^5.0.3`, `crypto: ^3.0.3` |
| **Local Auth** | Local Authentication | `local_auth: ^2.3.0` |
| **Rich Text Editor** | Flutter Quill | `flutter_quill: ^11.5.1` |
| **Media Handling** | Image Picker & Video Player | `image_picker: ^1.1.2`, `video_player: ^2.13.0` |
| **System Info / Share**| Share Plus / Connectivity | `share_plus: ^10.1.0`, `connectivity_plus: ^7.2.0` |
| **Backend / Proxy** | Cloudflare Workers | Serverless JavaScript (Wrangler runtime) |

---

## Project Structure

```
.
├── cloudflare_worker/
│   ├── index.js                     # Worker router and endpoint implementations
│   └── wrangler.toml                # Cloudflare Worker project configuration
├── lib/
│   ├── core/
│   │   ├── di/
│   │   │   └── injection_container.dart  # Dependency injection setup (GetIt)
│   │   ├── errors/
│   │   │   ├── failures.dart             # Sealed Failure classes
│   │   │   └── result.dart               # Functional Result type (Success/Failure)
│   │   ├── notifications/
│   │   │   └── notification_manager.dart # Local notification notifications manager
│   │   ├── security/
│   │   │   ├── encryption_service.dart   # AES-256 client-side encrypt/decrypt
│   │   │   └── session_manager.dart      # Active session tracking & revocation
│   │   ├── services/
│   │   │   └── backup_service.dart       # Encrypted ZIP backup/restore
│   │   ├── theme/
│   │   │   └── theme_provider.dart       # Colors, OLED black, custom fonts
│   │   └── utils/
│   │       └── quill_helper.dart         # Quill delta to plain text/HTML mapping
│   ├── data/
│   │   ├── local/
│   │   │   ├── models/
│   │   │   │   └── isar_note_model.dart  # Local DB schema and annotations
│   │   │   └── note_local_data_source.dart # CRUD operations on Isar instance
│   │   ├── models/
│   │   │   └── firestore_note_model.dart # Firestore REST DTO mapping
│   │   ├── remote/
│   │   │   ├── cloudinary_service.dart   # Media upload signed client
│   │   │   └── note_remote_data_source.dart # Firestore Cloud synchronization
│   │   └── repository/
│   │       └── note_repository_impl.dart # Sync engine coordinator
│   ├── domain/
│   │   ├── entities/
│   │   │   ├── note_entity.dart          # Pure business Note representation
│   │   │   └── user_profile.dart         # User parameters and storage details
│   │   ├── repository/
│   │   │   └── note_repository.dart      # Abstract repository interface
│   │   └── usecases/
│   │       └── ...                       # Business actions (e.g. DeleteAccount)
│   ├── presentation/
│   │   ├── screens/
│   │   │   ├── auth/                     # App Lock, Login, SignUp, Reset
│   │   │   ├── folders/                  # Folder editing manager
│   │   │   ├── home/                     # Note grid dashboard and side drawer
│   │   │   ├── note_editor/              # Rich text editor screen
│   │   │   ├── settings/                 # Settings screen and active sessions screen
│   │   │   ├── trash/                    # Deleted notes screen
│   │   │   └── vault/                    # Secure biometric locked vault screen
│   │   ├── widgets/                      # Shared reusable UI elements
│   │   └── providers/                    # Riverpod view models
│   ├── firebase_options.dart             # Generated Firebase configurations
│   └── main.dart                         # App initialization and lifecycle hooks
└── test/                                 # Complete unit and widget tests
```

---

## Setup & Installation

### Prerequisites
*   Flutter SDK `^3.22.0`
*   Dart SDK `^3.0.0`
*   Node.js (for deploying Cloudflare Worker via Wrangler)

---

### Step-by-Step Installation

#### 1. Clone & Install Flutter Packages
```bash
git clone https://github.com/chsaa/NoteSync.git
cd NoteSync
flutter pub get
```

#### 2. Configure Firebase Project
1. Create a project in the [Firebase Console](https://console.firebase.google.com/).
2. Enable **Authentication** (Email/Password & Google Sign-In).
3. Enable **Cloud Firestore** in test mode or with security rules.
4. Install the Firebase CLI and login:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```
5. Configure Firebase locally:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
6. Deploy the Firestore security rules:
   ```bash
   firebase deploy --only firestore:rules
   ```

#### 3. Cloudinary Configuration
1. Register for an account at [Cloudinary](https://cloudinary.com/).
2. Create a **Signed Upload Preset** in settings:
   - Mode: **Signed** (Do not use Unsigned).
   - Record the preset name.

#### 4. Cloudflare Worker Deployment
1. Navigate to the worker folder:
   ```bash
   cd cloudflare_worker
   npm install -g wrangler
   wrangler login
   ```
2. Create a KV namespace for rate limiting:
   ```bash
   wrangler kv:namespace create RATE_LIMIT_KV
   ```
3. Update the returned `id` in your `wrangler.toml` under `[[kv_namespaces]]`.
4. Deploy to Cloudflare:
   ```bash
   wrangler deploy
   ```
5. Configure backend secrets using Wrangler:
   ```bash
   wrangler secret put CLOUDINARY_API_KEY
   wrangler secret put CLOUDINARY_API_SECRET
   wrangler secret put CLOUDINARY_CLOUD_NAME
   wrangler secret put FIREBASE_PROJECT_ID
   wrangler secret put CLIENT_EMAIL
   wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
   ```

#### 5. Local Environment Setup
1. Copy `.env.example` to `.env` in the root:
   ```bash
   cp .env.example .env
   ```
2. Update the values:
   *   `CLOUDFLARE_WORKER_URL`: The URL of your deployed Worker.
   *   `CLOUDINARY_CLOUD_NAME`: Your Cloudinary Cloud Name.
   *   `FIREBASE_PROJECT_ID`: Your Firebase Project ID.

#### 6. Database Code Generation & Run
Generate Isar adapters:
```bash
dart run build_runner build --delete-conflicting-outputs
flutter run
```

---

## Environment Variables

### Client `.env` (Non-Secret Configuration)
Non-secret client variables are located in `.env` at the root of the project:
*   `CLOUDFLARE_WORKER_URL` - Endpoint URL of the deployed Cloudflare Worker proxy.
*   `CLOUDINARY_CLOUD_NAME` - Public name of the Cloudinary media account.
*   `FIREBASE_PROJECT_ID` - Firebase cloud database project ID.

### Cloudflare Worker Secrets (Secure Server-Side Configuration)
Configured securely via `wrangler secret put <KEY>`:
*   `CLOUDINARY_API_KEY` - Cloudinary credential key.
*   `CLOUDINARY_API_SECRET` - Cloudinary credential signing secret.
*   `CLOUDINARY_CLOUD_NAME` - Cloudinary account routing name.
*   `FIREBASE_PROJECT_ID` - Firebase cloud database project ID.
*   `CLIENT_EMAIL` - Google Firebase service account email.
*   `FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY` - RS256 private key PEM.

---

## Testing

NoteSync contains unit and widget tests covering encryption services, conflict resolution, session management, and account switching.

Run the test suite:
```bash
flutter test
```

---

## Screenshots

*Screenshots and demo recordings coming soon.*

---

## Roadmap & Future Scope

### Architecture Constrained Out-Of-Scope Actions
*   **Shared Workspaces / Note Collaboration**: Fully concurrent multi-user editing was intentionally excluded from the v1 architecture. Because NoteSync implements zero-knowledge encryption (where notes are encrypted client-side with keys stored strictly inside each user's secure hardware storage), implementing multi-user collaboration would require a complex key-exchange mechanism (e.g. Diffie-Hellman or double-ratchet key sharing) to safely distribute note encryption keys between authorized users. This is planned for future research and integration.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Author

*   **Muhammad Saad** - [GitHub Profile](https://github.com/chsaa)
