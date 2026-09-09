/**
 * İŞ PAKETİ 5 / DİLİM C — BACKEND İZİN ZORLAMASI.
 *
 * İstemcinin izin kapısı atlatılabilir (değiştirilmiş APK, doğrudan callable
 * çağrısı). Sunucu kendi kararını verir: izin YOKKEN hiçbir OpenAI çağrısı,
 * hiçbir kredi rezervasyonu ve hiçbir journal kaydı OLUŞMAZ.
 *
 * Kontrol, karar içeriği OKUNMADAN önce yapılır: izin vermemiş kullanıcının
 * içeriği analiz boru hattına hiç girmez.
 */
import { describe, expect, it } from "vitest";

import { buildService, ctx, reqId } from "./helpers/analyze_harness";
import { AI_CONSENT_VERSION } from "../src/privacy/ai_consent";
import { AppError } from "../src/core/errors";

const request = { decisionId: "d1", requestId: reqId("c") };

const validConsent = {
  granted: true,
  version: AI_CONSENT_VERSION,
  updatedAt: 1_700_000_000_000,
};

/** İzinsiz her senaryoda AYNI güvenli kod ve SIFIR yan etki beklenir. */
async function expectBlocked(h: ReturnType<typeof buildService>) {
  const before = {
    credits: h.ports.credits,
    tokens: h.tokens.total,
    spend: h.spend.total,
    daily: h.daily.slots,
  };
  await expect(h.service.run(ctx, request)).rejects.toMatchObject({
    code: "ai-consent-required",
  });

  expect(h.gateway.attempts, "OpenAI çağrısı").toBe(0);
  expect(h.gateway.completions, "OpenAI tamamlama").toBe(0);
  expect(h.ports.journal.size, "journal kaydı").toBe(0);
  expect(h.ports.commits, "analiz commit").toBe(0);
  expect(h.ports.reserved.credits, "kredi rezervasyonu").toBe(0);
  expect(h.ports.reserved.tokens, "token rezervasyonu").toBe(0);
  expect(h.ports.reserved.usd, "usd rezervasyonu").toBe(0);
  expect(h.ports.credits, "kredi bakiyesi").toBe(before.credits);
  expect(h.tokens.total).toBe(before.tokens);
  expect(h.spend.total).toBe(before.spend);
  expect(h.daily.slots, "günlük slot").toBe(before.daily);
  expect(h.rate.checks, "rate limit tüketimi").toBe(0);
  // İçerik boru hattına HİÇ girmez.
  expect(h.ports.contentReads, "karar içeriği okuması").toBe(0);
}

describe("izin yokken analiz engellenir", () => {
  it("izin belgesi YOK → engellenir, sıfır yan etki", async () => {
    const h = buildService();
    h.ports.aiConsent = null;
    await expectBlocked(h);
  });

  it("granted:false → engellenir", async () => {
    const h = buildService();
    h.ports.aiConsent = { ...validConsent, granted: false };
    await expectBlocked(h);
  });

  it("ESKİ sürüm izni geçerli SAYILMAZ", async () => {
    const h = buildService();
    h.ports.aiConsent = { ...validConsent, version: AI_CONSENT_VERSION - 1 };
    await expectBlocked(h);
  });

  it("bozuk belge (yanlış tip) → engellenir", async () => {
    const h = buildService();
    h.ports.aiConsent = { granted: "evet", version: AI_CONSENT_VERSION };
    await expectBlocked(h);
  });

  it("beklenmeyen fazla alan taşıyan belge → engellenir", async () => {
    const h = buildService();
    h.ports.aiConsent = { ...validConsent, escalate: true };
    await expectBlocked(h);
  });

  it("eksik alan (version yok) → engellenir", async () => {
    const h = buildService();
    h.ports.aiConsent = { granted: true, updatedAt: 1 };
    await expectBlocked(h);
  });

  it("Firestore OKUMA HATASI → FAIL CLOSED", async () => {
    const h = buildService();
    h.ports.consentReadError = new Error(
      "PERMISSION_DENIED: users/uid-SECRET/privacy/aiConsent",
    );
    await expectBlocked(h);
  });

  it("ham upstream hata metni istemciye SIZMAZ", async () => {
    const h = buildService();
    h.ports.consentReadError = new Error(
      "PERMISSION_DENIED: users/uid-SECRET/privacy/aiConsent",
    );
    const error = await h.service.run(ctx, request).catch((e) => e);
    expect(error).toBeInstanceOf(AppError);
    const text = `${(error as AppError).message} ${JSON.stringify(
      (error as AppError).details ?? {},
    )}`;
    for (const leak of ["PERMISSION_DENIED", "uid-SECRET", "users/", "privacy/"]) {
      expect(text.includes(leak), `sızıntı: ${leak}`).toBe(false);
    }
  });

  it("tekrar denemek durumu değiştirmez (retry yönergesi none)", async () => {
    const h = buildService();
    h.ports.aiConsent = null;
    const error = (await h.service.run(ctx, request).catch((e) => e)) as AppError;
    expect(error.code).toBe("ai-consent-required");
  });
});

describe("izin varken normal akış korunur", () => {
  it("geçerli izin → analiz üretilir ve TEK kredi işlenir", async () => {
    const h = buildService();
    h.ports.aiConsent = validConsent;
    const result = await h.service.run(ctx, request);

    expect(result.analysisId).toBeTruthy();
    expect(h.gateway.completions).toBe(1);
    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4); // 5 → 4, tek işlem
  });

  it("izin kontrolü karar içeriği OKUNMADAN ÖNCE yapılır", async () => {
    const h = buildService();
    h.ports.aiConsent = null;
    await h.service.run(ctx, request).catch(() => undefined);
    expect(h.ports.contentReads).toBe(0);

    const ok = buildService();
    ok.ports.aiConsent = validConsent;
    await ok.service.run(ctx, request);
    expect(ok.ports.contentReads).toBeGreaterThan(0);
  });

  it("izin GERİ ALINDIKTAN sonraki istek engellenir", async () => {
    const h = buildService();
    h.ports.aiConsent = validConsent;
    await h.service.run(ctx, request);
    expect(h.gateway.completions).toBe(1);

    // Kullanıcı ayarlardan izni geri aldı.
    h.ports.aiConsent = { ...validConsent, granted: false };
    await expect(
      h.service.run(ctx, { ...request, requestId: reqId("d") }),
    ).rejects.toMatchObject({ code: "ai-consent-required" });
    expect(h.gateway.completions, "ikinci çağrı YOK").toBe(1);
  });
});
