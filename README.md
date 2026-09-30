<p align="center">
  <img src="assets/branding/mark.png" alt="EvenPlate mark" width="96">
</p>

<h1 align="center">EvenPlate</h1>

<p align="center">
  <em>Build a more filling plate. No calorie counting.</em>
</p>

EvenPlate helps you explore how meal composition relates to fullness and track
how you feel after eating. Photograph a meal or build a plate from foods, assess
it, and try changes before saving it to your diary.

[Website](https://evenplateapp.xyz) | [Privacy](https://evenplateapp.xyz/privacy) | [Support](mailto:evenplatesupport@gmail.com)

EvenPlate is a Flutter app backed by Supabase. Google Gemini assesses meal
composition, while RevenueCat handles optional subscriptions and credit packs.
The app is currently in App Store review.

## What you can do

- **Scan a meal:** use the camera or photo library to get a relative fullness
  score, an explanation, and suggested additions.
- **Build a plate:** select familiar foods or enter your own descriptions, then
  assess the complete meal with one action.
- **Explore changes:** add or remove suggested foods and custom items. Reassess
  the complete plate rather than adding individual food scores together.
- **See a rough time range:** when available, a secondary estimate describes
  fullness duration for a regular portion.
- **Keep a meal diary:** save assessed meals, revisit results, and track your own
  energy through check-ins and insights.
- **Manage your account:** confirm registration, recover your password, control
  analysis consent and notifications, restore purchases, or delete your account.

The meal guidance uses four approachable food roles: protein, fiber, fat, and
volume. These help explain composition without requiring calorie tracking.

## How assessments work

Gemini assesses the **complete meal** on a relative **0-100 fullness scale**.
Photo scans, plates built from scratch, and edited meals use the same assessment
rubric. Composition, preparation, food form, and estimated portions inform the
assessment. The score is not a measured clinical Satiety Index.

The original scan assessment is preserved. When you change a scanned plate, the
app sends its structured context and the complete selected food descriptions,
without uploading the photo again. Suggested additions have no fixed score or
hours bonus. Removing additions can restore a previously assessed composition
and its exact cached result.

An optional rough fullness range comes from the same model request and assumes
**one regular meal**. It is not calculated by converting the score into hours or
adding durations for individual foods. If the model cannot provide an acceptable
range, the score can still be shown.

Both the score and time range are estimates. The time range has not been
validated against personal hunger outcomes; portions, recipes, and individual
responses vary. EvenPlate does not predict focus, blood sugar, or medical
outcomes. Follow your hunger cues rather than delaying eating based on a range.
Details are available in the app's **About this estimate** and Terms.

### Predictable editing and caching

Selecting foods does not trigger a remote request. **Assess plate** batches the
current selection into one complete-meal assessment. Save becomes available
only after that selection has been assessed; saving does not launch another
assessment.

While edits are pending, the app labels the previous assessment and hides its
outdated time range. All added foods can be removed, including custom entries
and suggested additions. Response-generation checks prevent a late request from
overwriting a newer selection. Failures preserve the selection and show feedback.

Complete assessments are cached by method version, original scan context, and
normalized food descriptions. Repeating the same composition can reuse a result
without another request or credit charge. Different quantities or preparation
text create a different composition. Identical in-flight requests are coalesced.
The encrypted cache is bounded and cleared on sign-out; failed assessments are
not cached.

Historical nutrient-based records remain readable, but new assessments do not
depend on nutrient-catalog matches or combine historical scores with the current
scale.

## Accounts and email

Email confirmation is required. Confirmation and password recovery links have
an HTTPS browser flow, so they can be used on a laptop as well as a phone, with
an option to continue in the app. Password fields clear and return to a masked
state after failed authentication or switching from registration to sign-in.

Authentication email uses Supabase with custom SMTP through Resend. Branded
confirmation and recovery templates are maintained in
[supabase/templates](supabase/templates). Domain authentication and SMTP are
configured for the deployed service. Inbox placement still depends on the
recipient's mail provider and sender reputation.

Browser confirmation, browser recovery, and subsequent phone sign-in have been
verified with fresh links, including rejection of the old password after reset.

## Credits and paid access

| Weekly allowance | Free | Pro |
| --- | ---: | ---: |
| Photo scans | 3 | 75 |
| Complete text-meal assessments | 20 | 100 |

Allowances reset **Monday at 00:00 UTC**. One new whole-meal text assessment uses
one food-score credit, regardless of how many foods it contains. Food selection,
opening saved results, and valid cache hits do not consume assessment credits.
Text assessments also have a 20-request hourly limit per account.

Photo packs contain 25 or 80 credits; food-score packs contain 40. Unused
purchased credits carry over. Prices, subscription renewal details, and trial
eligibility come from the configured store offering rather than fixed promises
in the app. RevenueCat manages purchases and restoration, with server-side
entitlement reconciliation.

### Fair free usage

Free usage is tracked on the server for the current week. Deleting an account
and registering again with the same mailbox does not restart an exhausted free
allowance. Personal Gmail aliases, including dots, plus suffixes, and the
`googlemail.com` variant, share that mailbox's remaining free allowance.
Other providers retain their complete address identity.

This does not merge accounts, passwords, meal history, subscriptions, or purchased
credits. Those remain account-specific. A private ledger retains a keyed mailbox
hash and usage counts through the current week, including after account deletion;
expired entries are removed by scheduled cleanup. It contains no raw email,
photos, or meal history, but is still pseudonymous personal data.

Device-based eligibility restrictions are **enabled on the deployed iOS backend**. Mailbox controls
do not prevent someone from using distinct mailboxes. The implemented DeviceCheck policy allows two qualifying free-account mailboxes
per iPhone, with weekly credits and a separate 12-month qualification record.
After expiry, support can recover eligibility. Apple has accepted a token from
the signed iPhone build. The first live free-account qualification and assessment
passed, and the server saved the qualification without a pending operation.

## Security and reliability

The app and backend include these protections:

- **Server-owned access and quotas:** authenticated functions, database row-level
  security, restricted quota operations, and server-controlled paid entitlements
  prevent clients from granting themselves Pro access or credits.
- **Explicit photo-analysis consent:** account-scoped consent is required before
  sending a meal photo to Gemini and can be withdrawn in Settings. Photos are
  resized and re-encoded before upload to remove original metadata.
- **Validated provider responses:** bounded input and output validation rejects
  malformed assessments. Bounded deadlines and fallback handling limit provider
  failures, while replay-safe reservations prevent duplicate charges and support
  refunds for failed or rejected analysis.
- **Consistent billing:** transaction deduplication, refund handling, webhook
  ordering, and subscription reconciliation protect account balances. Account
  guards isolate login, purchase, restoration, and logout operations.
- **Durable diary synchronization:** encrypted local storage and a persistent
  outbox retain pending changes across restarts. Stable meal IDs, revision checks,
  retry backoff, and visible sync feedback protect edits during interruptions.
- **Account isolation and deletion:** sign-out clears account-scoped cached data
  and guards pending work. Account deletion coordinates cloud data and external
  RevenueCat and OneSignal identities, with retryable failure feedback.
- **Notification controls:** explicit permission, opt-out, and logout cleanup
  govern local reminders and push identity. OneSignal uses a small tag set and
  removes legacy tags to reduce tag-limit conflicts.
- **Privacy-aware diagnostics:** client and function failures carry correlation
  information, with filtered Sentry reporting that excludes meal photos and
  sensitive authentication data. Release builds retain separate debug symbols.
- **Release configuration checks:** validation rejects placeholder release
  configuration. Private provider keys stay on the backend, outside the app binary.

Offline diary work and cached assessments can remain available locally. New
remote assessments, purchases, and cloud synchronization require connectivity.
Photos stored only on a device are not restored from cloud meal history.
Dietary suggestions are not an allergen-safety guarantee.

## Architecture

```text
Flutter app
  |-- Supabase Auth and account-scoped database access
  |-- Authenticated assessment functions --> Gemini
  |-- Billing reconciliation and webhooks --> RevenueCat
  |-- Notification identity --> OneSignal
  |-- Encrypted local diary, cache, and sync outbox
  `-- Filtered diagnostics --> Sentry

HTTPS auth website --> Supabase confirmation and password recovery
Account deletion --> database, Auth, RevenueCat, and OneSignal cleanup
```

| Location | Purpose |
| --- | --- |
| `lib/features/` | Authentication, scanning, meals, insights, and settings |
| `lib/services/` | Assessment, caching, billing, notifications, and synchronization |
| `lib/models/` | Meal, profile, assessment, and fullness-range data |
| `lib/core/` | Theme, configuration, legal copy, and allowance constants |
| `supabase/schema.sql` | Database policies, quotas, billing, and scheduled jobs |
| `supabase/functions/` | Assessments, webhooks, reconciliation, deletion, and legal pages |
| `supabase/templates/` | Confirmation and recovery email templates |
| `docs/auth/` | Browser confirmation and recovery pages |
| `test/` and `scripts/` | App, function, browser-flow, and database checks |

## Development setup

Use the Flutter SDK version pinned in CI and a supported Xcode or Android toolchain.
The backend deployment also requires the Supabase CLI. Function tests use Node.js
and bundled TypeScript helpers.

```bash
make setup
# Fill .env with publishable client configuration.
flutter pub get
make run
```

Use `make run` or pass `--dart-define-from-file=.env` explicitly. Configuration
omitted from a plain `flutter run` will not connect the app to the deployed services.

### Configuration boundaries

Copy [.env.example](.env.example) to `.env` for the Supabase URL and anon key,
RevenueCat platform SDK keys, OneSignal app ID, and Sentry DSN. Everything in this
file can be recovered from a compiled app: **never put private API keys here**.

Copy [supabase/.env.functions.example](supabase/.env.functions.example) to
`supabase/.env.functions` for Gemini, RevenueCat server and webhook credentials,
and OneSignal REST credentials. Both local environment files are ignored by Git.
Private signing keys must also remain untracked and server-side.

Keep `ALLOW_DEV_UNLIMITED_SCANS=false` in production. Legacy USDA catalog
maintenance is optional and is not required for the current assessment path.

### Backend and service setup

1. Create and link a Supabase project. Review and apply
   [supabase/schema.sql](supabase/schema.sql), including policies and scheduled
   quota/recovery jobs. Existing deployments should review incremental migrations
   rather than assume a schema file automatically migrates them.
2. Configure server credentials locally, then run `make secrets-push` and
   `make deploy-functions` against the intended linked project.
3. Configure RevenueCat products, offerings, the `evenplate_pro` entitlement,
   authenticated webhooks, and server reconciliation credentials. Verify real
   store products and restoration before release.
4. Configure OneSignal and Sentry, notification permissions, release symbols,
   and operational alerts.
5. Configure Supabase confirmation, SMTP, redirect allowlists, and email templates.
   Publish the HTTPS browser pages in `docs/auth/` before switching email links.

The client and SQL quota definitions must agree. Allowance and pack constants
live in `lib/core/billing/scan_allowance.dart`.

## Useful commands

```bash
make run                 # Debug app with local configuration
make run-release         # Release-mode app
make check               # Formatting, analysis, app and function tests
make test-functions      # Backend helper and handler checks
make test-db             # Linked database assertions, rolled back afterward
node --test scripts/auth_site_test.mjs
make secrets-push        # Upload configured backend secrets
make deploy-functions    # Deploy assessment, billing, deletion, and legal functions
make build-ios           # Local iOS release build with separate symbols
make build-appbundle     # Android release bundle with configuration validation
```

Database checks require the intended linked project and deployment permissions.
Live smoke scripts create disposable accounts and may invoke paid provider APIs;
they are separate from the isolated test suite. Retain release symbols for crash
symbolication. A local iOS release build is not an uploaded distribution archive.

The iOS release targets exclude OneSignal's unused location module. The
OneSignal 5.6.8 package is pinned under `third_party/onesignal_flutter` with its
Swift package manifest omitting `OneSignalLocation`. Xcode continued to bundle
that framework after a fresh resolution using OneSignal's documented environment
flag, so the local manifest makes this dependency choice deterministic. The
release targets also set the flag for CocoaPods and verify the completed app
bundle before it can be distributed. Retain the package's license when updating
the vendored copy.

## Verification

Run `make check` for formatting, static analysis, Flutter tests, and backend
handler checks. GitHub Actions also runs browser authentication tests, database
assertions, and native build checks. Store purchases, account recovery, camera
permissions, notifications, and offline behavior need physical-device checks.
These checks verify software behavior; they do not establish the clinical
accuracy of fullness estimates.

## Future plans

- **Validate the estimates:** compare predicted fullness ranges with voluntary
  post-meal check-ins, then calibrate or remove estimates that do not help.
- **Make meal history more useful:** add clearer trends and ways to revisit
  meals that left users satisfied.
- **Improve accessibility and localization:** test larger text, screen readers,
  and translations with people who use them.
- **Expand device coverage:** complete Android store and billing verification
  after iOS release.

## Support

For account, billing, or app help, contact
[evenplatesupport@gmail.com](mailto:evenplatesupport@gmail.com).
Privacy and Terms are available in the app and through the deployed legal pages.
Please do not send passwords, authentication links, private API keys, or meal
photos in public bug reports.
