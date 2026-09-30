import { reportAnalyzeIssue } from "../analyze-plate/sentry.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  candidateUserIds,
  packGrant,
  resolveEntitlement,
  timingSafeEqual,
  verifySignature,
} from "./verification.ts";

// Replay window for signed deliveries.
const SIGNATURE_TOLERANCE_SECONDS = 300;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const signingSecret = Deno.env.get("REVENUECAT_SIGNING_SECRET") ?? "";
  const authSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  const entitlementId = Deno.env.get("REVENUECAT_ENTITLEMENT") ??
    "evenplate_pro";
  const allowSandbox =
    (Deno.env.get("REVENUECAT_ALLOW_SANDBOX") ?? "false") !== "false";

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("revenuecat-webhook is missing Supabase configuration");
    return json({ error: "Service is not configured" }, 500);
  }

  // Refuse everything unless a verification method is configured, so a
  // misconfigured deployment cannot become an open entitlement endpoint.
  if (!signingSecret && !authSecret) {
    console.error("No webhook verification secret configured");
    return json({ error: "Service is not configured" }, 500);
  }

  // The raw bytes are what was signed. Parsing and re-serialising changes them
  // and breaks verification, so the body is read as text and parsed after.
  const rawBody = await req.text();

  if (signingSecret) {
    const header = req.headers.get("X-RevenueCat-Webhook-Signature");
    if (!header) {
      console.warn("Rejected delivery with no signature header");
      return json({ error: "Missing webhook signature" }, 401);
    }
    const result = await verifySignature(
      header,
      rawBody,
      signingSecret,
      SIGNATURE_TOLERANCE_SECONDS,
    );
    if (!result.ok) {
      console.warn("Rejected delivery:", result.reason);
      return json({ error: "Invalid webhook signature" }, 401);
    }
  } else {
    const provided = req.headers.get("Authorization") ?? "";
    if (!timingSafeEqual(provided, `Bearer ${authSecret}`)) {
      console.warn("Rejected delivery with bad authorization header");
      return json({ error: "Unauthorized" }, 401);
    }
  }

  let event: Record<string, unknown>;
  try {
    const payload = JSON.parse(rawBody);
    if (!payload?.event || typeof payload.event !== "object") {
      return json({ error: "Malformed payload: missing event" }, 400);
    }
    event = payload.event as Record<string, unknown>;
  } catch {
    return json({ error: "Body must be valid JSON" }, 400);
  }

  const eventId = typeof event.id === "string" ? event.id : "";
  const eventType = String(event.type ?? "UNKNOWN");
  const environment = String(event.environment ?? "UNKNOWN");

  if (!eventId) {
    return json({ error: "Malformed payload: missing event id" }, 400);
  }

  if (environment === "SANDBOX" && !allowSandbox) {
    console.log(`Ignoring sandbox ${eventType}`);
    return json({ message: "Sandbox events are not accepted" }, 200);
  }

  const eventMs = event.event_timestamp_ms;
  if (typeof eventMs !== "number" || !Number.isFinite(eventMs) || eventMs <= 0) return json({error:"Missing event timestamp"},400);
  const productId = typeof event.product_id === "string" ? event.product_id : "";
  const pack = packGrant(productId);
  if (pack) {
    if (!["NON_RENEWING_PURCHASE", "CANCELLATION"].includes(eventType)) return json({ message: "No credits for this event type" }, 200);
    const transactionId = typeof event.transaction_id === "string" ? event.transaction_id : "";
    if (!transactionId) return json({ error: "Missing transaction identity" }, 400);
    const candidates = candidateUserIds(event);
    if (candidates.length === 0) {
      console.warn(`No usable app user id on pack ${eventType} ${eventId}`);
      return json({ error: "Purchase identity is not linked yet" }, 503);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await admin.rpc("apply_credit_purchase", {
      p_user_id: candidates[0],
      p_transaction: `${environment}:${event.store}:${transactionId}`,
      p_refund: eventType === "CANCELLATION",
      p_photo: pack.photo,
      p_text: pack.text,
    });
    if (error) {
      console.error("add_purchased_credits failed", error);
      return json({ error: "Failed to apply credits" }, 500);
    }
    const status = (data as Record<string, unknown> | null) ?? {};
    if (status.ok !== true) {
      if (status.reason === "no_profile") {
        return json({ error: "Profile not found yet" }, 503);
      }
      return json({ error: "Failed to apply credits" }, 500);
    }
    return json({
      message: status.duplicate === true ? "Already processed" : "Credits added",
      photo: pack.photo,
      text: pack.text,
    }, 200);
  }

  if (eventType === "TRANSFER") {
    const key = Deno.env.get("REVENUECAT_SECRET_API_KEY");
    if (!key) return json({error:"Subscription reconciliation is not configured"},503);
    const destinationIds = (Array.isArray(event.transferred_to) ? event.transferred_to : []).filter((id): id is string => typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id));
    const ids = [...new Set([...(Array.isArray(event.transferred_from) ? event.transferred_from : []), ...destinationIds])].filter((id): id is string => typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id));
    const admin = createClient(supabaseUrl,serviceRoleKey);
    for (const id of ids) {
      try {
        const observedAt = Date.now();
        const result = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(id)}`, {headers:{Authorization:`Bearer ${key}`},signal:AbortSignal.timeout(6000)});
        if (!result.ok) return json({error:"Subscription reconciliation failed"},503);
        const info = await result.json();
        const entitlement = info.subscriber?.entitlements?.[entitlementId];
        const expiry = entitlement?.expires_date ?? null;
        const pro = !!entitlement && (expiry === null || Date.parse(expiry)>Date.now());
        const {data,error} = await admin.rpc("apply_revenuecat_event", {p_event_id:`${eventId}:${id}`,p_event_type:eventType,p_environment:entitlement?(info.subscriber?.subscriptions?.[entitlement.product_identifier]?.is_sandbox===true?"SANDBOX":"PRODUCTION"):"UNKNOWN",p_candidate_ids:[id],p_is_pro:pro,p_expires_at:expiry,p_event_ms:observedAt});
        if (error || (data?.status === "no_profile" && destinationIds.includes(id))) return json({error:"Subscription reconciliation pending"},503);
      } catch { return json({error:"Subscription reconciliation failed"},503); }
    }
    return json({success:true},200);
  }
  const decision = resolveEntitlement(event, entitlementId);
  if (!decision.decided) {
    console.log(`No entitlement change for ${eventType}: ${decision.reason}`);
    return json({ message: `Acknowledged ${eventType}` }, 200);
  }

  const candidates = candidateUserIds(event);
  if (candidates.length === 0) {
    // Nothing to match on, and retrying will not change that.
    console.warn(`No usable app user id on ${eventType} ${eventId}`);
    return json({ error: "Purchase identity is not linked yet" }, 503);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await admin.rpc("apply_revenuecat_event", {
    p_event_id: eventId,
    p_event_type: eventType,
    p_environment: environment,
    p_candidate_ids: candidates,
    p_is_pro: decision.isPro,
    p_expires_at: typeof event.expiration_at_ms === "number" ? new Date(event.expiration_at_ms).toISOString() : null,
    p_event_ms: eventMs,
  });

  if (error) {
    // 500 so RevenueCat retries: a database failure here is likely transient.
    await reportAnalyzeIssue(Deno.env.get("SENTRY_DSN")??"",{feature:"billing.webhook_failed",code:"WEBHOOK_FAILED",source:"revenuecat-webhook"});
    console.error("apply_revenuecat_event failed", error);
    return json({ error: "Failed to apply entitlement" }, 500);
  }

  const status = (data as Record<string, unknown> | null)?.status;

  if (status === "stale") return json({message:"Newer state already applied"},200);
  if (status === "duplicate") {
    console.log(`Duplicate delivery ignored: ${eventId}`);
    return json({ message: "Already processed" }, 200);
  }

  if (status === "no_profile") {
    // The claim was released, so a retry can still land this entitlement once
    // the profile exists. Non-200 asks RevenueCat to retry.
    console.warn(`No profile yet for ${eventType} ${eventId}, asking for retry`);
    return json({ error: "Profile not found yet" }, 503);
  }

  console.log(`Applied ${eventType} (${environment}): is_pro=${decision.isPro}`);
  return json({ success: true, eventType, isPro: decision.isPro }, 200);
});
