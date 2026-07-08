/**
 * Monitoring kancaları — AI-ANALIZ-TASARIMI.md §9.1.
 * Metrikler yapılandırılmış log satırı olarak yayımlanır; Cloud Monitoring
 * log-based metric tanımları bu event/alan adlarına bağlanır:
 *   event: "metric", metric: <ad>, value: <sayı>, ...etiketler
 */
import { log } from "./logger.js";
import type { RequestContext } from "./types.js";

export type MetricName =
  | "ai_latency_first_chunk_ms"
  | "ai_latency_total_ms"
  | "ai_error"
  | "ai_schema_failure"
  | "ai_cache_hit"
  | "ai_cost_usd"
  | "rate_limit_rejection"
  | "request_duration_ms";

export function emitMetric(
  ctx: RequestContext,
  metric: MetricName,
  value: number,
  labels: Record<string, string | number | boolean> = {},
): void {
  log("info", "metric", ctx, { metric, value, ...labels });
}

/** Süre ölçer: const stop = startTimer(); ... stop() → geçen ms. */
export function startTimer(): () => number {
  const start = process.hrtime.bigint();
  return () => Number((process.hrtime.bigint() - start) / 1_000_000n);
}

/** İstek kapanışı: süre metriği + bitiş logu tek yerden. */
export function finishRequest(
  ctx: RequestContext,
  outcome: "ok" | "error",
  labels: Record<string, string | number | boolean> = {},
): void {
  emitMetric(ctx, "request_duration_ms", Date.now() - ctx.startedAtMs, {
    outcome,
    ...labels,
  });
}
