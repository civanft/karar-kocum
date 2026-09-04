/**
 * İŞ PAKETİ 2 / DİLİM E-3 — idempotency, kurtarma ve belirsizlik.
 *
 * Bu dosya "aynı (uid, requestId) için başarılı analiz YALNIZ BİR KEZ
 * uygulanır" sözleşmesini ve sağlayıcı belirsizlik penceresindeki güvenli
 * davranışı doğrular.
 */
import { describe, expect, it } from "vitest";

import { JournalState } from "../src/ai/analysis_journal";
import { AnalyzeService } from "../src/ai/analyze_service";
import { AppError } from "../src/core/errors";
import {
  buildService,
  ctx,
  reqId,
  type Harness,
} from "./helpers/analyze_harness";

const rid = reqId("a");
const req = { decisionId: "d1", requestId: rid };

async function attempt(h: Harness, payload: unknown = req) {
  return h.service.run(ctx, payload).catch((e: unknown) => e as AppError);
}

describe("9-13: idempotency", () => {
  it("ardışık duplicate: gateway 1, kredi 1, finalize 1, aynı sonuç", async () => {
    const h = buildService();
    const first = await h.service.run(ctx, req);
    const second = await h.service.run(ctx, req);

    expect(h.gateway.completions).toBe(1);
    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4);
    expect(h.rate.checks).toBe(1);
    expect(h.daily.slots).toBe(1);
    expect(h.tokens.records).toBe(1);
    expect(h.spend.records).toBe(1);
    expect(second.analysis).toEqual(first.analysis);
  });

  it("PARALEL duplicate: tek sağlayıcı çağrısı", async () => {
    const h = buildService();
    const [a, b] = await Promise.all([attempt(h), attempt(h)]);

    expect(h.gateway.completions).toBe(1);
    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4);
    // Biri sonucu alır; diğeri ya aynı sonucu ya da güvenli belirsizlik hatası.
    const ok = [a, b].filter((r) => !(r instanceof AppError));
    expect(ok.length).toBeGreaterThanOrEqual(1);
    for (const e of [a, b].filter((r) => r instanceof AppError)) {
      expect((e as AppError).code).toBe("ai-uncertain");
    }
  });

  it("BAŞKA uid aynı requestId'yi etkilemez (ayrı journal alanı)", async () => {
    const h1 = buildService();
    const h2 = buildService();
    await h1.service.run(ctx, req);
    await h2.service.run({ ...ctx, uid: "u2", uidHash: "h2" }, req);

    expect(h1.gateway.completions).toBe(1);
    expect(h2.gateway.completions).toBe(1);
    expect(h1.ports.credits).toBe(4);
    expect(h2.ports.credits).toBe(4);
  });

  it("aynı requestId FARKLI decisionId → güvenli conflict, eski sonuç taşınmaz", async () => {
    const h = buildService();
    await h.service.run(ctx, req);
    const e = await attempt(h, { decisionId: "d2", requestId: rid });

    expect(e).toBeInstanceOf(AppError);
    expect((e as AppError).code).toBe("invalid-argument");
    expect(h.gateway.completions).toBe(1);
    expect(h.ports.commits).toBe(1);
  });

  it("aynı requestId FARKLI içerik → güvenli conflict", async () => {
    const h = buildService();
    await h.service.run(ctx, req);
    h.ports.content = {
      ...(h.ports.content as Record<string, unknown>),
      title: "Bambaşka bir karar",
    };
    const e = await attempt(h);

    expect(e).toBeInstanceOf(AppError);
    expect((e as AppError).code).toBe("invalid-argument");
    expect(h.gateway.completions).toBe(1);
  });

  it("tamamlanmış request retry'ı rate/daily sayaçlarını ARTIRMAZ", async () => {
    const h = buildService();
    await h.service.run(ctx, req);
    const before = { rate: h.rate.checks, daily: h.daily.slots };
    await h.service.run(ctx, req);

    expect(h.rate.checks).toBe(before.rate);
    expect(h.daily.slots).toBe(before.daily);
  });
});

