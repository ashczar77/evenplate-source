// Normalizes the vision model response.
//
// The model output is untrusted input. It is rendered into fixed size UI,
// written to typed columns, and partly derived from whatever text happens to be
// visible in a photograph, so every field is coerced into a known shape and
// range before it leaves the function.

import { FullnessEstimate, fullnessEstimateSchema, regularPortionEstimate } from "../_shared/fullness_estimate.ts";

export const MAX_MEAL_NAME_LENGTH = 80;
export const MAX_COMPONENTS = 40;
export const MAX_ITEM_LENGTH = 60;
export const MAX_PILLAR_ITEMS = 8;
export const MAX_ADVICE_LENGTH = 240;
export const MIN_DURATION_HOURS = 0.5;
export const MAX_DURATION_HOURS = 12;

// The UI switches on these exact lowercase values and renders crashRisk
// directly as a badge, so an unbounded string would break the layout.
const QUALITIES = ["high", "medium", "low"];
const CRASH_RISKS = ["low", "moderate", "high"];
const CAPTURE_ISSUES = ["none", "not_food", "too_dark", "blurry"];
const PILLAR_NAMES = ["anchor", "net", "buffer", "spark"] as const;

const DEFAULT_INSTANT_ADD =
  "Add a handful of seeds or nuts to bolster your lipid buffer.";
const DEFAULT_SMART_SWAP =
  "Next time, consider whole-grain or sprouted options for sustained fiber release.";
const DEFAULT_DIGESTIVE_CATALYST =
  "Sip a glass of room-temperature water or herbal tea before eating.";

export interface PillarDetail {
  detected: boolean;
  items: string[];
  quality: string;
}

export interface Analysis {
  mealName: string;
  components: string[];
  pillars: Record<string, PillarDetail>;
  satietyScore: number;
  assessmentNote?: string;
  fullnessEstimate?: FullnessEstimate | null;
  durationHours: number;
  crashRisk: string;
  captureIssue: string;
  hybridUpgrade: {
    instantAdd: string;
    instantAddFood?: string;
    smartSwap: string;
    digestiveCatalyst: string;
  };
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function asText(value: unknown, maxLength: number, fallback: string): string {
  if (typeof value !== "string") return fallback;
  // Collapse whitespace so a multi line answer cannot break single line UI.
  const collapsed = value.replace(/\s+/g, " ").trim();
  if (collapsed.length === 0) return fallback;
  return collapsed.length > maxLength
    ? collapsed.slice(0, maxLength).trimEnd()
    : collapsed;
}

function asNumber(
  value: unknown,
  min: number,
  max: number,
  fallback: number,
): number {
  // Number() coerces null, "", false and [] to 0, which would silently clamp a
  // missing score to the bottom of the range instead of using the fallback.
  let parsed: number;
  if (typeof value === "number") {
    parsed = value;
  } else if (typeof value === "string" && value.trim().length > 0) {
    parsed = Number(value);
  } else {
    return fallback;
  }
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function asStringList(
  value: unknown,
  maxItems: number,
  maxLength: number,
): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const entry of value) {
    if (out.length >= maxItems) break;
    const cleaned = asText(entry, maxLength, "");
    if (cleaned.length > 0) out.push(cleaned);
  }
  return out;
}

function asBoolean(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value.trim().toLowerCase() === "true";
  return false;
}

function asOneOf(value: unknown, allowed: string[], fallback: string): string {
  if (typeof value !== "string") return fallback;
  const lower = value.trim().toLowerCase();
  return allowed.includes(lower) ? lower : fallback;
}

function blobOf(analysis: {
  mealName: string;
  components: string[];
  pillars: Record<string, PillarDetail>;
}): string {
  const parts = [analysis.mealName, ...analysis.components];
  for (const name of PILLAR_NAMES) {
    parts.push(...(analysis.pillars[name]?.items ?? []));
  }
  return parts.join(" ").toLowerCase();
}

function hits(blob: string, needles: string[]): boolean {
  return needles.some((n) => blob.includes(n));
}

