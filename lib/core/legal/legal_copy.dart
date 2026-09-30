/// In-app legal copy. Hosted pages can replace this later; until then the
/// app itself is the source of truth so a missing website cannot hide it.
class LegalCopy {
  LegalCopy._();

  static const String shortDisclaimer =
      'Relative fullness is a Gemini model estimate of the complete meal, with assumed portions and preparation. '
      'A rough fullness-time range, when shown, assumes one regular meal and is an unvalidated model estimate, not a personal hunger forecast. It does not predict focus or blood sugar and is not medical advice. '
      'EvenPlate is not a medical device.';

  static const String privacyTitle = 'Privacy Policy';
  static const String termsTitle = 'Terms of Use';

  static const String privacyBody = '''
Last updated: 28 September 2026

EvenPlate is a satiety coaching app. This policy describes what the app collects and why.

What we collect
- Account: the email address you use to create or sign in to an account.
- User ID: an account identifier links your sign-in, saved meal diary, purchase access, opted-in notifications, and diagnostic reports. We use it to provide account features and measure purchases and notification activity.
- Photos: meal photos you choose to scan. They are sent to our backend and to Google Gemini Vision to produce a satiety analysis. We do not use your photos for advertising.
- Typed foods: names you type when building or editing a plate. They are sent to our backend and to Google Gemini to assess the complete selected meal. For edits, the original meal analysis is included as context, without uploading the photo again. Each new complete-plate assessment uses one food-score credit. Selecting chips, reusing an exact cached assessment, and opening a logged plate do not. We do not use food names for advertising.
- Nutrition and wellbeing information: meal names, meal times, meal assessments, and optional post-meal energy check-ins form your meal diary. These are health-related information about your eating patterns and how you feel after eating, even though we do not access medical records or HealthKit. Meal diary entries, including energy check-ins, sync to Supabase and are linked to your account. We use them to provide your diary, history, and personalised insights. Goals and dietary preferences customise coaching and are stored on device in encrypted Hive boxes. Saved photos remain encrypted on this device and are not backed up to your account.
- Free allowance protection: a server-keyed hash of your email groups equivalent personal Gmail addresses (including plus aliases and dotted variants). A weekly usage record prevents account deletion or aliases from resetting free credits. The hash is pseudonymous personal data, not anonymous data. We do not combine meal histories or sign-in credentials between accounts.
- Device identifiers: if you opt in to notifications, OneSignal receives an app-specific device push token and subscription identifier so it can deliver notifications and measure sessions and notification interactions. We associate that notification record with your account. Separately, Apple DeviceCheck verifies an iPhone using an ephemeral device token and two device flags. When enabled, two distinct mailboxes can qualify for free access on each iPhone. For this eligibility check, we retain a keyed mailbox hash and qualification expiry, not a permanent device identifier. Device identifiers are not used for advertising tracking. Verification is separate from advertising and does not merge accounts.
- Purchases: handled by Apple, Google, and RevenueCat. RevenueCat processes purchase history and an account identifier for subscription and credit access, receipt validation, fraud prevention, and purchase analytics. We store access status and credit balances, not your card number.
- Notifications: only if you opt in. OneSignal then receives a device push token, subscription and account identifiers, and two tags (persona and Pro status). It also collects device and operating-system information, session activity, and notification interactions to deliver notifications and measure their use. OneSignal may collect consumable purchase events for purchase analytics. These records can be linked to your account.
- Diagnostics: if crash reporting is configured, Sentry receives crash and error reports, stack traces, app version, device and operating-system information, diagnostic breadcrumbs, and sampled scan-performance timings. Reports include an opaque account id when you are signed in, so they can be linked to your account. We use this information to diagnose failures and improve reliability and performance. The analyze-plate and analyze-foods functions may also send a failure code and a Gemini finish reason. Meal photos, food lists, and email are not sent.

What we do not collect
- Weight, lab results, prescriptions, or HealthKit/Google Fit data.
- Precise location. Location metadata is removed from uploaded meal photos.
- Tracking identifiers for advertising. We do not use collected data for cross-app advertising tracking. We do not sell personal data.

Who processes data
- Supabase (EU or the region of the linked project) for auth, profiles, and meal history.
- Google Gemini for food identification and meal estimates.
- Apple for DeviceCheck verification and device qualification flags.
- RevenueCat for subscriptions.
- OneSignal for push, only after you consent.
- Sentry for crash and reliability reports, only when a DSN is configured in the build or on the analyze-plate and analyze-foods functions.

Retention
- Meal history stays until you delete entries or your account. Analysis retry records expire after seven days.
- Weekly free-usage records remain until the next Monday at 00:00 UTC, then expire and are removed by an hourly cleanup (within one hour). They contain a keyed email hash, week and credit counts, without your meals, photos or profile. This limited record can survive account deletion to prevent repeat free allowances.
- Device qualifications remain for 12 months after qualification, including after account deletion, and expire without extending on sign-in. Expired hashes are removed by a minute-by-minute cleanup. Support can recover eligibility for shared or second-hand phones or after expiry. Apple device flags do not reset with the weekly allowance. Pending encrypted verification tokens are purged after 15 minutes (within one additional minute); successful admission deletes them immediately. Verification receipts expire after one hour.
- Delete Account in Settings removes the auth account, profile, server meals, and local history, except for the limited weekly usage and 12-month device-qualification records described above. Purchase records that stores must retain follow their policies. Deleting the app alone does not delete your account.
- Remote scoring requires separate consent before the first upload. You can withdraw it in Settings. This prevents future uploads; it does not undo processing that already happened.

Contact
Email evenplatesupport@gmail.com for support, privacy questions, or deletion requests.
''';

