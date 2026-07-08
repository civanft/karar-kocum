import { describe, expect, it } from "vitest";

import { startTimer } from "../src/core/metrics";

describe("startTimer", () => {
  it("geçen süreyi ms cinsinden ölçer", async () => {
    const stop = startTimer();
    await new Promise((r) => setTimeout(r, 25));
    const elapsed = stop();
    expect(elapsed).toBeGreaterThanOrEqual(20);
    expect(elapsed).toBeLessThan(500);
  });
});
