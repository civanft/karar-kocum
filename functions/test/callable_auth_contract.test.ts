import type { CallableRequest } from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { describe, expect, it } from "vitest";

import { analyzeDecision } from "../src/ai/analyze";
import { createRewardTicket } from "../src/rewards/createRewardTicket";

function unauthenticatedRequest(): CallableRequest {
  return {
    data: {},
    auth: undefined,
    rawRequest: {},
    acceptsStreaming: false,
  } as unknown as CallableRequest;
}

describe("callable auth sözleşmesi", () => {
  it("analyzeDecision auth yoksa internal değil unauthenticated döner", async () => {
    const callable = analyzeDecision as unknown as {
      run(request: CallableRequest): Promise<unknown>;
    };

    const error = await callable
      .run(unauthenticatedRequest())
      .catch((cause) => cause as HttpsError);

    expect(error).toBeInstanceOf(HttpsError);
    expect(error.code).toBe("unauthenticated");
    expect((error.details as { appCode?: string }).appCode).toBe(
      "unauthenticated",
    );
  });

  it("createRewardTicket auth yoksa internal değil unauthenticated döner", async () => {
    const callable = createRewardTicket as unknown as {
      run(request: CallableRequest): Promise<unknown>;
    };

    const error = await callable
      .run(unauthenticatedRequest())
      .catch((cause) => cause as HttpsError);

    expect(error).toBeInstanceOf(HttpsError);
    expect(error.code).toBe("unauthenticated");
    expect((error.details as { appCode?: string }).appCode).toBe(
      "unauthenticated",
    );
  });
});
