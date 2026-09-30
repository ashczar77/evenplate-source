// Tests the RevenueCat webhook verification and entitlement logic.
// Secrets here are generated per run and never leave memory.
//
// Run with: make test-webhook

import {
  candidateUserIds,
  packGrant,
  resolveEntitlement,
  timingSafeEqual,
  verifySignature,
} from "../supabase/functions/revenuecat-webhook/verification.ts";

const ENTITLEMENT = "evenplate_pro";
const SECRET = "test-secret-" + Math.random().toString(36).slice(2);
const TOLERANCE = 300;
const NOW_MS = 1_760_000_000_000;
const NOW_S = Math.floor(NOW_MS / 1000);

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

async function sign(timestamp: number, body: string, secret = SECRET) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${body}`),
  );
  const hex = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `t=${timestamp},v1=${hex}`;
}

function event(overrides: Record<string, unknown> = {}) {
  return {
    id: "evt_1",
    type: "INITIAL_PURCHASE",
    environment: "PRODUCTION",
    app_user_id: "11111111-1111-4111-8111-111111111111",
    original_app_user_id: "11111111-1111-4111-8111-111111111111",
    aliases: ["11111111-1111-4111-8111-111111111111"],
    entitlement_ids: [ENTITLEMENT],
    expiration_at_ms: NOW_MS + 86_400_000,
    ...overrides,
  };
}

console.log("Signature verification");
{
  const body = JSON.stringify({ event: event() });

  check(
    "a correctly signed body is accepted",
    await verifySignature(await sign(NOW_S, body), body, SECRET, TOLERANCE, NOW_MS),
    { ok: true },
  );

  // Signing covers the body, so any change to it must invalidate the signature.
  const header = await sign(NOW_S, body);
  check(
    "a tampered body is rejected",
    await verifySignature(header, body + " ", SECRET, TOLERANCE, NOW_MS),
    { ok: false, reason: "signature_mismatch" },
  );

  check(
    "a signature made with a different secret is rejected",
    await verifySignature(
      await sign(NOW_S, body, "wrong-secret"),
      body,
      SECRET,
      TOLERANCE,
      NOW_MS,
    ),
    { ok: false, reason: "signature_mismatch" },
  );

  // Replay protection: a valid old signature must not be reusable forever.
  check(
    "a signature older than the tolerance is rejected",
    await verifySignature(
      await sign(NOW_S - TOLERANCE - 1, body),
      body,
      SECRET,
      TOLERANCE,
      NOW_MS,
    ),
    { ok: false, reason: "timestamp_outside_tolerance" },
  );

  check(
    "a signature just inside the tolerance is accepted",
    await verifySignature(
      await sign(NOW_S - TOLERANCE + 1, body),
      body,
      SECRET,
      TOLERANCE,
      NOW_MS,
    ),
    { ok: true },
  );

  check(
    "a far future timestamp is rejected",
    await verifySignature(
      await sign(NOW_S + TOLERANCE + 1, body),
      body,
      SECRET,
      TOLERANCE,
      NOW_MS,
    ),
    { ok: false, reason: "timestamp_outside_tolerance" },
  );

  check(
    "a header with no v1 component is rejected",
    await verifySignature(`t=${NOW_S}`, body, SECRET, TOLERANCE, NOW_MS),
    { ok: false, reason: "malformed_signature_header" },
  );

  check(
    "a non numeric timestamp is rejected",
    await verifySignature(`t=abc,v1=deadbeef`, body, SECRET, TOLERANCE, NOW_MS),
    { ok: false, reason: "invalid_timestamp" },
  );

  check("timingSafeEqual matches equal strings", timingSafeEqual("abc", "abc"), true);
  check("timingSafeEqual rejects different strings", timingSafeEqual("abc", "abd"), false);
  check("timingSafeEqual rejects different lengths", timingSafeEqual("abc", "ab"), false);
}

console.log("\nEntitlement decisions");
{
  const decide = (o: Record<string, unknown> = {}) =>
    resolveEntitlement(event(o), ENTITLEMENT, NOW_MS);

  check("initial purchase grants", decide(), { decided: true, isPro: true });
  check("renewal grants", decide({ type: "RENEWAL" }), { decided: true, isPro: true });
  check("uncancellation grants", decide({ type: "UNCANCELLATION" }), {
    decided: true,
    isPro: true,
  });

  // The bug this replaces: cancellation only stops auto renew, so access must
  // continue until the paid period actually ends.
  check("cancellation with time left keeps access", decide({ type: "CANCELLATION" }), {
    decided: true,
    isPro: true,
  });

  check("billing issue does not revoke", decide({ type: "BILLING_ISSUE" }), {
    decided: false,
    reason: "ignored_event:BILLING_ISSUE",
  });
  check("subscription paused does not revoke", decide({ type: "SUBSCRIPTION_PAUSED" }), {
    decided: false,
    reason: "ignored_event:SUBSCRIPTION_PAUSED",
  });

  check("expiration revokes", decide({ type: "EXPIRATION" }), {
    decided: true,
    isPro: false,
  });

  check(
    "a lapsed expiry revokes even on a purchase event",
    decide({ expiration_at_ms: NOW_MS - 1 }),
    { decided: true, isPro: false },
  );

  check(
    "a null expiry is treated as lifetime",
    decide({ expiration_at_ms: null, type: "NON_RENEWING_PURCHASE" }),
    { decided: true, isPro: true },
  );

  // An expiry on someone else's entitlement must not revoke ours.
  check(
    "expiration of a different entitlement is ignored",
    decide({ type: "EXPIRATION", entitlement_ids: ["some_other_tier"] }),
    { decided: false, reason: "different_entitlement" },
  );
  check(
    "a purchase of a different entitlement is ignored",
    decide({ entitlement_ids: ["some_other_tier"] }),
    { decided: false, reason: "different_entitlement" },
  );
  check("an unmapped product is ignored", decide({ entitlement_ids: null }), {
    decided: false,
    reason: "no_entitlement_mapping",
  });
  check("a test event is ignored", decide({ type: "TEST" }), {
    decided: false,
    reason: "ignored_event:TEST",
  });
}

console.log("\nUser id resolution");
{
  const real = "22222222-2222-4222-8222-222222222222";

  check("a plain user id is used", candidateUserIds(event()), [
    "11111111-1111-4111-8111-111111111111",
    ]);

  // A purchase made before sign-in is attributed to a RevenueCat anonymous id,
  // with the real user id only present among the aliases.
  check(
    "the real id is recovered from aliases",
    candidateUserIds(
      event({
        app_user_id: "$RCAnonymousID:abc123",
        original_app_user_id: "$RCAnonymousID:abc123",
        aliases: ["$RCAnonymousID:abc123", real],
      }),
    ),
    [real],
  );

  check(
    "non uuid ids are discarded",
    candidateUserIds(
      event({
        app_user_id: "$RCAnonymousID:abc123",
        original_app_user_id: "not-a-uuid",
        aliases: ["also-not-a-uuid"],
      }),
    ),
    [],
  );

  check(
    "ids are deduplicated and lowercased",
    candidateUserIds(
      event({
        app_user_id: real.toUpperCase(),
        original_app_user_id: real,
        aliases: [real],
      }),
    ),
    [real],
  );

  check(
    "a missing aliases array is tolerated",
    candidateUserIds({ app_user_id: real }),
    [real],
  );
}

console.log("\nConsumable packs");
{
  check("scan_pack_25 grants 25 photo", packGrant("scan_pack_25"), {
    photo: 25,
    text: 0,
  });
  check("scan_pack_80 grants 80 photo", packGrant("scan_pack_80"), {
    photo: 80,
    text: 0,
  });
  check("food_pack_40 grants 40 text", packGrant("food_pack_40"), {
    photo: 0,
    text: 40,
  });
  check("a subscription id is not a pack", packGrant("evenplate_pro"), null);
}

console.log(`\npassed: ${passed}   failed: ${failed}`);
if (failed > 0) {
  throw new Error(`${failed} webhook verification test(s) failed`);
}
