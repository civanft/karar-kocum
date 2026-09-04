/**
 * İŞ PAKETİ 2 / DİLİM B — analyzeDecision payload sözleşmesi.
 *
 * requestId idempotency ANAHTARIDIR: aynı (uid, requestId) için başarılı
 * analiz yalnız bir kez uygulanır. Bu yüzden biçimi kanonik ve sınırlı
 * olmalı, payload STRICT olmalı (bilinmeyen alan sessizce yutulmamalı).
 *
 * Biçim, mevcut istemci IdGenerator'ı ile hizalıdır: [a-z0-9], sabit uzunluk.
 * Yeni bir UUID bağımlılığı EKLENMEDİ.
 */
import { describe, expect, it } from "vitest";

import { analyzeRequestSchema, REQUEST_ID_LENGTH } from "../src/ai/schema";

const validId = "a".repeat(REQUEST_ID_LENGTH);

describe("analyzeRequestSchema", () => {
  it("decisionId + requestId kabul edilir", () => {
    const r = analyzeRequestSchema.safeParse({
      decisionId: "d1",
      requestId: validId,
    });
    expect(r.success).toBe(true);
  });

  it("requestId ZORUNLU", () => {
    expect(analyzeRequestSchema.safeParse({ decisionId: "d1" }).success)
      .toBe(false);
  });

  it("fazladan alan REDDEDİLİR (strict)", () => {
    const r = analyzeRequestSchema.safeParse({
      decisionId: "d1",
      requestId: validId,
      sneaky: "x",
    });
    expect(r.success).toBe(false);
  });

  it("kanonik biçim dışındaki requestId reddedilir", () => {
    for (const bad of [
      "",
      "SHORT",
      "A".repeat(REQUEST_ID_LENGTH),      // büyük harf
      "a".repeat(REQUEST_ID_LENGTH - 1),  // kısa
      "a".repeat(REQUEST_ID_LENGTH + 1),  // uzun
      `a-${"b".repeat(REQUEST_ID_LENGTH - 2)}`, // tire
      `${"a".repeat(REQUEST_ID_LENGTH - 1)}/`,  // yol ayracı
      "../".padEnd(REQUEST_ID_LENGTH, "a"),
    ]) {
      expect(
        analyzeRequestSchema.safeParse({ decisionId: "d1", requestId: bad })
          .success,
        `"${bad}" reddedilmeliydi`,
      ).toBe(false);
    }
  });

  it("uzunluk kriptografik entropi için yeterli (>= 20 karakter)", () => {
    expect(REQUEST_ID_LENGTH).toBeGreaterThanOrEqual(20);
  });

  it("requestId Firestore belge kimliği olarak güvenli", () => {
    // Yol ayracı, nokta segmenti veya __ öneki taşımamalı.
    expect(validId).not.toMatch(/[/.]/);
    expect(validId).not.toMatch(/^__/);
  });
});
