# Get Fit

Cross-platform Flutter client management app backed by Supabase. The repository contains the Phase 1 foundation and the Phase 2 workout implementation: trainer-owned client records, workout plans and exercises, assignments, client workout sessions, set logging, and an encrypted offline outbox. Phase 2 code has not been compiled or run against a live backend yet.

## Architecture

- `lib/`: Flutter app and Supabase client integration. The app uses the public anon key only; never put the service-role key in the mobile build.
- `supabase/migrations/`: Postgres schema and row-level security policies.
- `supabase/functions/`: server-side operations that require the service role. Each function verifies the caller and trainer role.
- `profiles`: auth identity and role. A client profile is linked to exactly one trainer.
- `clients`: trainer-owned client data, readable by that trainer and the linked client.
- `client_private_notes`: trainer-only notes isolated from client-visible rows.

## Local Setup

Prerequisites: Flutter 3.24 or newer, the Supabase CLI, and a Supabase project with email auth enabled. For production invitations, configure a verified SMTP provider and the Supabase Auth site URL/redirect settings.

1. Link the Supabase CLI to your project and apply the migration:

   ```powershell
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

2. Deploy the account functions:

   ```powershell
   supabase functions deploy invite-client
   supabase functions deploy delete-client
   ```

   Supabase Edge Functions receive project credentials in their managed environment. Do not copy the service-role key into Flutter, source control, or a client-side `.env` file.

3. Generate the native Flutter runners and configure email-link redirects for your chosen app scheme on Android and iOS. For example, use `getfit://auth-callback` consistently in the native URL handlers and Supabase Auth's allowed redirect URLs. Set the invitation redirect in the Edge Function environment:

   ```powershell
   flutter create . --platforms android,ios
   supabase secrets set CLIENT_APP_REDIRECT_URL=getfit://auth-callback
   ```

   Pass the same redirect at runtime with `--dart-define=AUTH_REDIRECT_URL=getfit://auth-callback` and add it to Supabase Auth's redirect allowlist. Register the URL scheme in both native runners. The production email template must link back to the installed app. Set up Android signing, iOS bundle identifiers, and associated app-link domains before store builds.

4. Install packages and run with the project URL and public anon key:

   ```powershell
   flutter pub get
   flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY --dart-define=AUTH_REDIRECT_URL=getfit://auth-callback
   ```

The app intentionally shows a configuration error when those values are absent. Invitations currently require an email address; phone is stored as optional contact information. No fake records are bundled.

## Phase 1 Checks

Run the app on both platforms after configuring the project and SMTP. Verify these manually against a non-production Supabase project:

- [ ] Email sign-in link completes authentication and session restoration.
- [ ] A new trainer can create a trainer profile; an invited client receives a working invitation.
- [ ] Trainer can find clients by name, email, and goal, and filter active/paused records.
- [ ] Trainer can view and edit client details, pause/resume a client, and maintain private notes.
- [ ] Client can read only their own linked client record; another trainer cannot read or modify it.
- [ ] Client cannot read `client_private_notes` or change `trainer_id` / `profile_id`.
- [ ] Deleting a client removes the auth account and associated profile/client data.
- [ ] Empty, loading, network-error, and retry states behave correctly.

Current verification status: Supabase CLI 2.122.0 is installed, but Flutter/Dart, Docker, and a linked Supabase project were unavailable. Device builds and live backend checks have not been run. Workspace diagnostics reported no issues in the edited Dart, TypeScript, and SQL files; this is not a substitute for compilation or database tests.

## Adding Features

Add each domain table and its RLS policies in a new migration before wiring a screen. Keep service-role operations in Edge Functions, verify the caller and ownership there, and add Realtime publication only for tables whose clients need live updates. Add tests for cross-trainer access whenever a new data relationship is introduced.

## Delivery Status

## Phase 2 Checks

After applying migrations and installing Flutter dependencies, verify these flows on iOS and Android:

- [ ] Trainer creates exercises, builds a plan, changes exercise prescriptions, and assigns it to a client.
- [ ] Client sees only an active plan assigned to their own account and can open its exercise instructions/demo links.
- [ ] Client starts or resumes a workout, logs reps and weight per set, uses the rest timer, and completes the session.
- [ ] With a workout open, enable airplane mode, log sets, close/reopen the app, restore the assignment/session, then reconnect.
- [ ] Pending sessions sync before sets, completion syncs last, and repeated sync does not duplicate records.
- [ ] A client cannot read another client's assignments, plans, sessions, or set logs; a trainer can read only their clients' logs.
- [ ] Rejected writes remain visible as errors and are not silently reported as synced.

Current Phase 2 verification status: not run. Flutter/Dart, Docker, and a linked Supabase project are unavailable in this workspace. The Supabase CLI is installed, but local database lint requires Docker and a running local Supabase stack.

## Delivery Status

Phase 2 workout source is present but unverified. Diet plans and phases 3-5, release builds, push delivery, analytics, scheduling, imports/exports, fees, chat/media, account export/consent flows, localization, and store checklists remain to be implemented. This repository is not a production-ready release.