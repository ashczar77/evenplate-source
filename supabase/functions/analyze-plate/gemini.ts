// Gemini response helpers. Kept free of Deno.env so the same file can be
// bundled into Node tests.

export type GeminiFailureKind =
  | "thinking_unsupported"
  | "exhausted"
  | "unpaid"
  | "transient"
  | "invalid_image"
  | "blocked"
  | "unknown";

export type GeminiRetryAction =
  | "stop"
  | "retry_without_thinking"
  | "fallback_once";

export interface GeminiFailure {
  kind: GeminiFailureKind;
  httpStatus: number;
  message: string;
}

export interface GeminiText {
  text: string | null;
  finishReason: string;
  blockReason: string;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
}

function tryParseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export function usageMetadataFromGemini(geminiData: unknown): {
  promptTokenCount: number;
  candidatesTokenCount: number;
  thoughtsTokenCount: number;
  totalTokenCount: number;
} | null {
  const meta = asRecord(asRecord(geminiData).usageMetadata);
  const prompt = meta.promptTokenCount;
  const candidates = meta.candidatesTokenCount;
  const thoughts = meta.thoughtsTokenCount;
  const total = meta.totalTokenCount;
  if (
    typeof prompt !== "number" &&
    typeof candidates !== "number" &&
    typeof total !== "number"
  ) {
    return null;
  }
  return {
    promptTokenCount: typeof prompt === "number" ? prompt : 0,
    candidatesTokenCount: typeof candidates === "number" ? candidates : 0,
    thoughtsTokenCount: typeof thoughts === "number" ? thoughts : 0,
    totalTokenCount: typeof total === "number" ? total : 0,
  };
}

export function analysisTextFromGemini(geminiData: unknown): GeminiText {
  const root = asRecord(geminiData);
  const feedback = asRecord(root.promptFeedback);
  const blockReason = typeof feedback.blockReason === "string"
    ? feedback.blockReason
    : "";

  const candidates = Array.isArray(root.candidates) ? root.candidates : [];
  const first = asRecord(candidates[0]);
  const finishReason = typeof first.finishReason === "string"
    ? first.finishReason
    : "";
  const content = asRecord(first.content);
  const parts = Array.isArray(content.parts) ? content.parts : [];

  let text = "";
  for (const part of parts) {
    if (!part || typeof part !== "object") continue;
    const rec = part as Record<string, unknown>;
    if (rec.thought === true) continue;
    if (typeof rec.text === "string") text += rec.text;
  }
  text = text.trim();
  return {
    text: text.length > 0 ? text : null,
    finishReason,
    blockReason,
  };
}

export function classifyGeminiFailure(
  httpStatus: number,
  bodyText: string,
): GeminiFailure {
  const parsed = tryParseJson(bodyText);
  const err = asRecord(asRecord(parsed).error);
  const status = typeof err.status === "string" ? err.status : "";
  const apiMessage = typeof err.message === "string" ? err.message : "";
  const code = typeof err.code === "number" ? err.code : httpStatus;
  const message = apiMessage || bodyText.slice(0, 400);
  const lower = `${status} ${message}`.toLowerCase();

  if (
    httpStatus === 402 ||
    code === 402 ||
    status === "PAYMENT_REQUIRED" ||
    lower.includes("payment required") ||
    lower.includes("prepay") ||
    lower.includes("prepaid") ||
    lower.includes("credit balance")
  ) {
    return { kind: "unpaid", httpStatus, message };
  }

  if (
    httpStatus === 429 ||
    code === 429 ||
    status === "RESOURCE_EXHAUSTED" ||
    lower.includes("resource exhausted") ||
    lower.includes("rate limit") ||
    lower.includes("quota exceeded")
  ) {
    return { kind: "exhausted", httpStatus, message };
  }

  if (
    lower.includes("thinkingconfig") ||
    lower.includes("thinking_config") ||
    (lower.includes("thinking") &&
      (lower.includes("unsupported") ||
        lower.includes("unknown") ||
        lower.includes("invalid")))
  ) {
    return { kind: "thinking_unsupported", httpStatus, message };
  }

  if (
    lower.includes("inline_data") ||
    lower.includes("inline data") ||
    lower.includes("unsupported mime") ||
    lower.includes("payload size") ||
    lower.includes("unable to process input image") ||
    lower.includes("invalid argument") && lower.includes("image")
  ) {
    return { kind: "invalid_image", httpStatus, message };
  }

  if (
    status === "SAFETY" ||
    lower.includes("blocked") ||
    lower.includes("prohibited") ||
    lower.includes("safety")
  ) {
    return { kind: "blocked", httpStatus, message };
  }

  if (
    httpStatus === 500 ||
    httpStatus === 502 ||
    httpStatus === 503 ||
    status === "UNAVAILABLE" ||
    status === "INTERNAL" ||
    status === "DEADLINE_EXCEEDED"
  ) {
    return { kind: "transient", httpStatus, message };
  }

  return { kind: "unknown", httpStatus, message };
}

