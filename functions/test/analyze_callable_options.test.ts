/**
 * 6B0 — `analyzeDecision` App Check SÖZLEŞMESİ (regresyon kapısı).
 *
 * Bu test bir kapsam boşluğunu kapatır: `enforceAppCheck: true` satırı
 * `analyzeDecision`'dan silindiğinde 335 birim testinin TAMAMI geçiyordu.
 * `deleteAccount` aynı sözleşmeyi zaten koruyordu; analiz yüzeyi — kullanıcı
 * içeriğini üçüncü taraf bir sağlayıcıya taşıyan fonksiyon — korumasızdı.
 *
 * NEDEN SEÇENEK NESNESİ: firebase-functions 7.x'te App Check bayrakları
 * `__endpoint` metadata'sına yansımaz (`callableTrigger` boş nesnedir).
 * Deploy edilen sözleşmenin denetlenebilir tek yüzeyi, `onCall`'a verilen
 * seçenek nesnesidir; bu yüzden nesne dışa verilir ve burada doğrulanır.
 * Nesnenin GERÇEKTEN bu fonksiyona bağlandığı, endpoint'te görünen
 * alanlarla ayrıca kanıtlanır.
 */
import { describe, expect, it } from "vitest";

import { analyzeDecision, analyzeDecisionOptions } from "../src/ai/analyze";
import {
  analyzeRuntimeServiceAccount,
  functionRegion,
} from "../src/core/deployment";

type Endpoint = Record<string, unknown>;

const endpoint = (): Endpoint =>
  (analyzeDecision as unknown as { __endpoint: Endpoint }).__endpoint;

describe("analyzeDecision App Check sözleşmesi", () => {
  it("enforceAppCheck AÇIKÇA true", () => {
    // `toBeTruthy` yetmez: seçenek 1 ya da "true" olsaydı da geçerdi.
    expect(analyzeDecisionOptions.enforceAppCheck).toBe(true);
  });

  it("consumeAppCheckToken AÇIKÇA true", () => {
    expect(analyzeDecisionOptions.consumeAppCheckToken).toBe(true);
  });

  it("her iki bayrak da TANIMLI (sessizce düşmemiş)", () => {
    const options = analyzeDecisionOptions as Record<string, unknown>;
    for (const flag of ["enforceAppCheck", "consumeAppCheckToken"]) {
      expect(
        Object.prototype.hasOwnProperty.call(options, flag),
        `${flag} seçenek nesnesinden kaldırılmış`,
      ).toBe(true);
      expect(options[flag]).not.toBeUndefined();
    }
  });

  it("deleteAccount ile AYNI App Check duruşu", async () => {
    const { deleteAccountOptions } = await import("../src/privacy/deleteAccount");
    expect(analyzeDecisionOptions.enforceAppCheck).toBe(
      deleteAccountOptions.enforceAppCheck,
    );
    expect(analyzeDecisionOptions.consumeAppCheckToken).toBe(
      deleteAccountOptions.consumeAppCheckToken,
    );
  });

  it("seçenek nesnesi GERÇEKTEN deploy edilen callable'a bağlı", () => {
    // App Check bayrakları endpoint'te görünmediği için bağlılık, görünen
    // alanların seçenek nesnesiyle birebir eşleşmesiyle kanıtlanır.
    const ep = endpoint();
    expect(ep.callableTrigger).toBeDefined();
    expect(ep.availableMemoryMb).toBe(512);
    expect(ep.timeoutSeconds).toBe(analyzeDecisionOptions.timeoutSeconds);
    expect(ep.concurrency).toBe(analyzeDecisionOptions.concurrency);
    expect(ep.maxInstances).toBe(analyzeDecisionOptions.maxInstances);
    expect(ep.serviceAccountEmail).toBe(analyzeRuntimeServiceAccount);
    expect(Array.isArray(ep.region) ? (ep.region as unknown[])[0] : ep.region)
      .toBe(functionRegion);
    expect(ep.secretEnvironmentVariables).toEqual([{ key: "OPENAI_API_KEY" }]);
  });
});
