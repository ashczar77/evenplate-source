// Tests Gemini error classification and text extraction.
//
// Run with: make test-vision

import {
  analysisTextFromGemini,
  classifyGeminiFailure,
  isGeminiSafetyBlock,
  nextGeminiAction,
  userMessageForGeminiFailure,
} from "../supabase/functions/analyze-plate/gemini.ts";

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

console.log("\nClassifying Gemini HTTP failures");

check(
  "HTTP 402 is unpaid",
  classifyGeminiFailure(402, '{"error":{"code":402,"status":"PAYMENT_REQUIRED","message":"credit balance"}}')
    .kind,
  "unpaid",
);

check(
  "HTTP 429 is exhausted",
  classifyGeminiFailure(429, '{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"quota"}}')
    .kind,
  "exhausted",
);

check(
  "quota wrapped as HTTP 400 is still exhausted",
  classifyGeminiFailure(
    400,
    '{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"Resource exhausted"}}',
  ).kind,
  "exhausted",
);

check(
  "thinking config 400 is thinking_unsupported",
  classifyGeminiFailure(
    400,
    '{"error":{"message":"Unknown name thinkingConfig","status":"INVALID_ARGUMENT"}}',
  ).kind,
  "thinking_unsupported",
);

check(
  "image payload 400 is invalid_image",
  classifyGeminiFailure(
    400,
    '{"error":{"message":"Unable to process input image","status":"INVALID_ARGUMENT"}}',
  ).kind,
  "invalid_image",
);

check(
  "500 is transient",
  classifyGeminiFailure(500, '{"error":{"status":"INTERNAL","message":"boom"}}').kind,
  "transient",
);

check(
  "exhausted maps to the busy line",
  userMessageForGeminiFailure({
    kind: "exhausted",
    httpStatus: 400,
    message: "Resource exhausted",
  }),
  {
    error: "Vision is busy. Try again in a moment.",
    status: 429,
    code: "GEMINI_BUSY",
  },
);

check(
  "unpaid copy does not tell the user to try again",
  userMessageForGeminiFailure({
    kind: "unpaid",
    httpStatus: 402,
    message: "prepaid",
  }),
  {
    error: "Scoring is temporarily unavailable.",
    status: 402,
    code: "GEMINI_UNPAID",
  },
);

check(
  "unknown maps to a retry line, not a Gemini brand string",
  userMessageForGeminiFailure({
    kind: "unknown",
    httpStatus: 400,
    message: "nope",
  }).error.includes("Gemini"),
  false,
);

check(
  "foods unknown does not mention a photo",
  userMessageForGeminiFailure({
    kind: "unknown",
    httpStatus: 404,
    message: "model gone",
  }, "foods").error.includes("photo"),
  false,
);

check(
  "foods quota is busy, not a photo error",
  userMessageForGeminiFailure({
    kind: "exhausted",
    httpStatus: 429,
    message: "quota",
  }, "foods"),
  {
    error: "Could not score these foods right now. Try again in a moment.",
    status: 429,
    code: "GEMINI_BUSY",
  },
);

console.log("\nExtracting analysis text");

check(
  "skips thought parts",
  analysisTextFromGemini({
    candidates: [{
      finishReason: "STOP",
      content: {
        parts: [
          { thought: true, text: "planning" },
          { text: '{"mealName":"Soup"}' },
        ],
      },
    }],
  }).text,
  '{"mealName":"Soup"}',
);

check(
  "empty candidates yield no text",
  analysisTextFromGemini({ candidates: [] }).text,
  null,
);

console.log("\nSafety blocks are not_food, not an outage");

check(
  "SAFETY finish is a block",
  isGeminiSafetyBlock({
    text: null,
    finishReason: "SAFETY",
    blockReason: "",
  }),
  true,
);

check(
  "HTTP blocked kind is a block even with no text",
  isGeminiSafetyBlock(null, {
    kind: "blocked",
    httpStatus: 400,
    message: "safety",
  }),
  true,
);

check(
  "empty unknown finish is not a block",
  isGeminiSafetyBlock({
    text: null,
    finishReason: "STOP",
    blockReason: "",
  }),
  false,
);

console.log("\nRetry policy never stacks timeout, 429, or 402");

const stopOpts = {
  surface: "foods" as const,
  thinking: true,
  alreadyTriedFallback: false,
};

check(
  "timeout stops foods",
  nextGeminiAction({ kind: "transient", httpStatus: 504, message: "timeout" }, stopOpts),
  "stop",
);

check(
  "exhausted stops foods",
  nextGeminiAction({ kind: "exhausted", httpStatus: 429, message: "quota" }, stopOpts),
  "stop",
);

check(
  "unpaid stops foods",
  nextGeminiAction({ kind: "unpaid", httpStatus: 402, message: "prepaid" }, stopOpts),
  "stop",
);

check(
  "timeout stops photo fallback",
  nextGeminiAction(
    { kind: "transient", httpStatus: 504, message: "timeout" },
    { surface: "photo", thinking: true, alreadyTriedFallback: false },
  ),
  "stop",
);

check(
  "thinking unsupported retries without thinking",
  nextGeminiAction(
    { kind: "thinking_unsupported", httpStatus: 400, message: "thinkingConfig" },
    stopOpts,
  ),
  "retry_without_thinking",
);

check(
  "photo 5xx may fallback once",
  nextGeminiAction(
    { kind: "transient", httpStatus: 503, message: "unavailable" },
    { surface: "photo", thinking: false, alreadyTriedFallback: false },
  ),
  "fallback_once",
);

check(
  "foods 5xx does not fallback",
  nextGeminiAction(
    { kind: "transient", httpStatus: 503, message: "unavailable" },
    stopOpts,
  ),
  "stop",
);

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) {
  throw new Error(`${failed} gemini failure test(s) failed`);
}
