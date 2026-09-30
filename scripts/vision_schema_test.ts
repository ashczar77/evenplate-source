// Tests the vision response normalizer.
//
// Run with: make test-vision

import {
  Analysis,
  completeAnalysis,
  MAX_ADVICE_LENGTH,
  MAX_COMPONENTS,
  MAX_DURATION_HOURS,
  MAX_ITEM_LENGTH,
  MAX_MEAL_NAME_LENGTH,
  MAX_PILLAR_ITEMS,
  MIN_DURATION_HOURS,
  normalizeAnalysis,
  notFoodAnalysis,
} from "../supabase/functions/analyze-plate/schema.ts";

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

function pillar(overrides: Record<string, unknown> = {}) {
  return { detected: true, items: ["thing"], quality: "high", ...overrides };
}

function response(overrides: Record<string, unknown> = {}) {
  return {
    mealName: "Grilled Salmon Bowl",
    components: ["Salmon", "Rice"],
    pillars: {
      anchor: pillar(),
      net: pillar(),
      buffer: pillar(),
      spark: pillar(),
    },
    satietyScore: 85,
    durationHours: 4.5,
    crashRisk: "low",
    hybridUpgrade: {
      instantAdd: "Add seeds.",
      smartSwap: "Swap the rice.",
      digestiveCatalyst: "Chew slowly.",
    },
    ...overrides,
  };
}

// Rejection: nothing usable came back
console.log("\nRejecting non analyses");
check("null is rejected", normalizeAnalysis(null), null);
check("a string is rejected", normalizeAnalysis("no"), null);
check("a number is rejected", normalizeAnalysis(7), null);
check("an array is rejected", normalizeAnalysis([{ mealName: "x" }]), null);
check("an empty object is rejected", normalizeAnalysis({}), null);
check(
  "an object with neither name nor pillars is rejected",
  normalizeAnalysis({ satietyScore: 90, crashRisk: "low" }),
  null,
);
check(
  "a name alone is enough to accept",
  (normalizeAnalysis({ mealName: "Toast" }) as Analysis).mealName,
  "Toast",
);
check(
  "pillars alone are enough to accept",
  (normalizeAnalysis({ pillars: {} }) as Analysis).mealName,
  "Mindful Plate",
);

// Score clamping
console.log("\nClamping satietyScore");
const scoreOf = (v: unknown) =>
  (normalizeAnalysis(response({ satietyScore: v })) as Analysis).satietyScore;
check("in range is kept", scoreOf(85), 85);
check("above 100 is clamped", scoreOf(9001), 100);
check("below 0 is clamped", scoreOf(-40), 0);
check("a numeric string is parsed", scoreOf("72"), 72);
check("a fraction is rounded", scoreOf(72.6), 73);
check("a non numeric string falls back", scoreOf("very filling"), 75);
check("null falls back rather than clamping to 0", scoreOf(null), 75);
check("undefined falls back", scoreOf(undefined), 75);
check("an empty string falls back", scoreOf(""), 75);
check("false falls back rather than clamping to 0", scoreOf(false), 75);
check("true falls back rather than becoming 1", scoreOf(true), 75);
check("an empty array falls back", scoreOf([]), 75);
check("an object falls back", scoreOf({}), 75);
check("NaN falls back", scoreOf(Number.NaN), 75);
check("Infinity falls back", scoreOf(Number.POSITIVE_INFINITY), 75);
check("negative Infinity falls back", scoreOf(Number.NEGATIVE_INFINITY), 75);

// Duration clamping
console.log("\nClamping durationHours");
const durationOf = (v: unknown) =>
  (normalizeAnalysis(response({ durationHours: v })) as Analysis).durationHours;
check("in range is kept", durationOf(4.5), 4.5);
check("above the max is clamped", durationOf(500), MAX_DURATION_HOURS);
check("negative is clamped to the min", durationOf(-3), MIN_DURATION_HOURS);
check("rounded to one decimal", durationOf(4.5678), 4.6);
check("a non numeric string falls back", durationOf("a while"), 3.5);
check("null falls back rather than clamping to the min", durationOf(null), 3.5);
check("zero clamps to the min", durationOf(0), MIN_DURATION_HOURS);

// Crash risk
console.log("\nConstraining crashRisk");
const riskOf = (v: unknown) =>
  (normalizeAnalysis(response({ crashRisk: v })) as Analysis).crashRisk;
