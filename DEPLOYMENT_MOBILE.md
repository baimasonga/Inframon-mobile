# InfraMon Mobile Deployment Guide

This guide outlines the steps to build and distribute the InfraMon Field Tool for production use.

## 1. Supabase Credentials (required for every build/run)

Credentials are **not** stored in source — they live in `env.json` at the repo
root, which is gitignored. The Supabase project is the same one the web
dashboard uses (`NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`).

### One-time setup on a fresh clone

Create `env.json` in the repo root (do NOT commit it):

```json
{
  "SUPABASE_URL": "https://xmkbgqniylgrcudqmkca.supabase.co",
  "SUPABASE_ANON_KEY": "<paste current anon key here>"
}
```

### Daily run / build commands

```bash
flutter run   --dart-define-from-file=env.json
flutter build apk      --split-per-abi --dart-define-from-file=env.json
flutter build appbundle               --dart-define-from-file=env.json
```

For CI builds the easiest path is to write `env.json` from a secret at the
start of the job, then pass the same flag.

If `env.json` is missing or either value is empty the app will fail fast on
startup with a clear `StateError` — intentional, to prevent accidentally
shipping a build pointed at the wrong project.

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

`key.properties` and `*.jks` are gitignored — never commit them.

### C. Build the App
Run from the root of the mobile app (uses `env.json` from §1):
- **For Play Store**: `flutter build appbundle --dart-define-from-file=env.json`
- **For Direct Install (APK)**: `flutter build apk --split-per-abi --dart-define-from-file=env.json`

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

## 5. Rotating the Supabase Anon Key

The mobile app and the web dashboard at https://web-dashboard-inframon.vercel.app/
share one Supabase project (`xmkbgqniylgrcudqmkca`). Any prior anon key that was
committed to source (now removed in commit `2ac1e7c`) remains recoverable from
git history, so it MUST be rotated before the next field deployment.

Run the rotation as a single coordinated change — there is a short window where
new key is live but old key is still accepted, which is what makes a safe
rollover possible.

1. **Generate a new anon key in Supabase**
   - Go to https://supabase.com/dashboard/project/xmkbgqniylgrcudqmkca/settings/api-keys
   - Under "Project API keys" → "anon / public", click "Roll" (or "Generate new key").
   - Supabase keeps the old key valid for ~24h on a free/pro plan; on enterprise it
     can be invalidated immediately. Confirm the grace period before proceeding.
   - Copy the new key to a password manager. Do NOT paste it into any file in
     either repo.

2. **Update the web dashboard (Vercel)**
   - https://vercel.com/ → web-dashboard project → Settings → Environment
     Variables → `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
   - Replace value, save, redeploy the latest production build. Verify
     `https://web-dashboard-inframon.vercel.app/` loads and login still works.

3. **Update the mobile app build pipeline**
   - Update whatever holds the build-time `--dart-define=SUPABASE_ANON_KEY=...`
     value (CI secret, local `env.json`, internal wiki). DO NOT commit the key.
   - Cut a new mobile build (`flutter build apk --split-per-abi ...`) and
     distribute via Firebase App Distribution (see §4).
   - Inspectors must install the new build before the grace window closes,
     or the old build will lose Supabase access.

4. **Invalidate the old key**
   - Once every active inspector has confirmed they can sync on the new build,
     return to the Supabase dashboard and revoke the previous key.
   - Confirm an old build fails to reach Supabase (expected — that is the
     proof the rotation worked).

5. **Re-audit git history**
   - `git log -S '<first 10 chars of old key>'` to confirm no other commits
     reference the old key.
   - Do not attempt to scrub git history with `git filter-branch` / BFG unless
     you understand the implications for forks and clones — the old key is
     now invalid, so leaving it in history is acceptable.

## 6. Troubleshooting
- **Sync Errors**: Ensure the mobile device has internet access during the first "Total Sync."
- **Auth Errors**: Verify that the user has been created in Supabase Auth and promoted via `create_super_admin.sql`.
