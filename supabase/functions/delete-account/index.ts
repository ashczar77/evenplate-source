import { reportAnalyzeIssue } from "../analyze-plate/sentry.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

serve(async (req) => {
  const json = (body: unknown, status: number) => new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json" },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) return json({ error: "Service unavailable" }, 503);
  const token = req.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  const admin = createClient(url, key, {
    auth: { persistSession: false },
    global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) }) },
  });
  try {
    const { data, error } = await admin.auth.getUser(token);
    let owner = data.user?.id;
    let alreadyDeleted = false;
    if (!owner && (error?.code === "user_not_found" || (error?.status === 403 && error?.message === "User from sub claim in JWT does not exist"))) {
      // Auth validated the token before reporting a missing subject.
      try {
        const encoded = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
        const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")));
        if (claims.role === "authenticated" && claims.iss === `${url}/auth/v1` && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(claims.sub)) {
          owner = claims.sub;
          alreadyDeleted = true;
        }
      } catch {}
    }
    if (!owner) {
      if (error?.status >= 500 || error?.name === "AuthRetryableFetchError") throw new Error("Auth unavailable");
      return json({ error: "Sign in again to delete your account" }, 401);
    }
    const pushKey = Deno.env.get("ONESIGNAL_REST_API_KEY");
    const pushApp = Deno.env.get("ONESIGNAL_APP_ID");
    if (!pushKey || !pushApp || !Deno.env.get("REVENUECAT_SECRET_API_KEY")) return json({error:"Account deletion is temporarily unavailable. Contact evenplatesupport@gmail.com."},503);
    if (pushKey && pushApp) {
      const deleted = await fetch(`https://api.onesignal.com/apps/${pushApp}/users/by/external_id/${owner}`, {
        method: "DELETE", headers: { Authorization: `Key ${pushKey}` },
        signal: AbortSignal.timeout(8000),
      });
      if (!deleted.ok && deleted.status !== 404) throw new Error("Push deletion failed");
    }
    const revenueCatKey = Deno.env.get("REVENUECAT_SECRET_API_KEY");
    if (revenueCatKey) {
      const removedBilling = await fetch(`https://api.revenuecat.com/v1/subscribers/${owner}`, {method:"DELETE",headers:{Authorization:`Bearer ${revenueCatKey}`},signal:AbortSignal.timeout(8000)});
      if (!removedBilling.ok && removedBilling.status !== 404) throw new Error("Billing deletion failed");
    }
    if (!alreadyDeleted) {
      const removed = await admin.auth.admin.deleteUser(owner);
      if (removed.error) throw removed.error;
    }
    return json({ deleted: true }, 200);
  } catch {
    await reportAnalyzeIssue(Deno.env.get("SENTRY_DSN")??"",{feature:"account.delete_failed",code:"DELETE_FAILED",source:"delete-account"});
    console.error("account.delete_failed");
    return json({ error: "Account deletion could not finish. Please try again." }, 503);
  }
});
