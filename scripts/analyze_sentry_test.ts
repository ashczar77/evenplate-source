// Tests DSN parsing and the analyze-plate Sentry payload.
//
// Run with: make test-vision

import {
  analyzeIssuePayload,
  parseSentryDsn,
} from "../supabase/functions/analyze-plate/sentry.ts";

let passed = 0;
let failed = 0;

function check(name: string, actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    passed++;
    console.log(`  PASS  ${name}`);
  } else {
    failed++;
    console.log(`  FAIL  ${name}\n          expected ${e}\n          actual   ${a}`);
  }
}

console.log("\nParsing Sentry DSNs");

check("blank is ignored", parseSentryDsn(""), null);
check("spaces only are ignored", parseSentryDsn("   "), null);
check(
  "EU ingest DSN becomes a store URL",
  parseSentryDsn(
    "https://pub@o1.ingest.de.sentry.io/99",
  )?.storeUrl,
  "https://o1.ingest.de.sentry.io/api/99/store/",
);
check(
  "public key is kept",
  parseSentryDsn("https://pub@o1.ingest.de.sentry.io/99")?.sentryKey,
  "pub",
);

const payload = analyzeIssuePayload({
  feature: "analyze.empty",
  code: "GEMINI_EMPTY",
  httpStatus: 502,
  detail: "empty",
  model: "gemini-2.5-flash",
});

check("payload fingerprints the feature", payload.fingerprint, ["analyze.empty"]);
check(
  "payload message keeps the Gemini detail",
  payload.message,
  "analyze.empty: empty",
);
check(
  "payload tags source as the function",
  (payload.tags as { source: string }).source,
  "analyze-plate",
);
check(
  "payload extra has no photo fields",
  Object.keys(payload.extra as object).sort(),
  ["code", "detail", "http_status", "model"].sort(),
);

const foodsPayload = analyzeIssuePayload({
  feature: "foods.timeout",
  code: "GEMINI_TIMEOUT",
  httpStatus: 504,
  source: "analyze-foods",
});

check(
  "typed-food failures tag analyze-foods",
  (foodsPayload.tags as { source: string }).source,
  "analyze-foods",
);
check("typed-food logger is the function", foodsPayload.logger, "analyze-foods");

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) {
  throw new Error(`${failed} analyze sentry test(s) failed`);
}
