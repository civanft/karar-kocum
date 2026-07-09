import { describe, expect, it } from "vitest";

import { dailySpendLimitUsd } from "../src/ai/config";
import { computeCostUsd } from "../src/ai/cost_control";
import { buildUserMessage } from "../src/ai/prompt";

describe("Gemini maliyet (6C-1 §7)", () => {
  it("analiz başına maliyet hedefi: < $0,001", () => {
    const cost = computeCostUsd("gemini-2.0-flash", {
      inputTokens: 1500,
      outputTokens: 600,
    });
    expect(cost).toBeCloseTo(0.00039, 5);
    expect(cost).toBeLessThan(0.001);
  });

  it("bilinmeyen model muhafazakâr tarifeye düşer (asla 0 değil)", () => {
    expect(
      computeCostUsd("bilinmeyen", { inputTokens: 1000, outputTokens: 1000 }),
    ).toBeGreaterThan(0.001);
  });

  it("günlük tavan varsayılanı $0,35 (MALIYET-AUDIT R1)", () => {
    expect(dailySpendLimitUsd()).toBe(0.35);
  });
});

describe("prompt", () => {
  it("kullanıcı verisi <user_data> bloğunda, kriterler dahil", () => {
    const message = buildUserMessage({
      title: "Telefon seçimi",
      options: [
        { id: "a", title: "iPhone", description: null, pros: [], cons: [] },
        { id: "b", title: "Samsung", description: null, pros: [], cons: [] },
      ],
      criteria: [{ id: "c1", name: "Fiyat", weight: 8 }],
    });
    expect(message).toContain("<user_data>");
    expect(message).toContain("</user_data>");
    expect(message).toContain("[a] iPhone");
    expect(message).toContain("Fiyat (önem: 8)");
  });
});
