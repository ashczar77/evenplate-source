// Seeds assets/pantry/gemini_chip_scores.json from live Gemini.
// One chip name per call so each hour is a single-food score.
// Do not run in CI. Resume-safe: already-scored names are skipped.
//
//   make seed-chips
//
// After a few live calls, read usageMetadata and replace the planning
// prices in lib/core/billing/scan_allowance.dart.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const OUT = "assets/pantry/gemini_chip_scores.json";
const ENV_FILE = "supabase/.env.functions";
const MODEL = process.env.GEMINI_MODEL || "gemini-3.6-flash";
const TIMEOUT_MS = 8_000;
const GAP_MS = 400;

const CHIP_NAMES = [
  "Eggs",
  "Greek yogurt",
  "Chicken",
  "Salmon",
  "Tofu",
  "Beans",
  "Side salad",
  "Broccoli",
  "Oats",
  "Lentils",
  "Berries",
  "Avocado",
  "Olive oil",
  "Walnuts",
  "Almonds",
  "Tahini",
  "Cucumber",
  "Cherry tomatoes",
  "Greens",
  "Apple",
  "Slaw",
  "Orange juice",
  "Sloppy joes",
  "Strawberries",
  "Banana",
  "Orange",
  "Rice",
  "Pasta",
  "Bread",
  "Milk",
];

function loadGeminiKey(): string {
  const fromEnv = (process.env.GEMINI_API_KEY ?? "").trim();
  if (fromEnv.length > 0) return fromEnv;
  if (!existsSync(ENV_FILE)) return "";
  const text = readFileSync(ENV_FILE, "utf8");
  for (const line of text.split("\n")) {
    if (!line.startsWith("GEMINI_API_KEY=")) continue;
    return line.slice("GEMINI_API_KEY=".length).trim();
  }
  return "";
}

function promptFor(food: string): string {
  return `
You are EvenPlate's Satiety Matrix analyst. Score a typed food list, not a photo.

Meal name: Plate
Typed foods: ${JSON.stringify([food])}

STEP 1. Classify each name.
- Food: an ingredient, drink, or dish a person would eat.
- Not food: furniture, people, software, random keyboard noise.
Put not-food names in rejected. Put edible names in components.

If every name is not food:
- captureIssue must be not_food
- durationHours 0.5
Do not invent a dish to replace junk input.

STEP 2. Only if captureIssue is none, score the edible foods.
durationHours is how long a typical adult is likely to stay comfortably full after a usual serving of exactly these foods.
- Assume a normal single serving, not a feast and not a bite.
- Watery foods add bulk and little staying power.
- A light plate is a short meal.

Return ONLY JSON:
{
  "mealName": "Plate",
  "components": ["${food}"],
  "rejected": [],
  "pillars": {
    "anchor": { "detected": false, "items": [], "quality": "low" },
    "net": { "detected": false, "items": [], "quality": "low" },
    "buffer": { "detected": false, "items": [], "quality": "low" },
    "spark": { "detected": false, "items": [], "quality": "low" }
  },
  "satietyScore": 40,
  "durationHours": 2.0,
  "crashRisk": "moderate",
  "captureIssue": "none"
}
`.trim();
}

function readExisting(): Record<string, number> {
  if (!existsSync(OUT)) return {};
  try {
    const parsed = JSON.parse(readFileSync(OUT, "utf8")) as {
      hours?: Record<string, unknown>;
    };
    const hours: Record<string, number> = {};
    for (const [key, value] of Object.entries(parsed.hours ?? {})) {
      if (typeof value === "number" && value > 0) hours[key] = value;
    }
    return hours;
  } catch {
    return {};
  }
}

function writeScores(hours: Record<string, number>) {
  mkdirSync(dirname(OUT), { recursive: true });
  const payload = {
    source: "gemini",
    generatedAt: new Date().toISOString(),
    hours,
  };
  writeFileSync(OUT, `${JSON.stringify(payload, null, 2)}\n`);
}

function textFromGemini(data: unknown): string | null {
  const root = data && typeof data === "object" ? data as Record<string, unknown> : {};
  const candidates = Array.isArray(root.candidates) ? root.candidates : [];
  const first = candidates[0] && typeof candidates[0] === "object"
    ? candidates[0] as Record<string, unknown>
    : {};
  const content = first.content && typeof first.content === "object"
    ? first.content as Record<string, unknown>
    : {};
  const parts = Array.isArray(content.parts) ? content.parts : [];
  let text = "";
  for (const part of parts) {
    if (!part || typeof part !== "object") continue;
    const rec = part as Record<string, unknown>;
    if (rec.thought === true) continue;
    if (typeof rec.text === "string") text += rec.text;
  }
  text = text.trim();
  return text.length > 0 ? text : null;
}

function hoursFromText(text: string): number | null {
  try {
    const parsed = JSON.parse(text) as { durationHours?: unknown };
    const hours = parsed.durationHours;
    if (typeof hours !== "number" || !Number.isFinite(hours) || hours <= 0) {
      return null;
    }
    return Math.round(Math.min(8, Math.max(0.5, hours)) * 10) / 10;
  } catch {
    return null;
  }
}

function classifyFailure(status: number, body: string): string {
  const lower = body.toLowerCase();
  if (
    status === 402 ||
    lower.includes("payment required") ||
    lower.includes("prepaid") ||
    lower.includes("credit balance")
  ) {
    return "unpaid";
  }
  if (
    status === 429 ||
    lower.includes("resource exhausted") ||
    lower.includes("rate limit")
  ) {
    return "exhausted";
  }
  return "other";
}

async function scoreOne(apiKey: string, food: string): Promise<number> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;
  const body = JSON.stringify({
    contents: [{ parts: [{ text: promptFor(food) }] }],
    generationConfig: {
      response_mime_type: "application/json",
      maxOutputTokens: 2048,
      thinkingConfig: {
        thinkingLevel: "MINIMAL",
        includeThoughts: false,
      },
    },
  });

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    signal: AbortSignal.timeout(TIMEOUT_MS),
    body,
  });
  const raw = await response.text();
  if (!response.ok) {
    const kind = classifyFailure(response.status, raw);
    throw new Error(`${kind}:${response.status}`);
  }
  const extracted = textFromGemini(JSON.parse(raw));
  if (!extracted) throw new Error("empty");
  const hours = hoursFromText(extracted);
  if (hours == null) throw new Error("malformed");
  return hours;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  const apiKey = loadGeminiKey();
  if (!apiKey) {
    console.error("GEMINI_API_KEY is missing in the environment or supabase/.env.functions");
    process.exit(1);
  }

  const hours = readExisting();
  const pending = CHIP_NAMES.filter((name) => hours[name.toLowerCase()] == null);
  console.log(`Chip seed: ${CHIP_NAMES.length - pending.length} saved, ${pending.length} to score.`);

  for (const name of pending) {
    try {
      const scored = await scoreOne(apiKey, name);
      hours[name.toLowerCase()] = scored;
      writeScores(hours);
      console.log(`${name}: ${scored}h`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown";
      if (message.startsWith("unpaid:") || message.startsWith("exhausted:")) {
        writeScores(hours);
        console.error(`Stopped at ${name}: ${message.split(":")[0]}`);
        process.exit(1);
      }
      console.error(`${name} failed (${message}). Leaving it for a later run.`);
    }
    await sleep(GAP_MS);
  }

  writeScores(hours);
  const saved = Object.keys(hours).length;
  console.log(`Wrote ${saved} Gemini chip hours to ${OUT}.`);
  if (saved < CHIP_NAMES.length) {
    process.exit(1);
  }
}

main();
