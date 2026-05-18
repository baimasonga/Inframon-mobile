# InfraMon Mobile Deployment Guide

This guide outlines the steps to build and distribute the InfraMon Field Tool for production use.

## 1. Production Validation
Before building, ensure `lib/main.dart` contains your production Supabase credentials.

```dart
await Supabase.initialize(
  url: 'https://your-project.supabase.co',
  anonKey: 'your-production-anon-key',
);
```

## 2. Android Deployment (Release)

### A. Create a Keystore
Run this command in your terminal to generate a signing key:
`keytool -genkey -v -keystore c:/Users/USER/upload-keystore.jks -storetype RSA -keysize 2048 -validity 10000 -alias upload`

### B. Configure `android/key.properties`
Create a file at `android/key.properties` with these contents:
```properties
storePassword=your-password
keyPassword=your-password
keyAlias=upload
storeFile=c:/Users/USER/upload-keystore.jks
```

### C. Build the App
Run the following command in the root of the mobile app:
- **For Play Store**: `flutter build appbundle`
- **For Direct Install (APK)**: `flutter build apk --split-per-abi`

The files will be located in `build/app/outputs/flutter-apk/`.

---

## 3. iOS Deployment

> [!NOTE]
> iOS builds require a Mac with Xcode installed.

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select your development team in **Signing & Capabilities**.
3. Run `flutter build ipa`.
4. The `.ipa` file will be generated in `build/ios/ipa/`.

---

## 4. Internal Distribution (Recommended)
Since this is a government/enterprise tool, we recommend using **Firebase App Distribution**:

1. Create a project in the [Firebase Console](https://console.firebase.google.com/).
2. Enable "App Distribution".
3. Upload your `.apk` or `.ipa` file.
4. Add your inspectors' email addresses; they will receive an invite to download the app directly to their phones.

---

## 5. Troubleshooting
- **Sync Errors**: Ensure the mobile device has internet access during the first "Total Sync."
- **Auth Errors**: Verify that the user has been created in Supabase Auth and promoted via `create_super_admin.sql`.
