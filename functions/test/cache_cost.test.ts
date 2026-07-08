import { describe, expect, it } from "vitest";

import { computeInputHash } from "../src/ai/cache";
import { computeCostUsd } from "../src/ai/cost_control";
import { buildUserMessage } from "../src/ai/prompts/analyze_v1";
import { toStoredAnalysis, type DecisionContent } from "../src/ai/schema";

const content: DecisionContent = {
  title: "Telefon seçimi",
  options: [
    { id: "a", title: "iPhone", description: null, pros: ["kamera"], cons: [] },
    { id: "b", title: "Samsung", description: null, pros: [], cons: [] },
  ],
  criteria: [{ id: "c1", name: "Fiyat", weight: 8 }],
};

const base = {
  content,
  tier: "basic" as const,
  promptVersion: "v1",
  model: "gpt-4o-mini",
};

describe("computeInputHash (§5)", () => {
  it("deterministik: aynı girdi aynı hash", () => {
    expect(computeInputHash(base)).toBe(computeInputHash(base));
  });

  it("seçenek SIRASI hash'i değiştirmez (normalizasyon)", () => {
    const reversed = {
      ...base,
      content: { ...content, options: [...content.options].reverse() },
    };
    expect(computeInputHash(reversed)).toBe(computeInputHash(base));
  });

  it("içerik, tier, promptVersion ve model değişimi hash'i değiştirir", () => {
    const h = computeInputHash(base);
    expect(
      computeInputHash({
        ...base,
        content: { ...content, title: "Araba seçimi" },
      }),
    ).not.toBe(h);
    expect(computeInputHash({ ...base, tier: "advanced" })).not.toBe(h);
    expect(computeInputHash({ ...base, promptVersion: "v2" })).not.toBe(h);
    expect(computeInputHash({ ...base, model: "gpt-4o" })).not.toBe(h);
  });
});

describe("computeCostUsd (§6)", () => {
  it("bilinen model fiyat tablosundan hesaplar", () => {
    // 1500 in + 700 out, gpt-4o-mini: 1500/1M*0.15 + 700/1M*0.60
    const cost = computeCostUsd("gpt-4o-mini", {
      inputTokens: 1500,
      outputTokens: 700,
    });
    expect(cost).toBeCloseTo(0.000645, 6);
    // Tasarım hedefi: temel analiz < $0.001
    expect(cost).toBeLessThan(0.001);
  });

  it("bilinmeyen model muhafazakâr fiyata düşer (asla 0 değil)", () => {
    const cost = computeCostUsd("bilinmeyen-model", {
      inputTokens: 1000,
      outputTokens: 1000,
    });
    expect(cost).toBeGreaterThan(0);
  });
});

describe("prompt v1", () => {
  it("kullanıcı verisi <user_data> bloğunda, kriterler dahil", () => {
    const message = buildUserMessage(content);
    expect(message).toContain("<user_data>");
    expect(message).toContain("</user_data>");
    expect(message).toContain("[a] iPhone");
    expect(message).toContain("Fiyat (önem: 8)");
  });
});

describe("toStoredAnalysis", () => {
  it("perOption dizisi optionId anahtarlı map'e çevrilir (§5 şeması)", () => {
    const stored = toStoredAnalysis({
      summary: "s",
      risks: [],
      perOption: [
        { optionId: "a", strengths: ["x"], weaknesses: [] },
        { optionId: "b", strengths: [], weaknesses: ["y"] },
      ],
      suggestedCriteria: [],
      confidence: "high",
      confidenceReason: "r",
    });
    expect(stored.perOption["a"]!.strengths).toEqual(["x"]);
    expect(stored.perOption["b"]!.weaknesses).toEqual(["y"]);
  });
});
