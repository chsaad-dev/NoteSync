# Privacy Policy for NoteSync

**Last Updated:** July 2026

Welcome to NoteSync. Your privacy and the security of your data are our highest priorities. NoteSync is built around a local-first, zero-knowledge encryption model. This means that your sensitive data is encrypted on your device before it ever leaves it, and only you hold the keys to decrypt it.

## 1. Information We Collect

### 1.1 Account Information
To sync your data across devices, we require you to create an account. We collect your authentication details, which may include:
- Email address
- Authentication tokens (e.g., from Google Sign-In)

### 1.2 Encrypted Data Syncing
If you choose to sync your notes, the following data is transmitted and stored on our cloud infrastructure (via Firebase):
- **Encrypted Notes:** The titles, bodies, and metadata of your notes are encrypted on your device. We store this encrypted payload, but we cannot read it.
- **Encrypted Media:** Media files (images, etc.) are securely uploaded via our Cloudflare Workers and stored (e.g., on Cloudinary). We only store the encrypted media or secure references to it.

### 1.3 Device and Local Data
Your notes and preferences are stored locally on your device in a secure database (Isar Database). NoteSync functions entirely offline, meaning local data remains on your device until you choose to sync.

## 2. How We Use Your Information

- **To Provide the Service:** We use your account information to authenticate you and facilitate syncing across your devices.
- **Zero-Knowledge Architecture:** We DO NOT have access to your notes, passwords, vault contents, or decryption keys. Because of our zero-knowledge architecture, we cannot read, share, or sell your personal notes.
- **App Functionality:** To ensure smooth functionality, we may use standard analytics to monitor app performance and crash reports, but this does not include any of your encrypted note contents.

## 3. Data Storage and Security

- **Client-Side Encryption:** All notes and media are encrypted client-side using industry-standard encryption before transmission.
- **Cloud Infrastructure:** Encrypted data is securely transmitted and stored using Firebase and Cloudflare.
- **Authentication:** Your account credentials are secured through Firebase Authentication.

## 4. Your Rights and Choices

- **Local Only:** You can use NoteSync entirely offline. If you do not create an account or enable syncing, all your data remains exclusively on your physical device.
- **Data Deletion:** You can delete your account and all associated encrypted cloud data at any time from within the app settings. Once deleted from the cloud, your data cannot be recovered by us.

## 5. Third-Party Services

NoteSync uses the following third-party services to function:
- **Firebase:** For authentication and encrypted data syncing.
- **Cloudflare Workers / Cloudinary:** For secure media upload and storage.
- **Google Play Services:** For Android functionality and Google Sign-In.

These services have their own privacy policies, but please remember that they only ever handle the **encrypted** form of your notes and media.

## 6. Changes to this Policy

We may update this Privacy Policy from time to time as we add new features or as regulatory requirements change. We will notify you of any significant changes within the app.

## 7. Contact Us

If you have any questions about this Privacy Policy or how your data is handled, please contact the developer via our support channels or GitHub repository.
