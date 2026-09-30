import { fullnessEstimateInstruction } from "../_shared/fullness_estimate.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  analysisTextFromGemini,
  classifyGeminiFailure,
  GeminiFailure,
  isGeminiSafetyBlock,
  nextGeminiAction,
  usageMetadataFromGemini,
  userMessageForGeminiFailure,
} from "./gemini.ts";
import { analysisResponseSchema, completeAnalysis, notFoodAnalysis } from "./schema.ts";
import { reportAnalyzeIssue } from "./sentry.ts";

// Mobile clients send no Origin header and do not enforce CORS, so nothing is
// allowed by default. Set ALLOWED_ORIGINS to a comma separated list only if a
// browser build needs to reach this function.
const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter((origin) => origin.length > 0);

function corsHeadersFor(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-evenplate-dev-unlimited",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (origin && allowedOrigins.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function stripBase64Payload(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0) return null;
  const comma = value.indexOf(",");
  if (value.startsWith("data:") && comma !== -1) {
    return value.slice(comma + 1);
  }
  return value;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// Roughly 8 MB of base64, which is about 6 MB of image bytes. The client
// downscales the long edge well below this.
const MAX_IMAGE_BASE64_LENGTH = 8 * 1024 * 1024;
const ALLOWED_MIME_TYPES = ["image/jpeg", "image/png", "image/webp"];

// Google retires models on a rolling schedule, and a retired id makes the
// request hang rather than fail cleanly. Overridable by secret so the model can
// be moved without a redeploy.
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.6-flash";
const GEMINI_FALLBACK_MODEL = Deno.env.get("GEMINI_FALLBACK_MODEL") ??
  "gemini-3.5-flash-lite";

// Must stay comfortably under the platform wall clock limit. If the request is
// still running when the platform kills the function, no catch block runs and
// the reserved credit is never refunded.
const GEMINI_TIMEOUT_MS = 45_000;

const promptText = `
You are EvenPlate's Satiety Matrix analyst. Identify the foods in this photo. Do not predict hunger, focus, or blood sugar.

STEP 1. Classify the photo before you score anything.
- not_food: no meal, snack, drink, or plated food a person would eat. Pets, people, books, forests, rooms, screens, objects, and packaging with no edible food are not_food.
- too_dark: the frame is too dark to identify food.
- blurry: motion blur makes food unreadable.
- none: there is food or drink to score.

If captureIssue is not none:
- mealName must be "Not a plate"
- components must be []
- every pillar detected false, items [], quality low
- satietyScore 0, durationHours 0.5, crashRisk low
- hybridUpgrade can say to point the camera at a meal
Do not invent a dish. Do not score a dog, book, forest, or person as food.

STEP 2. Only if captureIssue is none, score the plate.

The 4 pillars are specific foods, not "something in that category exists":
- Anchor (protein): flesh, eggs, dairy protein, tofu, legumes. A burger patty counts. Gravy does not.
- Net (fiber): vegetables, beans, intact whole grains, fruit. A white bun or a garnish leaf is quality low. A real salad or beans is high.
- Buffer (healthy lipids): avocado, nuts, seeds, olive oil, oily fish. Melted cheese sauce, mayo, cream, and fryer oil are quality low, never high.
- Spark (volume and crunch): water-rich produce (salad, cucumber, slaw, fruit). Potato chips, fries, crisps, and crackers are quality low. They are not a completed Spark.

Estimate relative meal fullness as satietyScore from 0 to 100, considering the complete meal, protein, fiber, food form, preparation, and likely relative portions. This is a qualitative model estimate, not a measured satiety index. Never add individual food scores or award a fixed bonus for a pairing. Do not force every added food to increase the rating. Keep estimates conservative when portions or recipes are unclear. In assessmentNote retain preparation and estimated relative portion observations for each food, plus important uncertainty, within 600 characters. Never claim precision, validated personal satiety, or guaranteed effects. Legacy fields must be durationHours 0.5 and crashRisk moderate; only the separate optional fullnessEstimate field may describe a rough hunger-time range. Do not predict focus, energy, or blood sugar.
Set hybridUpgrade.instantAddFood to the one exact food and portion the suggestion selects. The instantAdd suggestion must name exactly one food with no alternatives or promised outcome. Suggestions are optional food pairings, not guaranteed rescues. Do not promise changes in hunger time, crash risk, hormones, blood sugar, or focus.
Use ordinary searchable food names and preparation methods. Name a composed dish as one food; do not also list its internal ingredients as separate foods. Do not invent nutrients or recipe details that cannot be identified.

List every distinct food and drink you can see in components, including sides, sauces, bread, and alcohol. Use real names (burger, beer, pizza, chips). Never use Protein, Fiber, Lipids, or Volume as item names.
Set captureIssue using STEP 1. Use none only when the photo is a meal.

Return ONLY JSON:
{
  "mealName": "Name of the dish",
  "components": ["name each visible food or drink"],
  "pillars": {
    "anchor": { "detected": false, "items": [], "quality": "low" },
    "net": { "detected": false, "items": [], "quality": "low" },
    "buffer": { "detected": false, "items": [], "quality": "low" },
    "spark": { "detected": false, "items": [], "quality": "low" }
  },
  "assessmentNote": "Portions and recipes are estimated.",
  "satietyScore": 50,
  "durationHours": 0.5,
  "crashRisk": "moderate",
  "captureIssue": "none",
  "hybridUpgrade": {
    "instantAddFood": "One named side food",
    "instantAdd": "One thing to eat with this plate now",
    "smartSwap": "One swap for next time",
    "digestiveCatalyst": "One pacing or pairing tip"
  }
}
`;

serve(async (req) => {
  const corsHeaders = corsHeadersFor(req.headers.get("Origin"));

  const json = (body: unknown, status: number): Response =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json", "X-Request-Id": req.headers.get("x-request-id") ?? crypto.randomUUID() },
    });

  const sentryDsn = Deno.env.get("SENTRY_DSN") ?? "";

  const reportIssue = (
    feature: string,
    code: string,
    extra: {
      model?: string;
      httpStatus?: number;
      detail?: string;
      level?: "error" | "warning" | "info";
    } = {},
  ) =>
    reportAnalyzeIssue(sentryDsn, {
      feature,
      code,
      ...extra,
    });

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed", code: "METHOD_NOT_ALLOWED" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const geminiApiKey = Deno.env.get("GEMINI_API_KEY") ?? "";

  if (!supabaseUrl || !supabaseAnonKey || !geminiApiKey) {
    console.error("analyze-plate is missing required environment variables");
    await reportIssue("analyze.unconfigured", "SERVICE_UNCONFIGURED", {
      httpStatus: 500,
    });
    return json(
      { error: "Service is not configured", code: "SERVICE_UNCONFIGURED" },
      500,
    );
  }

  // Tracks whether a credit was reserved, so it can be returned if the
  // analysis fails after the reservation.
  let reservedUserId: string | null = null;
  let requestId = "";

  const refundIfReserved = async () => {
    if (!reservedUserId || !serviceRoleKey) return;
    try {
      const admin = createClient(supabaseUrl, serviceRoleKey);
      const refundUser = reservedUserId;
      reservedUserId = null;
      const { error } = await admin.rpc("settle_analysis_request", {
        p_user_id: refundUser, p_request_id: requestId, p_success:false,
      });
      if (error) throw error;
    } catch (refundError) {
      console.error("Failed to refund scan credit", refundError);
    }
  };

  const requestDeadline = Date.now() + 48000;
  try {
    // 1. Require a bearer token up front.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return json(
        { error: "Missing or invalid Authorization header", code: "AUTH" },
        401,
      );
    }

    // The Authorization header stays on the client so later queries run as the
    // caller and RLS applies to them.
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // 2. Verify the caller. The token has to be passed explicitly: there is no
    // stored session in a function, so the argumentless getUser() has nothing
    // to validate and rejects every request.
    const accessToken = authHeader.slice("Bearer ".length).trim();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(accessToken);
    if (authError || !user) {
      console.error("Token verification failed", authError?.message);
      return json(
        { error: "Unauthorized: Invalid or expired token", code: "AUTH" },
        401,
      );
    }

    // 3. Validate the payload before spending a credit on it.
    let payload: { imageBase64?: unknown; mimeType?: unknown; requestId?: unknown; dietaryPreference?: unknown; analysisConsent?: unknown };
    try {
      payload = await req.json();
    } catch {
      return json(
        { error: "Request body must be valid JSON", code: "BAD_REQUEST" },
        400,
      );
    }

    if (payload.analysisConsent !== true) return json({error:"Allow meal analysis before uploading.",code:"CONSENT_REQUIRED"},403);
    requestId = typeof payload.requestId === "string" ? payload.requestId : crypto.randomUUID();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestId)) return json({error:"Invalid request identity",code:"BAD_REQUEST"},400);
    const imageBase64 = stripBase64Payload(payload.imageBase64);
    const mimeType =
      typeof payload.mimeType === "string" ? payload.mimeType : "image/jpeg";

    if (imageBase64 == null) {
      return json(
        { error: "Missing imageBase64 in request body", code: "BAD_REQUEST" },
        400,
      );
    }
    if (imageBase64.length > MAX_IMAGE_BASE64_LENGTH) {
      return json(
        { error: "Image is too large", code: "IMAGE_TOO_LARGE" },
        413,
      );
    }
    if (!ALLOWED_MIME_TYPES.includes(mimeType)) {
      return json(
        { error: `Unsupported mimeType: ${mimeType}`, code: "UNSUPPORTED_TYPE" },
        415,
      );
    }

    // 4. Atomically check and consume quota. Doing this before the vision call
    // means concurrent requests cannot all pass on the same stale count.
    // Dev unlimited is off unless the function secret is set, so a client
    // header alone cannot skip the meter.
    const devUnlimited =
      Deno.env.get("ALLOW_DEV_UNLIMITED_SCANS") === "true" &&
      req.headers.get("x-evenplate-dev-unlimited") === "1";

    let quota: {
      allowed?: boolean;
      is_pro?: boolean;
      remaining?: number;
      reason?: string;
      response?: unknown;
      skipped?: boolean;
      used_purchased?: boolean;
      photo_remaining?: number;
      photo_purchased?: number;
    };

    if (devUnlimited) {
      quota = { allowed: true, is_pro: true, remaining: 0, skipped: true };
    } else {
      const consumed = await supabase.rpc("reserve_analysis_request", {p_request_id: requestId, p_kind:"photo"});
      if (consumed.error || !consumed.data) {
        console.error("consume_scan_credit failed", consumed.error);
        await reportIssue("analyze.quota_check", "QUOTA_CHECK_FAILED", {
          httpStatus: 500,
          detail: consumed.error?.message,
        });
        return json(
          { error: "Failed to verify scan quota", code: "QUOTA_CHECK_FAILED" },
          500,
        );
      }
      quota = consumed.data;
    }

    if (quota.reason === "complete") return json(quota.response, 200);
    if (quota.reason === "reserved") return json({error:"Analysis is still processing. Try again shortly.",code:"REQUEST_PENDING"},409);
    if (quota.reason === "refunded") return json({error:"The previous attempt was refunded. Please retry.",code:"REQUEST_REFUNDED"},503);
    if (quota.reason === "device_required") return json({error:"Verify this iPhone for free access, or use paid credits. Please retry or contact support.",code:"DEVICE_REQUIRED"},403);
    if (!quota.allowed) {
      if (quota.reason === "quota_exceeded") {
        return json(
          {
            error: "Weekly photo scans used. Buy more or wait until Monday.",
            code: "QUOTA_EXCEEDED",
            quota: {
              isPro: quota.is_pro === true,
              freeScansRemaining: 0,
              photoPurchased: 0,
            },
          },
          403,
        );
      }
      return json(
        { error: "Unable to authorize this scan", code: "AUTH" },
        403,
      );
    }

    reservedUserId = quota.skipped === true ? null : user.id;


    const clientQuota = (
      currentQuota: typeof quota,
      refunded = false,
    ): Record<string, unknown> => {
      const included = typeof currentQuota.photo_remaining === "number"
        ? currentQuota.photo_remaining
        : 0;
      const purchased = typeof currentQuota.photo_purchased === "number"
        ? currentQuota.photo_purchased
        : 0;
      const usedPurchased = currentQuota.used_purchased === true;
      return {
        isPro: currentQuota.is_pro === true,
        freeScansRemaining: included + (refunded && !usedPurchased ? 1 : 0),
        photoPurchased: purchased + (refunded && usedPurchased ? 1 : 0),
      };
    };

    const notFoodPayload = (
      currentQuota: typeof quota,
    ): Record<string, unknown> => {
      return {
        ...notFoodAnalysis(),
        ...(currentQuota.skipped === true
          ? {}
          : { quota: clientQuota(currentQuota, true) }),
      };
    };

    // 5. Call vision. Primary first, then a quieter fallback model so a
    // busy or flaky primary does not dead-end the scan the way a single
    // vendor call would.
    const preference = typeof payload.dietaryPreference === "string" ? payload.dietaryPreference.slice(0,80) : "Omnivore / Balanced";
    const dietaryInstruction = `Recommendations must fit the dietary preference: ${JSON.stringify(preference)}. Vegan means no animal products; vegetarian means no meat or fish; low carb avoids refined starch suggestions. Do not claim that foods are allergen-safe. For sensitive preferences, recommend checking ingredients against the person's own allergy plan. Analyze the submitted meal honestly regardless of preference.`;
    const geminiEndpoint = (model: string) =>
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`;

    const geminiBody = (useThinking: boolean, maxOutputTokens = 4096) =>
      JSON.stringify({
        contents: [
          {
            parts: [
              { text: promptText + fullnessEstimateInstruction + "\n" + dietaryInstruction },
              { inline_data: { mime_type: mimeType, data: imageBase64 } },
            ],
          },
        ],
        generationConfig: {
          response_mime_type: "application/json",
          responseJsonSchema: analysisResponseSchema,
          maxOutputTokens,
          ...(useThinking
            ? {
              thinkingConfig: {
                thinkingLevel: "MINIMAL",
                includeThoughts: false,
              },
            }
            : {}),
        },
      });

    const callGemini = (model: string, body: string) =>
      fetch(geminiEndpoint(model), {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Request-Id": req.headers.get("x-request-id") ?? crypto.randomUUID() },
        signal: AbortSignal.timeout(Math.max(1, Math.min(GEMINI_TIMEOUT_MS, requestDeadline - Date.now()))),
        body,
      });

    type GeminiAttempt = {
      model: string;
      thinking: boolean;
      maxOutputTokens: number;
      delayMs: number;
    };

    const attempts: GeminiAttempt[] = [{
      model: GEMINI_MODEL,
      thinking: true,
      maxOutputTokens: 4096,
      delayMs: 0,
    }];

    let extracted: ReturnType<typeof analysisTextFromGemini> | null = null;
    let lastFailure: GeminiFailure | null = null;
    let usedFallback = false;
    let assessedModel = GEMINI_MODEL;
    let satietyResult: ReturnType<typeof completeAnalysis> = null;
    let malformedDetail: string | null = null;

    const applyRetry = (failure: GeminiFailure, thinking: boolean) => {
      const action = nextGeminiAction(failure, {
        surface: "photo",
        thinking,
        alreadyTriedFallback: usedFallback,
      });
      if (action === "retry_without_thinking") {
        attempts.push({
          model: GEMINI_MODEL,
          thinking: false,
          maxOutputTokens: 4096,
          delayMs: 0,
        });
        return;
      }
      if (action === "fallback_once" && GEMINI_FALLBACK_MODEL !== GEMINI_MODEL) {
        usedFallback = true;
        attempts.push({
          model: GEMINI_FALLBACK_MODEL,
          thinking: false,
          maxOutputTokens: 4096,
          delayMs: 400,
        });
      }
    };

    for (const attempt of attempts) {
      if (attempt.delayMs > 0) await sleep(attempt.delayMs);

      let geminiResponse: Response;
      try {
        geminiResponse = await callGemini(
          attempt.model,
          geminiBody(attempt.thinking, attempt.maxOutputTokens),
        );
      } catch (fetchError) {
        console.error(
          "Gemini request did not complete",
          attempt.model,
          fetchError,
        );
        lastFailure = {
          kind: "transient",
          httpStatus: 504,
          message: "timeout",
        };
        break;
      }

      if (!geminiResponse.ok) {
        const errText = await geminiResponse.text();
        const failure = classifyGeminiFailure(geminiResponse.status, errText);
        lastFailure = failure;
        console.error(
          "Gemini request failed",
          attempt.model,
          geminiResponse.status,
          failure.kind,

        );

        applyRetry(failure, attempt.thinking);
        continue;
      }

      const geminiData = await geminiResponse.json();
      const usage = usageMetadataFromGemini(geminiData);
      if (usage) {
        console.log("scan.usageMetadata", JSON.stringify(usage));
      }
      extracted = analysisTextFromGemini(geminiData);
      if (extracted.text) {
        const cleanJson = extracted.text.replace(/```json/g, "").replace(/```/g, "").trim();
        try {
          satietyResult = completeAnalysis(JSON.parse(cleanJson));
          malformedDetail = satietyResult ? null : "schema";
        } catch {
          malformedDetail = "unparseable";
        }
        if (satietyResult) { assessedModel = attempt.model; break; }
        if (!usedFallback && GEMINI_FALLBACK_MODEL !== GEMINI_MODEL && requestDeadline - Date.now() > 1000) {
          usedFallback = true;
          attempts.push({model: GEMINI_FALLBACK_MODEL, thinking: false, maxOutputTokens: 4096, delayMs: 0});
          continue;
        }
        break;
      }

      console.error(
        "No analysis text from vision model",
        attempt.model,
        extracted.finishReason,
        extracted.blockReason,
      );

      if (isGeminiSafetyBlock(extracted)) {
        lastFailure = {
          kind: "blocked",
          httpStatus: 422,
          message: extracted.blockReason || extracted.finishReason,
        };
        break;
      }

      lastFailure = {
        kind: "unknown",
        httpStatus: 502,
        message: extracted.finishReason || "empty",
      };
      applyRetry(lastFailure, attempt.thinking);
    }

    if (!extracted?.text) {
      await refundIfReserved();
      if (isGeminiSafetyBlock(extracted, lastFailure)) {
        reservedUserId = null;
        return json(notFoodPayload(quota), 200);
      }
      if (lastFailure?.httpStatus === 504 && lastFailure.message === "timeout") {
        await reportIssue("analyze.timeout", "GEMINI_TIMEOUT", {
          httpStatus: 504,
          detail: lastFailure.message,
        });
        return json(
          {
            error: "Scoring is temporarily unavailable.",
            code: "GEMINI_TIMEOUT",
          },
          504,
        );
      }
      if (lastFailure) {
        const mapped = userMessageForGeminiFailure(lastFailure);
        await reportIssue(`analyze.${mapped.code.toLowerCase()}`, mapped.code, {
          httpStatus: mapped.status,
          detail: lastFailure.message,
        });
        return json(
          { error: mapped.error, code: mapped.code },
          mapped.status,
        );
      }
      await reportIssue("analyze.empty", "GEMINI_EMPTY", { httpStatus: 502 });
      return json(
        {
          error: "Scoring is temporarily unavailable.",
          code: "GEMINI_EMPTY",
        },
        502,
      );
    }

    if (!satietyResult) {
      await refundIfReserved();
      await reportIssue("analyze.malformed", "GEMINI_MALFORMED", {
        httpStatus: 502,
        detail: malformedDetail ?? "schema",
      });
      return json({error: "Analysis is temporarily unavailable. Please try again.", code: "GEMINI_MALFORMED"}, 502);
    }

    // Capture issues are not meals. Refund the credit and skip the diary.
    if (satietyResult.captureIssue !== "none") {
      await refundIfReserved();
      reservedUserId = null;
      return json(
        {
          ...satietyResult,
          ...(quota.skipped === true ? {} : {
            quota: clientQuota(quota, true),
          }),
        },
        200,
      );
    }

    Object.assign(satietyResult, {assessmentMethod:'gemini-meal-v1', assessmentId:requestId, assessmentModel:assessedModel,
      assessmentNote: satietyResult.assessmentNote || 'Photo portions and recipes are estimated.',
      durationHours:0, crashRisk:'moderate'});


    // 6. Record the meal. A failure here should not cost the user a credit.
    const diaryId = requestId;
    const satietyStore = {
      ...satietyResult,
      _evenplate: {
        id: diaryId,
        timestamp: new Date().toISOString(),
      },
    };
    const response = {...satietyResult, diaryId, ...(quota.skipped === true ? {} : {quota: clientQuota(quota)})};
    const {data: settled,error: insertError} = quota.skipped === true
      ? await supabase.from("meals").upsert({user_id:user.id, local_id:diaryId, meal_name:satietyResult.mealName, satiety_score:satietyResult.satietyScore, duration_hours:satietyResult.durationHours, satiety_result:satietyStore}, {onConflict:"user_id,local_id"})
      : await createClient(supabaseUrl,serviceRoleKey).rpc("settle_analysis_request", {p_user_id:user.id,p_request_id:requestId,p_success:true,p_response:response,p_meal:satietyStore});

    if (insertError || (quota.skipped !== true && settled?.ok !== true)) {
      console.error("Failed to insert meal", insertError);
      await refundIfReserved();
      await reportIssue("analyze.meal_insert", "MEAL_INSERT_FAILED", {
        httpStatus: 503,
        detail: insertError?.message ?? "Analysis settlement failed",
      });
      return json({ error: "Could not save the analysis. Please try again.", code: "MEAL_INSERT_FAILED" }, 503);
    }

    reservedUserId = null;
    return json(response,200);
  } catch (error) {
    console.error("analyze-plate failed", error);
    await refundIfReserved();
    await reportIssue("analyze.internal", "INTERNAL", {
      httpStatus: 500,
      detail: error instanceof Error ? error.message : "unknown",
    });
    return json({ error: "Internal Server Error", code: "INTERNAL" }, 500);
  }
});
