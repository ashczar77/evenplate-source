// Optional, unvalidated model range. Never derived from the relative score.
export interface FullnessEstimate {
  minHours: number;
  maxHours: number;
  portion: "regular";
  basis: "model_regular_portion_v1";
}

export function regularPortionEstimate(raw: unknown): FullnessEstimate | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const value = raw as Record<string, unknown>;
  const min = value.minHours;
  const max = value.maxHours;
  if (value.portion !== "regular" || value.basis !== "model_regular_portion_v1" ||
      typeof min !== "number" || typeof max !== "number" ||
      !Number.isInteger(min) || !Number.isInteger(max) ||
      min < 1 || max > 12 || max - min < 1) return null;
  return {minHours: min, maxHours: max, portion: "regular", basis: "model_regular_portion_v1"};
}

export const fullnessEstimateInstruction = `
In the SAME assessment, optionally provide fullnessEstimate: a broad model-estimated range of hours until hunger may return after ONE regular-sized meal, not a range converted from satietyScore. Assume the entire selected composition makes one regular meal, not a full meal for every component. Honor explicit amounts and preparation. Added sides are ordinary side portions, not extra full meals. Never add or subtract per-food hours. The estimate is unvalidated and does not predict an individual's hunger, focus, energy, or blood sugar. Use whole-hour endpoints at least one hour apart. Return null when the meal or portion context is insufficient, implausible, or only a drink/condiment. Do not fabricate a research formula or a validated confidence interval. Do not modify the relative score to fit a duration. The regular-portion assumption must be described in assessmentNote.
fullnessEstimate is null or {"minHours": integer, "maxHours": integer, "portion": "regular", "basis": "model_regular_portion_v1"}.
`;

export const fullnessEstimateSchema = {
  anyOf: [
    {type: "null"},
    {type: "object", properties: {
      minHours: {type: "integer", minimum: 1, maximum: 11},
      maxHours: {type: "integer", minimum: 2, maximum: 12},
      portion: {type: "string", enum: ["regular"]},
      basis: {type: "string", enum: ["model_regular_portion_v1"]},
    }, required: ["minHours", "maxHours", "portion", "basis"]},
  ],
};