check("low is kept", riskOf("low"), "low");
check("high is kept", riskOf("high"), "high");
check("moderate is kept", riskOf("moderate"), "moderate");
check("medium becomes moderate", riskOf("medium"), "moderate");
check("case is normalized", riskOf("HIGH"), "high");
check("surrounding space is trimmed", riskOf("  low  "), "low");
check("an unknown value falls back", riskOf("catastrophic"), "moderate");
check("a long sentence cannot reach the badge", riskOf("x".repeat(500)), "moderate");
check("a non string falls back", riskOf(3), "moderate");

// Text bounds
console.log("\nBounding text");
const longName = "Sourdough ".repeat(40);
const named = normalizeAnalysis(response({ mealName: longName })) as Analysis;
check("mealName is truncated", named.mealName.length <= MAX_MEAL_NAME_LENGTH, true);
check(
  "newlines are collapsed",
  (normalizeAnalysis(response({ mealName: "Salmon\n\n  Bowl" })) as Analysis)
    .mealName,
  "Salmon Bowl",
);
check(
  "an empty name falls back",
  (normalizeAnalysis(response({ mealName: "   " })) as Analysis).mealName,
  "Mindful Plate",
);
check(
  "a non string name falls back",
  (normalizeAnalysis(response({ mealName: 42, pillars: {} })) as Analysis)
    .mealName,
  "Mindful Plate",
);

const advised = normalizeAnalysis(
  response({
    hybridUpgrade: {
      instantAdd: "y".repeat(2000),
      smartSwap: 12,
      digestiveCatalyst: null,
    },
  }),
) as Analysis;
check(
  "advice is truncated",
  advised.hybridUpgrade.instantAdd.length <= MAX_ADVICE_LENGTH,
  true,
);
check(
  "non string advice falls back",
  advised.hybridUpgrade.smartSwap.startsWith("Next time"),
  true,
);
check(
  "null advice falls back",
  advised.hybridUpgrade.digestiveCatalyst.startsWith("Sip a glass"),
  true,
);
check(
  "missing hybridUpgrade falls back",
  (normalizeAnalysis(response({ hybridUpgrade: "nope" })) as Analysis)
    .hybridUpgrade.instantAdd.startsWith("Add a handful"),
  true,
);

// Lists
console.log("\nBounding lists");
const many = normalizeAnalysis(
  response({ components: Array.from({ length: 200 }, (_, i) => `item ${i}`) }),
) as Analysis;
check("components are capped", many.components.length, MAX_COMPONENTS);

const mixed = normalizeAnalysis(
  response({ components: ["Salmon", 5, null, "", "  ", "Rice", { a: 1 }] }),
) as Analysis;
check("non string entries are dropped", mixed.components, ["Salmon", "Rice"]);

check(
  "a non array components field becomes empty",
  (normalizeAnalysis(response({ components: "Salmon, Rice" })) as Analysis)
    .components,
  [],
);
check(
  "long component names are truncated",
  (normalizeAnalysis(response({ components: ["z".repeat(500)] })) as Analysis)
    .components[0].length <= MAX_ITEM_LENGTH,
  true,
);

// Pillars
console.log("\nNormalizing pillars");
const partial = normalizeAnalysis(
  response({ pillars: { anchor: pillar({ detected: true }) } }),
) as Analysis;
check("all four pillars are always present", Object.keys(partial.pillars), [
  "anchor",
  "net",
  "buffer",
  "spark",
]);
check("a missing pillar is not detected", partial.pillars.net.detected, false);
check("a missing pillar has no items", partial.pillars.net.items, []);
check("a missing pillar gets a default quality", partial.pillars.net.quality, "medium");

const stringy = normalizeAnalysis(
  response({
    pillars: {
      anchor: pillar({ detected: "true" }),
      net: pillar({ detected: "false" }),
      buffer: pillar({ detected: 1 }),
      spark: pillar({ quality: "amazing" }),
    },
  }),
) as Analysis;
check('detected "true" is honoured', stringy.pillars.anchor.detected, true);
check('detected "false" is honoured', stringy.pillars.net.detected, false);
check("a numeric detected is not truthy", stringy.pillars.buffer.detected, false);
check("an unknown quality falls back", stringy.pillars.spark.quality, "medium");

const overflowing = normalizeAnalysis(
  response({
    pillars: {
      anchor: pillar({
        items: Array.from({ length: 50 }, (_, i) => `item ${i}`),
      }),
    },
  }),
) as Analysis;
check(
  "pillar items are capped",
  overflowing.pillars.anchor.items.length,
  MAX_PILLAR_ITEMS,
);
check(
  "a non object pillar is tolerated",
  (normalizeAnalysis(response({ pillars: { anchor: "yes" } })) as Analysis)
    .pillars.anchor.detected,
  false,
);

