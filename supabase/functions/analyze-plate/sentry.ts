// Reports analyze-plate failures to Sentry over HTTP. No SDK import so the
// function stays small and this file can be unit tested without Deno.
//
// Never put photos, food lists, or email in [extra] or [message].

export interface SentryDsn {
  storeUrl: string;
  sentryKey: string;
}

export interface AnalyzeIssue {
  feature: string;
  code: string;
  level?: "error" | "warning" | "info";
  model?: string;
  httpStatus?: number;
  detail?: string;
  source?: string;
}

export function parseSentryDsn(dsn: string): SentryDsn | null {
  const trimmed = dsn.trim();
  if (!trimmed) return null;
  const match = trimmed.match(/^(https?):\/\/([^@]+)@([^/]+)\/(\d+)\s*$/);
  if (!match) return null;
  const [, protocol, sentryKey, host, projectId] = match;
  if (!sentryKey || !host || !projectId) return null;
  return {
    storeUrl: `${protocol}://${host}/api/${projectId}/store/`,
    sentryKey,
  };
}

export function analyzeIssuePayload(issue: AnalyzeIssue): Record<string, unknown> {
  const eventId = crypto.randomUUID().replace(/-/g, "");
  const extra: Record<string, string> = { code: issue.code };
  if (issue.httpStatus != null) extra.http_status = String(issue.httpStatus);
  if (issue.detail) extra.detail = issue.detail.slice(0, 240);
  if (issue.model) extra.model = issue.model;
  const source = issue.source ?? "analyze-plate";

  return {
    event_id: eventId,
    timestamp: Date.now() / 1000,
    platform: "javascript",
    logger: source,
    environment: "production",
    server_name: source,
    level: issue.level ?? "error",
    fingerprint: [issue.feature],
    message: issue.detail
      ? `${issue.feature}: ${issue.detail.slice(0, 180)}`
      : issue.feature,
    tags: {
      feature: issue.feature,
      source,
      code: issue.code,
    },
    extra,
  };
}

export async function reportAnalyzeIssue(
  dsn: string,
  issue: AnalyzeIssue,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const parsed = parseSentryDsn(dsn);
  if (!parsed) return;

  const payload = analyzeIssuePayload(issue);
  try {
    await fetchImpl(parsed.storeUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Sentry-Auth":
          `Sentry sentry_version=7, sentry_client=evenplate-analyze-plate/1.0.0, sentry_key=${parsed.sentryKey}`,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(2000),
    });
  } catch (error) {
    console.error("Sentry report failed", error);
  }
}