function worseQuality(current: string, cap: string): string {
  const order = ["low", "medium", "high"];
  const a = order.indexOf(current);
  const b = order.indexOf(cap);
  const idx = Math.min(a < 0 ? 1 : a, b < 0 ? 1 : b);
  return order[idx];
}

function pillarPoints(detail: PillarDetail): number {
  if (!detail.detected) return 0;
  if (detail.quality === "high") return 25;
  if (detail.quality === "medium") return 14;
  return 8;
}

function itemsAreGeneric(items: string[], labels: string[]): boolean {
  if (items.length === 0) return false;
  return items.every((item) => labels.includes(item.trim().toLowerCase()));
}

// Presence is not quality. Cheese sauce is not a Buffer. Chips are not Spark.
// The model copies high example scores; this keeps a feast from reading as 84.
export function applySatietyHonesty(analysis: Analysis): Analysis {
  const blob = blobOf(analysis);
  const pillars = { ...analysis.pillars };

  const strongBuffer = hits(blob, [
    "avocado",
    "olive oil",
    "olives",
    "walnut",
    "almond",
    "chia",
    "flax",
    "tahini",
    "pistachio",
    "salmon",
    "mackerel",
    "sardine",
    "seeds",
  ]);
  const weakBuffer = hits(blob, [
    "cheese sauce",
    "melted cheese",
    "cream sauce",
    "gravy",
    "mayo",
    "mayonnaise",
    "ranch",
    "margarine",
    "aioli",
  ]);
  const strongNet = hits(blob, [
    "salad",
    "lettuce",
    "broccoli",
    "lentil",
    "chickpea",
    "kale",
    "spinach",
    "slaw",
    "beans",
    "quinoa",
    "oat",
    "vegetable",
  ]);
  const weakNet = hits(blob, [
    "bun",
    "wrap",
    "tortilla",
    "white rice",
    "pasta",
    "bagel",
    "white bread",
  ]);
  const strongSpark = hits(blob, [
    "salad",
    "cucumber",
    "tomato",
    "celery",
    "greens",
    "lettuce",
    "slaw",
    "pickle",
    "berries",
    "apple",
    "watermelon",
    "radish",
  ]);
  const weakSpark = hits(blob, [
    "chips",
    "fries",
    "crisps",
    "french fry",
    "tater tots",
  ]);
  const friedOrRefined = hits(blob, [
    "chips",
    "fries",
    "fried",
    "crisps",
    "french fry",
    "donut",
    "doughnut",
    "pastry",
    "soda",
    "milkshake",
    "beer",
    "wine",
    "cocktail",
    "candy",
  ]);

  const buffer = { ...pillars.buffer };
  const weakBufferHit = Boolean(
    buffer.detected && weakBuffer && !strongBuffer,
  );
  if (weakBufferHit) {
    buffer.quality = worseQuality(buffer.quality, "low");
  }

  const net = { ...pillars.net };
  const genericNet = itemsAreGeneric(net.items, [
    "fiber",
    "fibre",
    "plants",
    "plant",
  ]);
  if (net.detected && genericNet && !strongNet) {
    net.quality = worseQuality(net.quality, "low");
  }
  if (net.detected && weakNet && !strongNet) {
    net.quality = worseQuality(net.quality, "medium");
  }
  if (friedOrRefined && net.detected) {
    net.quality = worseQuality(net.quality, "medium");
  }

  const spark = { ...pillars.spark };
  const weakSparkHit = Boolean(
    spark.detected && weakSpark && !strongSpark,
  );
  if (weakSparkHit) {
    spark.quality = worseQuality(spark.quality, "low");
  }

  pillars.buffer = buffer;
  pillars.net = net;
  pillars.spark = spark;

  const tainted = friedOrRefined || weakBufferHit || weakSparkHit;
  let crashRisk = analysis.crashRisk;
  if (friedOrRefined) {
    crashRisk = "high";
  } else if (tainted && crashRisk === "low") {
    crashRisk = "moderate";
  }

  let satietyScore = analysis.satietyScore;
  let durationHours = analysis.durationHours;
  if (tainted) {
    // Cap generous scores. Leave an already-honest 32 donut alone.
    let derived =
      pillarPoints(pillars.anchor) +
      pillarPoints(net) +
      pillarPoints(buffer) +
      pillarPoints(spark);
    if (crashRisk === "high") derived -= 20;
    if (crashRisk === "moderate") derived -= 12;
    derived = Math.min(100, Math.max(15, derived));
    if (satietyScore > 50 && satietyScore > derived) satietyScore = derived;
    if (crashRisk === "high") durationHours = Math.min(durationHours, 2.5);
    else if (crashRisk === "moderate") durationHours = Math.min(durationHours, 3.5);
  }

  return {
    ...analysis,
    pillars,
    satietyScore,
    durationHours,
    crashRisk,
  };
}