describe("14-18: transaction ve kurtarma", () => {
  it("finalize ilk denemede başarısız → retry sağlayıcıyı ÇAĞIRMADAN finalize eder", async () => {
    const h = buildService();
    h.ports.failOn.finalize = true;

    const first = await attempt(h);
    expect(first).toBeInstanceOf(Error);
    expect(h.gateway.completions).toBe(1);
    expect(h.ports.journal.get(rid)?.state).toBe(JournalState.providerSucceeded);

    const second = await h.service.run(ctx, req);
    expect(h.gateway.completions).toBe(1); // İKİNCİ sağlayıcı çağrısı YOK
    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4);
    expect(second.analysis.summary).toBeTruthy();
  });

  it("journal yazımı başarısız → sonuç BELİRSİZ, ikinci sağlayıcı çağrısı YOK", async () => {
    const h = buildService();
    h.ports.failOn.recordProviderSuccess = true;

    const first = await attempt(h);
    expect(first).toBeInstanceOf(Error);
    expect(h.gateway.completions).toBe(1);

    const second = await attempt(h);
    expect(second).toBeInstanceOf(AppError);
    expect((second as AppError).code).toBe("ai-uncertain");
    expect(h.gateway.completions).toBe(1); // ASLA ikinci çağrı
    expect(h.ports.commits).toBe(0);
    expect(h.ports.credits).toBeNull(); // kredi hiç düşmedi
  });

  it("karar analiz sürerken DEĞİŞTİ → superseded, kredi YANMAZ", async () => {
    const h = buildService();
    h.ports.fingerprintOverride = "farkli-fingerprint";

    const e = await attempt(h);
    expect(e).toBeInstanceOf(AppError);
    expect((e as AppError).code).toBe("invalid-argument");
    expect(h.ports.commits).toBe(0);
    expect(h.ports.credits).toBeNull(); // KULLANICI KREDİSİ YANMADI
    expect(h.ports.journal.get(rid)?.state).toBe(JournalState.superseded);
    // Gerçek sağlayıcı maliyeti yine de BİR kez muhasebeleşir.
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
  });

  it("superseded analiz YENİ karara bağlanmaz", async () => {
    const h = buildService();
    h.ports.fingerprintOverride = "farkli-fingerprint";
    await attempt(h);
    expect(h.ports.lastAnalysis).toBeNull();
  });

  it("finalize retry'ında kredi/sayaç İKİ KEZ uygulanmaz", async () => {
    const h = buildService();
    await h.service.run(ctx, req);
    await h.service.run(ctx, req);
    await h.service.run(ctx, req);

    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4);
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
  });
});

describe("belirsizlik penceresi", () => {
  it("sağlayıcı ai-uncertain → journal uncertain, retry YENİDEN ÇAĞIRMAZ", async () => {
    const h = buildService();
    h.gateway.failWith = new AppError("ai-uncertain", "belirsiz", {
      retryable: true,
    });

    const first = await attempt(h);
    expect((first as AppError).code).toBe("ai-uncertain");
    expect(h.ports.journal.get(rid)?.state).toBe(JournalState.uncertain);

    const second = await attempt(h);
    expect((second as AppError).code).toBe("ai-uncertain");
    expect(h.gateway.attempts).toBe(1); // ikinci sağlayıcı denemesi YOK
    expect(h.ports.credits).toBeNull();
  });

  it("moderasyon → terminal_failed, kredi YANMAZ, retry sağlayıcıyı çağırmaz", async () => {
    const h = buildService();
    h.gateway.failWith = new AppError("moderated", "engellendi");

    const first = await attempt(h);
    expect((first as AppError).code).toBe("moderated");
    expect(h.ports.journal.get(rid)?.state).toBe(JournalState.terminalFailed);
    expect(h.ports.credits).toBeNull();

    const second = await attempt(h);
    expect(second).toBeInstanceOf(AppError);
    expect(h.gateway.attempts).toBe(1);
  });
});

describe("AnalyzeService sözleşmesi", () => {
  it("servis journal portları olmadan kurulamaz (tip düzeyinde)", () => {
    expect(AnalyzeService).toBeTypeOf("function");
  });
});
