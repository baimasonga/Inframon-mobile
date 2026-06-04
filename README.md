# InfraMon Mobile Field App

InfraMon Mobile is the field data-capture app for the InfraMon web dashboard:
https://web-dashboard-inframon.vercel.app/.

Field inspectors use this app to capture project monitoring data on site. The
app stores entries locally first so inspectors can keep working in poor network
conditions, then syncs queued records to the shared Supabase backend used by the
web dashboard.

## What the mobile app captures

The app is designed to collect the data that the web dashboard processes and
presents, including:

- project inspection reports and milestone updates;
- assigned inspection task status updates;
- issues observed in the field;
- daily workforce records;
- attendance/check-in data;
- inspection photos and location metadata.

## Backend relationship with the web dashboard

The mobile app and web dashboard must point to the same Supabase project:

- mobile uses `SUPABASE_URL` and `SUPABASE_ANON_KEY` at build/run time;
- web uses the matching Vercel environment variables, typically
  `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`;
- the mobile app writes captured field data to Supabase tables/RPCs;
- the web dashboard reads, processes, and displays that same Supabase data.

Never commit Supabase keys to this repository. Keep local values in an
untracked `env.json` file or in CI/deployment secrets.

## Local setup

Create `env.json` in the repository root:

```json
{
  "SUPABASE_URL": "https://<current-shared-project>.supabase.co",
  "SUPABASE_ANON_KEY": "<current anon/public key>"
}
```

Then fetch dependencies and run the app:

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

The app intentionally fails at startup if either Supabase value is missing so a
field build cannot accidentally point to the wrong backend.

## Login troubleshooting after Supabase changes

Supabase Auth users are project-specific. If the mobile app was rebuilt against
a new Supabase project or a rotated key, an inspector who existed in the old
project may receive `invalid_credentials` until their account is created or
reset in the current shared Supabase project used by the web dashboard.

When login fails after a backend change:

1. Check the backend project reference shown at the bottom of the mobile login
   screen.
2. Confirm it matches the Supabase project configured for the web dashboard.
3. In the web app/admin flow or Supabase Auth dashboard, create the inspector
   user or send a password reset for that same email.
4. Retry the mobile login with the new/reset password.

## Build commands

```bash
flutter build apk --split-per-abi --dart-define-from-file=env.json
flutter build appbundle --dart-define-from-file=env.json
```

See [`DEPLOYMENT_MOBILE.md`](DEPLOYMENT_MOBILE.md) and
[`PRODUCTION.md`](PRODUCTION.md) for release and distribution notes.

## Verification checklist before field deployment

1. Confirm the mobile `env.json` Supabase URL matches the web dashboard's Vercel
   Supabase URL.
2. Confirm the anon/public key has been rotated if an old key was exposed or
   replaced.
3. Build a fresh APK/app bundle with `--dart-define-from-file=env.json`.
4. Log in as a field inspector, capture a small test record, sync it, and verify
   that it appears in the web dashboard.
5. Distribute the verified build to inspectors.
