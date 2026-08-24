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
  "AI_DAILY_SPEND_LIMIT_USD",
  "DAILY_TOKEN_LIMIT",
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

/** PR-COST-1 — GLOBAL günlük maliyet devre kesicisinin üretim tabanı.
 *
 *  Aynı save/restore sözleşmesini kullanır (ENV_KEYS genişletildi), bu yüzden
 *  senaryolar sıra bağımsızdır ve env sızıntısı olmaz. */
describe("günlük maliyet tavanı", () => {
  it("env yokken üretim tabanı 0.08 USD / 50.000 token", async () => {
    delete process.env.AI_DAILY_SPEND_LIMIT_USD;
    delete process.env.DAILY_TOKEN_LIMIT;
    const config = await import("../src/config");
    expect(config.DAILY_SPEND_LIMIT_USD).toBe(0.08);
    expect(config.DAILY_TOKEN_LIMIT).toBe(50_000);
  });

  it("env override'ları hâlâ çalışır", async () => {
    process.env.AI_DAILY_SPEND_LIMIT_USD = "0.12";
    process.env.DAILY_TOKEN_LIMIT = "90000";
    const config = await import("../src/config");
    expect(config.DAILY_SPEND_LIMIT_USD).toBe(0.12);
    expect(config.DAILY_TOKEN_LIMIT).toBe(90_000);
  });
});
