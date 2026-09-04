/**
 * İŞ PAKETİ 2 / DİLİM E-2 — içerik parmak izi sözleşmesi.
 */
import { describe, expect, it } from "vitest";

import { contentFingerprint } from "../src/ai/analysis_fingerprint";
import type { DecisionContent } from "../src/ai/schema";

const base: DecisionContent = {
  title: "Telefon",
  options: [
    { id: "a", title: "iPhone", description: null, pros: ["kamera"], cons: [] },
    { id: "b", title: "Samsung", description: "not", pros: [], cons: ["fiyat"] },
  ],
  criteria: [{ id: "c1", name: "Fiyat", weight: 8 }],
};

const fp = (c: DecisionContent, model = "m", promptVersion = "v1") =>
  contentFingerprint({ content: c, model, promptVersion });

describe("contentFingerprint", () => {
  it("deterministik: aynı girdi aynı özet", () => {
    expect(fp(base)).toBe(fp(structuredClone(base)));
  });

  it("başlık değişimi özeti değiştirir", () => {
    expect(fp({ ...base, title: "Telefon 2" })).not.toBe(fp(base));
  });

  it("seçenek artı/eksi değişimi özeti değiştirir", () => {
    const c = structuredClone(base);
    c.options[0]!.pros = ["kamera", "ekran"];
    expect(fp(c)).not.toBe(fp(base));
  });

  it("seçenek SIRASI özeti değiştirir (AI girdisini etkiler)", () => {
    const c = structuredClone(base);
    c.options.reverse();
    expect(fp(c)).not.toBe(fp(base));
  });

  it("kriter ağırlığı özeti değiştirir", () => {
    const c = structuredClone(base);
    c.criteria[0]!.weight = 3;
    expect(fp(c)).not.toBe(fp(base));
  });

  it("model değişimi özeti değiştirir", () => {
    expect(fp(base, "m2")).not.toBe(fp(base));
  });

  it("promptVersion değişimi özeti değiştirir", () => {
    expect(fp(base, "m", "v2")).not.toBe(fp(base));
  });

  it("null ve boş açıklama AYNI kabul edilir (normalize)", () => {
    const c = structuredClone(base);
    c.options[0]!.description = "";
    expect(fp(c)).toBe(fp(base));
  });

  it("özet ham karar metnini TAŞIMAZ", () => {
    const digest = fp(base);
    expect(digest).toMatch(/^[a-f0-9]{64}$/);
    expect(digest).not.toContain("Telefon");
    expect(digest).not.toContain("iPhone");
  });
});