  static const String termsBody = '''
Last updated: 27 September 2026

By using EvenPlate you agree to these terms.

The service
EvenPlate estimates how filling a photographed meal may be. Results are coaching hints, not nutrition facts, calorie counts, or clinical guidance. The relative score and optional hours range are separate Gemini model estimates. The rough hours range assumes one regular-sized meal and has not been validated against measured hunger outcomes. Portion size, recipe, activity and individual differences can change the result. It is not a guarantee of when hunger will return; do not delay eating or ignore hunger cues because of an estimate. You are responsible for your own eating decisions, allergies, and medical care.

Accounts
You sign in with email. You are responsible for the credentials you choose. Progress is tied to that account. Free allowances renew weekly on Monday at 00:00 UTC. Equivalent personal Gmail addresses share the remaining free allowance for the week; account deletion and registration do not refill it. Paid entitlements and purchased credits remain account-specific. When device protection is enabled, each iPhone can qualify two distinct free-account mailboxes. Each qualified account retains its normal weekly allowance; deleting an account or using an equivalent Gmail alias does not reopen a device slot. Qualification lasts 12 months, after which support can recover eligibility. Additional accounts can sign in and use paid access.

Subscriptions
Paid access is sold through the App Store or Google Play via RevenueCat. Billing, refunds, and cancellation follow the store's rules, not a custom EvenPlate checkout. A promo code, if provided, may grant time-limited Pro access on the server and is not a store purchase.

Privacy
Our Privacy Policy describes how account information, meal photos, health-related meal diary and energy check-in information, purchases, notifications, and diagnostics are processed. You can read it in Settings or at https://evenplateapp.xyz/privacy. Remote meal analysis requires separate consent, which you can withdraw in Settings.

Acceptable use
Do not upload photos of other people without their permission. Do not attempt to bypass scan quotas or forge entitlements.

Disclaimer
EVENPLATE IS PROVIDED AS IS. We do not warrant that estimates are accurate for every plate, lighting condition, or body. Nothing in the app is medical advice.

Changes
We may update these terms in a later app version. Continued use after an update that you are shown in the app is acceptance of the new terms.
''';
}
