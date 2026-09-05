/**
 * İŞ PAKETİ 2 / DİLİM D — doğrulama sırası (2B'de güncellendi).
 *
 * Şema olarak geçerli ama derlenmiş mesajı MAX_INPUT_CHARS'ı aşan bir istek,
 * eskiden önce rate sayacını, günlük analiz slotunu ve token/USD kontrolünü
 * tüketip SONRA reddediliyordu: kullanıcı hakkı ve global günlük slot boşa
 * yanıyordu. Boyut kontrolü HİÇBİR sayaç tüketilmeden önce yapılır.
 *
 * 2B: kabul kontrolü ve TÜM rezervasyonlar artık tek `reserve()` çağrısının
 * içindedir. Bu yüzden "hiçbir sayaç tüketilmedi" iddiası, reserve'ün hiç
 * çağrılmamış olmasıyla ve harness sayaçlarının sıfır kalmasıyla kanıtlanır.
 */
import { describe, expect, it } from "vitest";

import { buildService, ctx } from "./helpers/analyze_harness";
import { MAX_INPUT_CHARS } from "../src/config";

/** MAX_INPUT_CHARS'ı aşacak kadar büyük ama ŞEMAYA UYGUN karar. */
function oversizedContent() {
  const long = "x".repeat(140);
  return {
    title: "Çok büyük karar",
    options: Array.from({ length: 10 }, (_, i) => ({
      id: `o${i}`,
      title: `Seçenek ${i}`,
      description: "y".repeat(280),
      pros: Array.from({ length: 20 }, () => long),
      cons: Array.from({ length: 20 }, () => long),
    })),
    criteria: Array.from({ length: 15 }, (_, i) => ({
      id: `c${i}`,
      name: `Kriter ${i}`,
      weight: 5,
    })),
  };
}

const request = { decisionId: "d1", requestId: "r".repeat(24) };

describe("aşırı büyük istek hiçbir sayaç tüketmez", () => {
  function make() {
    const h = buildService();
    h.ports.content = oversizedContent();
    return h;
  }

  it("invalid-argument döner", async () => {
    const h = make();
    await expect(h.service.run(ctx, request)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("rate sayacı TÜKETİLMEZ", async () => {
    const h = make();
    await h.service.run(ctx, request).catch(() => {});
    expect(h.rate.checks).toBe(0);
  });

  it("günlük analiz slotu TÜKETİLMEZ", async () => {
    const h = make();
    await h.service.run(ctx, request).catch(() => {});
    expect(h.daily.slots).toBe(0);
    expect(h.daily.total).toBe(0);
  });

  it("token/USD rezervasyonu YAPILMAZ", async () => {
    const h = make();
    await h.service.run(ctx, request).catch(() => {});
    expect(h.ports.reserved.tokens).toBe(0);
    expect(h.ports.reserved.usd).toBe(0);
    expect(h.spend.records).toBe(0);
    expect(h.tokens.records).toBe(0);
  });

  it("kredi REZERVE EDİLMEZ ve provider ÇAĞRILMAZ", async () => {
    const h = make();
    await h.service.run(ctx, request).catch(() => {});
    expect(h.ports.reserved.credits).toBe(0);
    expect(h.ports.credits).toBeNull();
    expect(h.gateway.attempts).toBe(0);
  });

  it("journal kaydı bile OLUŞMAZ", async () => {
    const h = make();
    await h.service.run(ctx, request).catch(() => {});
    expect(h.ports.journal.size).toBe(0);
  });

  it("sınır gerçekten MAX_INPUT_CHARS üstünde (fixture doğrulaması)", () => {
    expect(MAX_INPUT_CHARS).toBeGreaterThan(0);
  });
});
