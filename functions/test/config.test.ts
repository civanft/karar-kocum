import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

/** Release 6E-A — per-user analiz limitleri ÜRETİM varsayılanı (3/10/3).
 *
 *  config.ts env'i modül yükünde okur; bu yüzden her senaryo modül
 *  cache'ini sıfırlayıp dinamik import kullanır. Env değerleri test
 *  sonunda geri yüklenir → diğer testlere sızıntı yok, sıra bağımsız. */
const ENV_KEYS = [
  "USER_ANALYZE_PER_MINUTE",
  "USER_ANALYZE_PER_HOUR",
  "USER_ANALYZE_PER_DAY",
] as const;

const savedEnv: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const key of ENV_KEYS) savedEnv[key] = process.env[key];
  vi.resetModules();
});

afterEach(() => {
  for (const key of ENV_KEYS) {
    const value = savedEnv[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  vi.resetModules();
});

describe("PER_USER_ANALYZE_LIMITS", () => {
  it("env yokken üretim varsayılanı 3/10/3", async () => {
    for (const key of ENV_KEYS) delete process.env[key];
    const config = await import("../src/config");
    expect(config.PER_USER_ANALYZE_LIMITS.perMinute).toBe(3);
    expect(config.PER_USER_ANALYZE_LIMITS.perHour).toBe(10);
    expect(config.PER_USER_ANALYZE_LIMITS.perDay).toBe(3);
  });

  it("env override'ları hâlâ çalışır (geliştirme/yük testi yolu)", async () => {
    process.env.USER_ANALYZE_PER_MINUTE = "20";
    process.env.USER_ANALYZE_PER_HOUR = "200";
    process.env.USER_ANALYZE_PER_DAY = "1000";
    const config = await import("../src/config");
    expect(config.PER_USER_ANALYZE_LIMITS.perMinute).toBe(20);
    expect(config.PER_USER_ANALYZE_LIMITS.perHour).toBe(200);
    expect(config.PER_USER_ANALYZE_LIMITS.perDay).toBe(1000);
  });
});
