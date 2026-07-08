/**
 * Duman testi: fonksiyon envanterindeki her stub tanımlı ve export edilmiş mi?
 * (index.ts initializeApp çağırdığı için modüller tek tek import edilir.)
 * Sprint 2'de her fonksiyonun gerçek davranış testleri bu dosyanın yerini alır.
 */
import { describe, expect, it } from "vitest";

import { analyzeDecision } from "../src/ai/analyze";
import { scoreOptions } from "../src/ai/scoreOptions";
import { suggestCriteria } from "../src/ai/suggestCriteria";
import { revenuecatWebhook } from "../src/billing/revenuecatWebhook";
import { deleteAccount } from "../src/privacy/deleteAccount";
import { exportData } from "../src/privacy/exportData";

describe("fonksiyon envanteri (TEKNIK-MIMARI.md §5.1)", () => {
  it.each([
    ["analyzeDecision", analyzeDecision],
    ["suggestCriteria", suggestCriteria],
    ["scoreOptions", scoreOptions],
    ["revenuecatWebhook", revenuecatWebhook],
    ["deleteAccount", deleteAccount],
    ["exportData", exportData],
  ])("%s export edilmiş ve çağrılabilir yapıda", (_name, fn) => {
    expect(fn).toBeDefined();
    expect(typeof fn).toBe("function");
  });
});