/// Returns null when the payload is not an analysis at all, so the caller can
/// refund the credit rather than store a fabricated result.
export function normalizeAnalysis(raw: unknown): Analysis | null {
  const root = asRecord(raw);
  if (!root) return null;

  const rawPillars = asRecord(root.pillars);
  if (typeof root.mealName !== "string" && !rawPillars) return null;

  const pillars: Record<string, PillarDetail> = {};
  for (const name of PILLAR_NAMES) {
    const detail = asRecord(rawPillars?.[name]) ?? {};
    pillars[name] = {
      detected: asBoolean(detail.detected),
      items: asStringList(detail.items, MAX_PILLAR_ITEMS, MAX_ITEM_LENGTH),
      quality: asOneOf(detail.quality, QUALITIES, "medium"),
    };
  }

  // The model is prompted for "low" but sometimes answers "medium", which the
  // client would otherwise render as an unrecognised badge.
  let crashRisk = asOneOf(root.crashRisk, [...CRASH_RISKS, "medium"], "moderate");
  if (crashRisk === "medium") crashRisk = "moderate";

  const advice = asRecord(root.hybridUpgrade) ?? {};

  const built: Analysis = {
    mealName: asText(root.mealName, MAX_MEAL_NAME_LENGTH, "Mindful Plate"),
    components: asStringList(root.components, MAX_COMPONENTS, MAX_ITEM_LENGTH),
    assessmentNote: asText(root.assessmentNote, 600, 'Portions and recipes are estimated.'),
    pillars,
    satietyScore: Math.round(asNumber(root.satietyScore, 0, 100, 75)),
    durationHours: Math.round(
      asNumber(
        root.durationHours,
        MIN_DURATION_HOURS,
        MAX_DURATION_HOURS,
        3.5,
      ) * 10,
    ) / 10,
    crashRisk,
    captureIssue: asOneOf(root.captureIssue, CAPTURE_ISSUES, "none"),
    hybridUpgrade: {
      instantAddFood: asText(advice.instantAddFood, MAX_ITEM_LENGTH, ''),
      instantAdd: asText(
        advice.instantAdd,
        MAX_ADVICE_LENGTH,
        DEFAULT_INSTANT_ADD,
      ),
      smartSwap: asText(advice.smartSwap, MAX_ADVICE_LENGTH, DEFAULT_SMART_SWAP),
      digestiveCatalyst: asText(
        advice.digestiveCatalyst,
        MAX_ADVICE_LENGTH,
        DEFAULT_DIGESTIVE_CATALYST,
      ),
    },
  };

  return sanitizeCaptureIssue(applySatietyHonesty(built));
}

function emptyPillar(): PillarDetail {
  return { detected: false, items: [], quality: "low" };
}

// Used when Gemini refuses to score the photo (safety finish or block).
// That is the same product outcome as captureIssue not_food: no meal in frame.
export function notFoodAnalysis(): Analysis {
  return sanitizeCaptureIssue({
    mealName: "Not a plate",
    components: [],
    pillars: {
      anchor: emptyPillar(),
      net: emptyPillar(),
      buffer: emptyPillar(),
      spark: emptyPillar(),
    },
    satietyScore: 0,
    durationHours: MIN_DURATION_HOURS,
    crashRisk: "low",
    captureIssue: "not_food",
    hybridUpgrade: {
      instantAdd: "Point the camera at a meal and try again.",
      smartSwap: "Use a well lit photo of the plate.",
      digestiveCatalyst: "Hold the camera steady over the food.",
    },
  });
}

