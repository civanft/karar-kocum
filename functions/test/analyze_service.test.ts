/**
 * Sadeleştirilmiş boru hattı testleri (6C-3): doğrulama → rate/kredi/
 * kesici sırası → AI sağlayıcısı → tek commit. Kota adaleti invariant'ları
 * (6C-2) korunur: hata/moderasyon/rate reddi kredi YAKMAZ.
 */
import { describe, expect, it } from "vitest";

import {
  buildService,
  ctx,
  reqId,
  validContent,
  validOutput,
} from "./helpers/analyze_harness";
import { LATEST_ANALYSIS_ID } from "../src/ai/analyze_service";
import { SELF_HARM_REDIRECT } from "../src/ai/openai_gateway";
import { AppError } from "../src/core/errors";

/**
 * 2B: sahteler paylaşılan harness'a taşındı. Kabul kontrolü artık ayrı
 * guard nesnelerinde değil, ports.reserve() kabul transaction'ının
 * içindedir — bu yüzden limitler `buildService` üzerinden verilir.
 */
function make(overrides?: {
  spendTotal?: number;
  dailyLimit?: number;
  tokenLimit?: number;
  tokenTotal?: number;
}) {
  const h = buildService({
    spendTotal: overrides?.spendTotal,
    tokenTotal: overrides?.tokenTotal,
    limits: {
      ...(overrides?.dailyLimit != null
        ? { dailyAnalyses: overrides.dailyLimit }
        : {}),
      ...(overrides?.tokenLimit != null
        ? { dailyTokens: overrides.tokenLimit }
        : {}),
    },
  });
  return {
    service: h.service,
    ports: h.ports,
    gateway: h.gateway,
    rate: h.rate,
    spend: h.spend,
    counter: h.daily,
    tokens: h.tokens,
  };
}

// İş Paketi 2: payload STRICT ve requestId ZORUNLU (idempotency anahtarı).
const reqId = (seed: string) => seed.repeat(24).slice(0, 24);
const request = { decisionId: "d1", requestId: reqId("a") };

describe("mutlu yol", () => {
  it("analiz üretir, latest'e commit'ler, kredi 5→4, maliyet kaydedilir", async () => {
    const { service, ports, spend } = make();
    const result = await service.run(ctx, request);

    expect(result.analysisId).toBe(LATEST_ANALYSIS_ID);
    expect(result.analysis.summary).toBe(validOutput.summary);
    expect(result.analysis.recommendation).toContain("iPhone");
    expect(result.analysis.model).toBe("gpt-4.1-mini");
    expect(result.analysis.promptVersion).toBe("mvp-1");
    expect(ports.commits).toBe(1);
    expect(ports.credits).toBe(4); // lazy-init 5 → 4
    expect(spend.total).toBeGreaterThan(0);
    // Maliyet hedefi: analiz başına < $0,002 (gpt-4.1-mini ~$0,00156)
    expect(spend.total).toBeLessThan(0.002);
  });

  // SÖZLEŞME DEĞİŞİKLİĞİ (İş Paketi 2): eskiden AYNI requestId ile ikinci
  // çağrı ikinci bir ÜCRETLİ sağlayıcı isteği ve İKİNCİ kredi düşümü
  // üretiyordu. Artık idempotent. Gerçek "yeniden analiz" YENİ requestId
  // ile gelir ve o zaman yeni bir analiz üretilir.
  it("AYNI requestId ile ikinci çağrı idempotenttir", async () => {
    const { service, ports, gateway } = make();
    const first = await service.run(ctx, request);
    const second = await service.run(ctx, request);

    expect(first.analysisId).toBe(second.analysisId);
    expect(second.analysis).toEqual(first.analysis);
    expect(gateway.completions).toBe(1); // ikinci sağlayıcı çağrısı YOK
    expect(ports.commits).toBe(1);
    expect(ports.credits).toBe(4); // kredi YALNIZ bir kez düştü
  });

  it("YENİ requestId gerçek yeniden analiz üretir, aynı kimliğe yazar", async () => {
    const { service, ports, gateway } = make();
    const first = await service.run(ctx, request);
    const second = await service.run(ctx, {
      decisionId: "d1",
      requestId: reqId("c"),
    });
    expect(first.analysisId).toBe(second.analysisId);
    expect(gateway.completions).toBe(2);
    expect(ports.commits).toBe(2);
    expect(ports.credits).toBe(3);
  });
});