// Nothing unexpected survives
console.log("\nDropping unknown fields");
const extra = normalizeAnalysis(
  response({ evilField: "<script>alert(1)</script>", __proto__: { x: 1 } }),
) as Analysis;
check("unknown keys are not carried through", Object.keys(extra).sort(), [
  "assessmentNote",
  "captureIssue",
  "components",
  "crashRisk",
  "durationHours",
  "hybridUpgrade",
  "mealName",
  "pillars",
  "satietyScore",
]);

check("missing captureIssue is none", extra.captureIssue, "none");
check(
  "not_food is kept",
  (normalizeAnalysis(response({ captureIssue: "not_food" })) as Analysis)
    .captureIssue,
  "not_food",
);
const fakeMeal = normalizeAnalysis(
  response({
    captureIssue: "not_food",
    mealName: "Forest salad",
    components: ["Trees", "Dirt"],
    satietyScore: 84,
    durationHours: 5,
    crashRisk: "low",
    pillars: {
      anchor: pillar({ items: ["Protein"], quality: "high" }),
    },
  }),
) as Analysis;
check("not_food zeros the score", fakeMeal.satietyScore, 0);
check("not_food drops invented foods", fakeMeal.components.length, 0);
check("not_food names the miss", fakeMeal.mealName, "Not a plate");
check("not_food clears pillars", fakeMeal.pillars.anchor.detected, false);
check(
  "too_dark is kept",
  (normalizeAnalysis(response({ captureIssue: "TOO_DARK" })) as Analysis)
    .captureIssue,
  "too_dark",
);
check(
  "junk captureIssue falls back to none",
  (normalizeAnalysis(response({ captureIssue: "explode" })) as Analysis)
    .captureIssue,
  "none",
);

console.log("\nSatiety honesty");
const feast = normalizeAnalysis(
  response({
    mealName: "Gourmet Beef Burger & BBQ Meat Spread",
    components: ["Beef burger", "BBQ meat", "Potato chips", "Fries"],
    pillars: {
      anchor: pillar({ items: ["Beef burger patties"], quality: "high" }),
      net: pillar({ items: ["Fiber"], quality: "high" }),
      buffer: pillar({ items: ["Melted cheese sauce"], quality: "high" }),
      spark: pillar({ items: ["Crispy potato chips"], quality: "high" }),
    },
    satietyScore: 84,
    durationHours: 5.0,
    crashRisk: "moderate",
  }),
) as Analysis;
check("chips are not a high Spark", feast.pillars.spark.quality, "low");
check("cheese sauce is not a high Buffer", feast.pillars.buffer.quality, "low");
check("a Fiber label is not a high Net", feast.pillars.net.quality === "high", false);
check("fried refined plates are high crash", feast.crashRisk, "high");
check("duration is capped for high crash", feast.durationHours <= 2.5, true);
check("score cannot stay in the 80s", feast.satietyScore <= 50, true);

const donut = normalizeAnalysis(
  response({
    mealName: "Glazed Cinnamon Donut",
    components: ["Enriched Flour", "Sugar Glaze", "Palm Oil"],
    pillars: {
      anchor: pillar({ detected: false, items: [], quality: "low" }),
      net: pillar({ detected: false, items: [], quality: "low" }),
      buffer: pillar({ items: ["Frying Fat"], quality: "low" }),
      spark: pillar({ detected: false, items: [], quality: "low" }),
    },
    satietyScore: 32,
    durationHours: 1.2,
    crashRisk: "high",
  }),
) as Analysis;
check("an honest donut score is kept", donut.satietyScore, 32);
check("an honest donut stays high crash", donut.crashRisk, "high");
check("an honest donut duration is kept", donut.durationHours, 1.2);

const salmon = normalizeAnalysis(response()) as Analysis;
check("a balanced salmon bowl keeps its score", salmon.satietyScore, 85);
check("a balanced salmon bowl keeps low crash", salmon.crashRisk, "low");

const blocked = notFoodAnalysis();
check("a safety block is not_food", blocked.captureIssue, "not_food");
check("a safety block does not invent a dish", blocked.mealName, "Not a plate");
check("a safety block score is zero", blocked.satietyScore, 0);

check("strict rejects empty successful model response", completeAnalysis({}), null);
check("strict rejects a fabricated numeric default", completeAnalysis({mealName:"Plate",components:["Beans"],pillars:{},satietyScore:"80",durationHours:3,captureIssue:"none",crashRisk:"low"}), null);
check("strict accepts complete not-food envelope", completeAnalysis(notFoodAnalysis())?.captureIssue, "not_food");
console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) {
  throw new Error(`${failed} vision schema test(s) failed`);
}
