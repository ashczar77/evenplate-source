// Pure verification and entitlement logic for the RevenueCat webhook.
// Kept free of Deno and Supabase imports so it can be unit tested directly.

// Access is removed only here. A cancellation just turns off auto renew and the
// subscriber keeps access until the period ends, so revoking on CANCELLATION
// would strip access a customer has already paid for.
export const REVOKE_EVENTS = new Set(["EXPIRATION"]);

// Events that never change entitlement. Acknowledged so RevenueCat stops
// retrying, but no write happens.
export const NON_ENTITLEMENT_EVENTS = new Set([
  "TEST",
  "BILLING_ISSUE",
  "SUBSCRIPTION_PAUSED",
  "INVOICE_ISSUANCE",
  "VIRTUAL_CURRENCY_TRANSACTION",
]);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Compares without an early exit so a wrong value cannot be discovered one
/// character at a time from response timing.
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export interface SignatureResult {
  ok: boolean;
  reason?: string;
}

/// Verifies the X-RevenueCat-Webhook-Signature header, which carries
/// t=<unix seconds>,v1=<hex hmac sha256 of "<t>.<raw body>">.
///
/// rawBody must be the bytes exactly as received. Parsing and re-serialising
/// JSON changes them and makes a valid signature fail.
export async function verifySignature(
  header: string,
  rawBody: string,
  secret: string,
  toleranceSeconds: number,
  nowMs: number = Date.now(),
): Promise<SignatureResult> {
  let timestamp: string | undefined;
  let provided: string | undefined;

  for (const part of header.split(",")) {
    const index = part.indexOf("=");
    if (index === -1) continue;
    const key = part.slice(0, index).trim();
    const value = part.slice(index + 1).trim();
    if (key === "t") timestamp = value;
    if (key === "v1") provided = value;
  }

  if (!timestamp || !provided) {
    return { ok: false, reason: "malformed_signature_header" };
  }

  const sentAt = Number(timestamp);
  if (!Number.isFinite(sentAt)) {
    return { ok: false, reason: "invalid_timestamp" };
  }

  if (Math.abs(Math.floor(nowMs / 1000) - sentAt) > toleranceSeconds) {
    return { ok: false, reason: "timestamp_outside_tolerance" };
  }

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${rawBody}`),
  );

  if (!timingSafeEqual(toHex(signed), provided.toLowerCase())) {
    return { ok: false, reason: "signature_mismatch" };
  }
  return { ok: true };
}

export interface EntitlementDecision {
  decided: boolean;
  isPro?: boolean;
  reason?: string;
}

/// Decides entitlement from the event's own expiry rather than from the event
/// name. This keeps access through cancellations and billing retries, and drops
/// it only once the subscription has actually lapsed.
export function resolveEntitlement(
  event: Record<string, unknown>,
  entitlementId: string,
  nowMs: number = Date.now(),
): EntitlementDecision {
  const type = String(event.type ?? "");
  if (!["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "CANCELLATION", "EXPIRATION", "NON_RENEWING_PURCHASE", "SUBSCRIPTION_EXTENDED", "TEMPORARY_ENTITLEMENT_GRANT", "REFUND_REVERSED"].includes(type)) {
    return { decided: false, reason: `ignored_event:${type}` };
  }

  if (NON_ENTITLEMENT_EVENTS.has(type)) {
    return { decided: false, reason: `ignored_event:${type}` };
  }

  // Confirm the event concerns this app's entitlement before acting on it,
  // including for revocations: an expiry on some other entitlement must not
  // revoke Pro.
  const entitlements = event.entitlement_ids;
  if (!Array.isArray(entitlements)) {
    return { decided: false, reason: "no_entitlement_mapping" };
  }
  if (!entitlements.includes(entitlementId)) {
    return { decided: false, reason: "different_entitlement" };
  }

  if (REVOKE_EVENTS.has(type)) {
    return { decided: true, isPro: false };
  }

  // Null expiry means a lifetime or non renewing purchase.
  const expiresAt = event.expiration_at_ms;
  if (expiresAt === null || expiresAt === undefined) {
    return { decided: true, isPro: true };
  }
  if (typeof expiresAt !== "number") {
    return { decided: false, reason: "unreadable_expiration" };
  }

  return { decided: true, isPro: expiresAt > nowMs };
}

/// Every id RevenueCat associates with the subscriber. A purchase made before
/// sign-in is attributed to a RevenueCat anonymous id, and the real user id
/// appears only among the aliases.
export function packGrant(
  productId: string,
): { photo: number; text: number } | null {
  if (productId === "scan_pack_25") return { photo: 25, text: 0 };
  if (productId === "scan_pack_80") return { photo: 80, text: 0 };
  if (productId === "food_pack_40") return { photo: 0, text: 40 };
  return null;
}

export function candidateUserIds(event: Record<string, unknown>): string[] {
  const raw = [
    event.app_user_id,
    event.original_app_user_id,
    ...(Array.isArray(event.aliases) ? event.aliases : []),
  ];

  const seen = new Set<string>();
  for (const value of raw) {
    if (typeof value === "string" && UUID_PATTERN.test(value)) {
      seen.add(value.toLowerCase());
    }
  }
  return [...seen];
}