export type AnalyzeErrorCode =
  | "GEMINI_BUSY"
  | "GEMINI_UNPAID"
  | "GEMINI_BLOCKED"
  | "GEMINI_INVALID_IMAGE"
  | "GEMINI_TIMEOUT"
  | "GEMINI_EMPTY"
  | "GEMINI_MALFORMED"
  | "GEMINI_TRANSIENT"
  | "GEMINI_UNKNOWN";

const unavailable = "Scoring is temporarily unavailable.";

export function userMessageForGeminiFailure(
  failure: GeminiFailure,
  surface: "photo" | "foods" = "photo",
): { error: string; status: number; code: AnalyzeErrorCode } {
  const foods = surface === "foods";
  switch (failure.kind) {
    case "unpaid":
      return {
        error: unavailable,
        status: 402,
        code: "GEMINI_UNPAID",
      };
    case "exhausted":
      return {
        error: foods
          ? "Could not score these foods right now. Try again in a moment."
          : "Vision is busy. Try again in a moment.",
        status: 429,
        code: "GEMINI_BUSY",
      };
    case "invalid_image":
      return {
        error: "That photo could not be read. Try another shot.",
        status: 422,
        code: "GEMINI_INVALID_IMAGE",
      };
    case "blocked":
      return {
        error: foods
          ? "That does not look like food."
          : "This photo could not be analyzed. Try another.",
        status: 422,
        code: "GEMINI_BLOCKED",
      };
    case "transient":
      return {
        error: foods ? unavailable : unavailable,
        status: 502,
        code: "GEMINI_TRANSIENT",
      };
    default:
      return {
        error: foods ? unavailable : unavailable,
        status: 502,
        code: "GEMINI_UNKNOWN",
      };
  }
}

// Timeout, 429, and 402 never enqueue another model call. thinking_unsupported
// may retry the same model with thinking off. Photos may take one fallback on
// a fast 5xx. Foods do not.
export function nextGeminiAction(
  failure: GeminiFailure,
  opts: {
    surface: "photo" | "foods";
    thinking: boolean;
    alreadyTriedFallback: boolean;
  },
): GeminiRetryAction {
  if (failure.kind === "thinking_unsupported" && opts.thinking) {
    return "retry_without_thinking";
  }
  if (
    failure.kind === "exhausted" ||
    failure.kind === "unpaid" ||
    failure.kind === "blocked" ||
    failure.kind === "invalid_image"
  ) {
    return "stop";
  }
  const timedOut = failure.httpStatus === 504 || failure.message === "timeout";
  if (timedOut) return "stop";
  if (
    opts.surface === "photo" &&
    failure.kind === "transient" &&
    !opts.alreadyTriedFallback
  ) {
    return "fallback_once";
  }
  return "stop";
}

// Safety finishes often have empty parts and no promptFeedback.blockReason.
// Those are "this photo is not a meal we will score", not a vendor outage.
export function isGeminiSafetyBlock(
  extracted: GeminiText | null,
  failure: GeminiFailure | null = null,
): boolean {
  if (failure?.kind === "blocked") return true;
  if (!extracted) return false;
  const blob = `${extracted.blockReason} ${extracted.finishReason}`
    .toUpperCase();
  return /SAFETY|RECITATION|PROHIBITED|BLOCKLIST|IMAGE_SAFETY/.test(blob);
}