describe("kredi adaleti (6C-2 invariant'ları)", () => {
  it("kredi 0 → quota-exceeded, OpenAI hiç çağrılmaz", async () => {
    const { service, ports, gateway } = make();
    ports.credits = 0;
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("quota-exceeded");
    expect(gateway.completions).toBe(0);
  });

  it("kredi 1→0: geçer; ikincisi reddedilir; negatif imkânsız", async () => {
    const { service, ports, gateway } = make();
    ports.credits = 1;

    await service.run(ctx, request);
    expect(ports.credits).toBe(0);

    const error = await service
      .run(ctx, { decisionId: "d2", requestId: reqId("b") })
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("quota-exceeded");
    expect(ports.credits).toBe(0); // değişmedi
    expect(gateway.completions).toBe(1);
  });

  it("OpenAI moderasyon bloğu kredi YAKMAZ", async () => {
    const { service, ports, gateway } = make();
    gateway.failWith = new AppError("moderated", SELF_HARM_REDIRECT, {
      selfHarm: true,
    });

    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("moderated");
    expect((error as AppError).message).toBe(SELF_HARM_REDIRECT);
    expect(ports.credits).toBeNull(); // kredi yanmadı
    expect(ports.commits).toBe(0);
  });

  it("OpenAI kesintisi (ai-unavailable) kredi YAKMAZ", async () => {
    const { service, ports, gateway } = make();
    gateway.failWith = new AppError("ai-unavailable", "kesinti", {
      retryable: true,
    });
    await service.run(ctx, request).catch(() => undefined);
    expect(ports.credits).toBeNull();
    expect(ports.commits).toBe(0);
  });

  it("premium: kredi sınırı ve kesici bypass", async () => {
    const { service, ports } = make({ spendTotal: 1 }); // kesici eşik üstü
    ports.plan = "premium";
    ports.credits = 0;
    const result = await service.run(ctx, request);
    expect(result.analysisId).toBe(LATEST_ANALYSIS_ID);
  });
});

describe("koruma sırası", () => {
  it("rate reddi OpenAI'den önce keser", async () => {
    const { service, ports, gateway } = make();
    ports.rateReject = true;
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("rate-limited");
    expect(gateway.completions).toBe(0);
    expect(ports.credits).toBeNull();
  });

  it("7B: günlük ADET limiti dolunca doğru mesaj, kredi YANMAZ", async () => {
    const { service, ports, gateway } = make({ dailyLimit: 1 });

    await service.run(ctx, request); // slot 1/1
    const error = await service
      .run(ctx, { decisionId: "d2", requestId: reqId("b") })
      .catch((e: unknown) => e);

    expect((error as AppError).code).toBe("daily-limit");
    expect((error as AppError).message).toContain(
      "Bugünkü analiz limiti doldu",
    );
    expect(gateway.completions).toBe(1); // ikinci istek sağlayıcıya gitmedi
    expect(ports.credits).toBe(4); // yalnız ilk analiz kredi düşürdü
  });

  it("7B: başarılı analiz global sayacı 1 artırır", async () => {
    const { service, counter } = make();
    await service.run(ctx, request);
    expect(counter.total).toBe(1);
  });

  it("cost guard: başarılı analiz token sayacına giriş+çıkış ekler", async () => {
    const { service, tokens } = make();
    await service.run(ctx, request);
    expect(tokens.total).toBe(2100); // 1500 giriş + 600 çıkış
  });

  it("cost guard: günlük token tavanı dolunca daily-limit, kredi YANMAZ", async () => {
    const { service, ports, gateway } = make({ tokenTotal: 375_000 });
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("daily-limit");
    expect(gateway.completions).toBe(0);
    expect(ports.credits).toBeNull();
  });

  it("cost guard: giriş boyutu MAX_INPUT_CHARS aşarsa invalid-argument", async () => {
    const { service, ports, gateway } = make();
    // 8 dolu seçenek × (20 artı + 20 eksi) × 140 kr ≈ 45K kr > 24K tavan.
    ports.content = {
      ...validContent,
      options: Array.from({ length: 8 }, (_, i) => ({
        id: `o${i}`,
        title: `Seçenek ${i}`,
        pros: Array.from({ length: 20 }, () => "x".repeat(140)),
        cons: Array.from({ length: 20 }, () => "y".repeat(140)),
      })),
    };
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");
    expect((error as AppError).details?.["maxInputChars"]).toBe(24_000);
    expect(gateway.completions).toBe(0);
  });

  it("günlük tavan aşımı: free kullanıcı ai-unavailable", async () => {
    const { service } = make({ spendTotal: 0.16 }); // > $0,15
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("ai-unavailable");
    expect((error as AppError).details?.["circuitBreaker"]).toBe(true);
  });
});

describe("girdi doğrulama", () => {
  it("olmayan karar / bozuk istek / tek seçenek → invalid-argument", async () => {
    const { service, ports } = make();

    ports.content = null;
    let error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");

    ports.content = validContent;
    error = await service.run(ctx, { yanlis: 1 }).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");

    ports.content = { ...validContent, options: [validContent.options[0]] };
    error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");
  });
});
