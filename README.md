# Fishing App Flutter Client

This directory contains the first minimal Flutter app for the fishing app MVP.

## What it includes

- email/password login
- email/password registration
- home screen with visible fishing spots
- latest fishing score label and value on the home list
- add fishing spot flow
- spot detail with latest score and latest weather snapshot
- favorites screen with add/remove favorite actions

## Prerequisites

- Flutter SDK installed locally
- a running Supabase project with the schema from `../supabase/migrations/202603230001_initial_mvp_schema.sql`
- for direct messages, also apply `app/db/migrations/202604140001_direct_messages.sql`

## Run the app

From `app/`, install packages and run the app with Supabase values passed via `--dart-define`.

Exact steps:

```bash
cd /opt/fishing-app/app
flutter pub get
flutter run -d chrome \
  --dart-define=SUPABASE_URL=YOUR_SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

If you omit the `--dart-define` values, the app still starts but shows the built-in missing-configuration screen from `lib/main.dart`.

## Mobile platform folders

This repository now includes the minimal Flutter app structure needed to run on web immediately. If you later want generated Android or iOS runner projects as well, create them locally with your Flutter SDK:

```bash
cd /opt/fishing-app/app
flutter create . --platforms=android,ios
```

That command should preserve the existing `lib/` code.

## Notes

- Registration creates both the auth user and the matching `profiles` row.
- The app assumes RLS is enabled as defined in the existing migration.
- UI is intentionally minimal and focused on the MVP flow.
