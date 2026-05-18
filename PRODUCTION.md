# Mobile Production & Firebase App Distribution

This guide covers how to build a release version of the InfraMon Mobile App and distribute it securely to inspectors via Firebase.

## 1. Generating the Release APK

Run this command in the `mobile_app` root directory:

```bash
flutter build apk --release
```

The resulting file will be located at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 2. Firebase App Distribution (The Easy Way)

Since you want to avoid Play Store delays, Firebase App Distribution allows you to send the APK directly to inspectors' emails. It is **free** and does not require a subscription.

### A. Initial Setup (One-time)
1. Go to the **[Firebase Console](https://console.firebase.google.com/)**.
2. Click **Add Project** and name it `InfraMon`.
3. Click the **Android Icon** in the middle to register your app.
   - Package name: `com.inframon.system` (Check `android/app/build.gradle`).
4. Skip the Google Services JSON step for now (unless you want Cloud Messaging).

### B. Uploading to Inspectors
1. In the left sidebar, go to **Release & Monitor > App Distribution**.
2. Drag and drop your `app-release.apk` into the box.
3. **Add Testers**: Enter the email addresses of your field inspectors.
4. Click **Distribute**.

### C. Inspector Experience
1. Inspectors will receive an email from "Firebase".
2. They click **Accept Invite**.
3. They follow the instructions to download the **App Tester** utility.
4. The InfraMon app will install directly on their phone.

---

## 3. Bandwidth Optimization Settings

The app is pre-configured for Sierra Leone's mobile networks:
- **Sync Priority**: Only one report is uploaded at a time to prevent bandwidth monopolization.
- **Offline Cache**: Data is saved to the internal SQLite database if the network signal (3G/4G) is low.
- **Manual Sync**: Inspectors can force a sync by tapping the "Sync" icon on the dashboard when they reach a stronger signal area.

---

## 🏗 Maintenance Checklist
- **App Versioning**: Every time you release an update, increment the version number in `pubspec.yaml` (e.g., `1.0.1+2`).
- **Supabase Keys**: Ensure the `main.dart` Supabase URL matches your production project.
