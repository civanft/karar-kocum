/**
 * İŞ PAKETİ 2B — muhasebe atomikliği (RED-first).
 *
 * Bağımsız denetim bulgusu #1: AI sonucu, journal, kredi, maliyet ve token
 * muhasebesi ATOMİK DEĞİL. `finalize` transaction'ı journal + kredi + analiz
 * yazıyor; spend ve token sayaçları transaction'dan SONRA ayrı side effect
 * olarak yazılıyor. Bu testler doğru sözleşmeyi tarif eder.
 *
 * Sözleşme:
 *  - `completed` journal ancak Firestore içindeki TÜM muhasebe tamamlandıysa
 *    yazılır.
 *  - Muhasebe yazımı başarısız olursa journal kurtarılabilir durumda kalır ve
 *    aynı requestId ile retry eksik muhasebeyi TAMAMLAR.
 *  - Hiçbir senaryoda kredi/spend/token birden fazla kez uygulanmaz.
 */
import { describe, expect, it } from "vitest";

import { buildService, ctx, reqId } from "./helpers/analyze_harness";
import { JournalState } from "../src/ai/analysis_journal";

const decisionId = "d1";
const payload = (rid: string) => ({ decisionId, requestId: rid });

describe("muhasebe atomikliği — spend yazımı başarısız", () => {
  it("spend yazımı çökerse journal completed KALMAZ ve retry muhasebeyi tamamlar", async () => {
    const h = buildService();
    const rid = reqId("a");

    h.spend.failNext = true;
    await expect(h.service.run(ctx, payload(rid))).rejects.toThrow();

    // Journal, muhasebe tamamlanmadan terminal `completed` olmamalı.
    expect(h.ports.journal.get(rid)!.state).not.toBe(JournalState.completed);

    // Aynı requestId ile retry: sağlayıcı YENİDEN çağrılmaz, eksik muhasebe
    // tamamlanır, kredi ikinci kez düşmez.
    await h.service.run(ctx, payload(rid));

    expect(h.gateway.completions).toBe(1);
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
    expect(h.ports.credits).toBe(4);
    expect(h.ports.commits).toBe(1);
  });
});

describe("muhasebe atomikliği — token yazımı başarısız", () => {
  it("token yazımı çökerse aynı sözleşme geçerlidir", async () => {
    const h = buildService();
    const rid = reqId("b");

    h.tokens.failNext = true;
    await expect(h.service.run(ctx, payload(rid))).rejects.toThrow();
    expect(h.ports.journal.get(rid)!.state).not.toBe(JournalState.completed);

    await h.service.run(ctx, payload(rid));

    expect(h.gateway.completions).toBe(1);
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
    expect(h.ports.credits).toBe(4);
  });
});

describe("muhasebe atomikliği — kısmî yazım", () => {
  it("spend yazıldı, token çöktü: retry ÇİFT spend üretmez", async () => {
    const h = buildService();
    const rid = reqId("c");

    h.tokens.failNext = true;
    await expect(h.service.run(ctx, payload(rid))).rejects.toThrow();

    await h.service.run(ctx, payload(rid));

    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
  });
});

describe("muhasebe atomikliği — tekrarlanan finalize", () => {
  it("aynı requestId ÜÇ kez çalıştığında her muhasebe TAM BİR kez uygulanır", async () => {
    const h = buildService();
    const rid = reqId("d");

    await h.service.run(ctx, payload(rid));
    await h.service.run(ctx, payload(rid));
    await h.service.run(ctx, payload(rid));

    expect(h.gateway.completions).toBe(1);
    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4);
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
  });

  it("PARALEL finalize'da muhasebe TAM BİR kez uygulanır", async () => {
    const h = buildService();
    const rid = reqId("e");

    // Sağlayıcı sonucu dayanıklı yazılana kadar ilerlet, sonra 8 paralel retry.
    await h.service.run(ctx, payload(rid));
    h.ports.journal.get(rid)!.state = JournalState.providerSucceeded;
    h.ports.credits = 5;
    h.ports.commits = 0;
    h.spend.records = 0;
    h.tokens.records = 0;

    await Promise.all(
      Array.from({ length: 8 }, () =>
        h.service.run(ctx, payload(rid)).catch(() => undefined),
      ),
    );

    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4);
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
  });
});

describe("muhasebe atomikliği — superseded", () => {
  it("karar değiştiyse kredi düşmez ama gerçek maliyet TAM BİR kez kaydedilir", async () => {
    const h = buildService();
    const rid = reqId("f");

    h.ports.fingerprintOverride = "degisti";
    await expect(h.service.run(ctx, payload(rid))).rejects.toThrow();

    expect(h.ports.credits).toBe(null); // hiç düşmedi
    expect(h.ports.commits).toBe(0); // analiz karara bağlanmadı
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);

    // Aynı requestId tekrar gelirse maliyet İKİNCİ kez kaydedilmez.
    await expect(h.service.run(ctx, payload(rid))).rejects.toThrow();
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
  });
});

describe("muhasebe atomikliği — provider_succeeded kurtarma", () => {
  it("final transaction geçici olarak çökse de retry saklanan sonucu kullanır", async () => {
    const h = buildService();
    const rid = reqId("g");

    h.ports.failOn.finalize = true;
    await expect(h.service.run(ctx, payload(rid))).rejects.toThrow();
    expect(h.ports.journal.get(rid)!.state).toBe(JournalState.providerSucceeded);

    await h.service.run(ctx, payload(rid));

    expect(h.gateway.attempts).toBe(1); // OpenAI YENİDEN çağrılmadı
    expect(h.ports.commits).toBe(1);
    expect(h.ports.credits).toBe(4);
    expect(h.spend.records).toBe(1);
    expect(h.tokens.records).toBe(1);
  });
});

describe("rezervasyon sözleşmesi", () => {
  it("reserve() kotaları da rezerve eder — yalnız journal oluşturmaz", async () => {
    const h = buildService();
    const rid = reqId("h");

    await h.service.run(ctx, payload(rid));
    expect(h.daily.slots).toBe(1);

    // AYNI requestId ile retry rezervasyonları TEKRAR artırmaz.
    await h.service.run(ctx, payload(rid));
    expect(h.daily.slots).toBe(1);
    expect(h.rate.checks).toBe(1);
  });

  it("son ücretsiz kredi için yarışan İKİ FARKLI requestId'den yalnız biri sağlayıcıya ulaşır", async () => {
    const h = buildService();
    h.ports.credits = 1;

    const results = await Promise.allSettled([
      h.service.run(ctx, payload(reqId("i"))),
      h.service.run(ctx, payload(reqId("j"))),
    ]);

    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(h.gateway.attempts).toBe(1);
    expect(h.ports.credits).toBe(0);
  });

  it("geçersiz/çok büyük payload hiçbir rezervasyon veya sayaç tüketmez", async () => {
    const h = buildService();
    h.ports.content = {
      ...h.ports.content as Record<string, unknown>,
      title: "x".repeat(5000),
    };

    await expect(
      h.service.run(ctx, payload(reqId("k"))),
    ).rejects.toThrow();

    expect(h.daily.slots).toBe(0);
    expect(h.rate.checks).toBe(0);
    expect(h.spend.records).toBe(0);
    expect(h.tokens.records).toBe(0);
    expect(h.ports.journal.size).toBe(0);
  });
});
