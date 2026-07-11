/**
 * Deploy yüzeyi duman testi (PR #6E-3A).
 * index.ts YALNIZ canlıda iş gören fonksiyonları export eder; bu test
 * o yüzeyi sabitler (yanlışlıkla stub eklenirse/aktif fonksiyon düşerse
 * yakalar). Stub kaynak dosyaları hâlâ derlenir ama index'te YOKTUR.
 */
import { describe, expect, it } from "vitest";

import * as api from "../src/index";

describe("deploy yüzeyi (PR #6E-3A)", () => {
  const DEPLOYED = [
    "analyzeDecision",
    "createRewardTicket",
    "admobRewardCallback",
  ];

  it.each(DEPLOYED)("%s export edilmiş ve çağrılabilir", (name) => {
    expect(typeof (api as Record<string, unknown>)[name]).toBe("function");
  });

  it("yalnız 3 fonksiyon deploy edilir (stub'lar hariç)", () => {
    const exported = Object.keys(api).filter(
      (k) => typeof (api as Record<string, unknown>)[k] === "function",
    );
    expect(exported.sort()).toEqual([...DEPLOYED].sort());
  });

  it("stub'lar index'te YOK (Sprint 5/6'ya kadar deploy edilmez)", () => {
    for (const stub of ["revenuecatWebhook", "deleteAccount", "exportData"]) {
      expect((api as Record<string, unknown>)[stub]).toBeUndefined();
    }
  });
});