function sanitizeCaptureIssue(analysis: Analysis): Analysis {
  if (analysis.captureIssue === "none") return analysis;
  return {
    ...analysis,
    mealName: analysis.captureIssue === "not_food"
      ? "Not a plate"
      : analysis.mealName,
    components: [],
    pillars: {
      anchor: emptyPillar(),
      net: emptyPillar(),
      buffer: emptyPillar(),
      spark: emptyPillar(),
    },
    satietyScore: 0,
    durationHours: MIN_DURATION_HOURS,
    crashRisk: "low",
    hybridUpgrade: {
      instantAdd: "Point the camera at a meal and try again.",
      smartSwap: "Use a well lit photo of the plate.",
      digestiveCatalyst: "Hold the camera steady over the food.",
    },
  };
}

export function completeAnalysis(raw: unknown): Analysis | null {
  const root = asRecord(raw);
  if (!root || typeof root.mealName !== "string" || !Array.isArray(root.components) || !asRecord(root.pillars) || typeof root.satietyScore !== "number" || !Number.isFinite(root.satietyScore) || root.satietyScore < 0 || root.satietyScore > 100 || typeof root.durationHours !== "number" || !Number.isFinite(root.durationHours) || !CAPTURE_ISSUES.includes(String(root.captureIssue)) || !CRASH_RISKS.includes(String(root.crashRisk))) return null;
  if (!root.mealName.trim() || root.components.some((item:unknown) => typeof item !== "string") || (root.captureIssue === "none" && root.components.length === 0)) return null;
  const upgrade = asRecord(root.hybridUpgrade);
  if (!upgrade || ["instantAdd","smartSwap","digestiveCatalyst"].some(key => typeof upgrade[key] !== "string")) return null;
  for (const name of PILLAR_NAMES) {
    const pillar = asRecord((root.pillars as Record<string, unknown>)[name]);
    if (!pillar || typeof pillar.detected !== "boolean" || !Array.isArray(pillar.items) || !QUALITIES.includes(String(pillar.quality))) return null;
  }
  const normalized = normalizeAnalysis(raw);
  if (!normalized) return null;
  // Retain the provider rating; keyword rules must not rewrite it.
  normalized.satietyScore = Math.round(Math.max(0, Math.min(100, root.satietyScore as number)));
  normalized.fullnessEstimate = root.captureIssue === "none"
    ? regularPortionEstimate(root.fullnessEstimate) : null;
  return normalized;
}

// Constrain provider output before applying server validation.
const pillarResponseSchema = {
  type: "object",
  properties: {
    detected: { type: "boolean" },
    items: { type: "array", items: { type: "string" } },
    quality: { type: "string", enum: QUALITIES },
  },
  required: ["detected", "items", "quality"],
};
export const analysisResponseSchema = {
  type: "object",
  properties: {
    mealName: { type: "string" },
    components: { type: "array", items: { type: "string" } },
    pillars: {
      type: "object",
      properties: Object.fromEntries(PILLAR_NAMES.map(name => [name, pillarResponseSchema])),
      required: [...PILLAR_NAMES],
    },
    satietyScore: { type: "number", minimum: 0, maximum: 100 },
    assessmentNote: { type: "string" },
    fullnessEstimate: fullnessEstimateSchema,
    durationHours: { type: "number" },
    crashRisk: { type: "string", enum: CRASH_RISKS },
    captureIssue: { type: "string", enum: CAPTURE_ISSUES },
    hybridUpgrade: {
      type: "object",
      properties: {
        instantAdd: { type: "string" },
        instantAddFood: { type: "string" },
        smartSwap: { type: "string" },
        digestiveCatalyst: { type: "string" },
      },
      required: ["instantAdd", "instantAddFood", "smartSwap", "digestiveCatalyst"],
    },
  },
  required: ["mealName", "components", "pillars", "satietyScore", "durationHours", "crashRisk", "captureIssue", "hybridUpgrade", "fullnessEstimate"],
};
