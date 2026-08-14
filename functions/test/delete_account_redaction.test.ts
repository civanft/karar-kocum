/**
 * PR-R1C — hesap silme teşhis alanlarının REDAKSİYONU.
 *
 * Ham hata metni loglanamaz: Firestore Admin hatalarının message/stack'i
 * belge YOLUNU taşır, yol da UID'i içerir. Log hijyeni (§9.2) ham uid'i
 * yasaklar — bu yüzden teşhis yalnız SABİT ALANLARLA taşınır.
 *
 * Sentinel değerler, üretilen JSON'da hiçbir biçimde görünmemelidir.
 */
import { logger } from "firebase-functions/v2";
import type { CallableRequest } from "firebase-functions/v2/https";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  deletionDiagnosticOf,
  describeCause,
  deleteAccountCascade,
  type AccountDeletionPorts,
} from "../src/privacy/delete_account_service";
import { handleDeleteAccount } from "../src/privacy/deleteAccount";

const SENTINEL_UID = "raw-user-secret-123";
const SENTINEL_PATH = `users/${SENTINEL_UID}/decisions/private`;
const SENTINEL_MESSAGE = "PRIVATE_UPSTREAM_MESSAGE";
const SENTINELS = [SENTINEL_UID, SENTINEL_PATH, SENTINEL_MESSAGE];

/** Gerçek Firestore hatasına benzeyen, üç sentinel'i de taşıyan hata. */
function leakyCause(code: unknown = "permission-denied"): Error {
  const error = new Error(`${SENTINEL_MESSAGE} at ${SENTINEL_PATH}`);
  return Object.assign(error, {
    code,
    path: SENTINEL_PATH,
    documentPath: SENTINEL_PATH,
  });
}

function assertNoSentinels(payload: unknown, label: string): void {
  const json = JSON.stringify(payload) ?? "";
  for (const sentinel of SENTINELS) {
    expect(json, `${label} içinde "${sentinel}" sızmış`).not.toContain(
      sentinel,
    );
  }
}

function request(uid: string): CallableRequest {
  return {
    data: {},
    auth: { uid, token: { firebase: {} } },
    rawRequest: {},
    acceptsStreaming: false,
  } as unknown as CallableRequest;
}

function portsThatFail(
  which: "firestore" | "auth",
  cause: unknown,
): AccountDeletionPorts {
  return {
    recursiveDeleteUser: vi.fn(async () => {
      if (which === "firestore") throw cause;
    }),
    deleteDocument: vi.fn(async () => {}),
    deleteAuthUser: vi.fn(async () => {
      if (which === "auth") throw cause;
    }),
  };
}

afterEach(() => vi.restoreAllMocks());

describe("teşhis alanları — redaksiyon sözleşmesi", () => {
  it("describeCause yalnız güvenli alanlar üretir", () => {
    const diagnostic = describeCause("firestore", leakyCause());

    expect(diagnostic).toEqual({
      failureStage: "firestore",
      causeType: "Error",
      causeCode: "permission-denied",
    });
    assertNoSentinels(diagnostic, "describeCause çıktısı");
  });

  it("güvensiz causeCode 'unknown'a düşer", () => {
    // Kod alanı yol taşıyorsa (ör. yanlış SDK sarmalaması) ASLA geçmemeli.
    expect(describeCause("firestore", leakyCause(SENTINEL_PATH)).causeCode).toBe(
      "unknown",
    );
    expect(describeCause("firestore", leakyCause({ nested: 1 })).causeCode).toBe(
      "unknown",
    );
    // Kod alanı hiç yoksa da güvenli varsayılan.
    expect(
      describeCause("firestore", new Error(SENTINEL_MESSAGE)).causeCode,
    ).toBe("unknown");
    // 64 karakterden uzun kod da reddedilir.
    expect(describeCause("auth", leakyCause("x".repeat(65))).causeCode).toBe(
      "unknown",
    );
  });

  it("güvenli kod biçimleri korunur, izinsiz karakterler reddedilir", () => {
    // İzinli küme: [A-Za-z0-9_.-]
    expect(describeCause("firestore", leakyCause("NOT_FOUND")).causeCode).toBe(
      "NOT_FOUND",
    );
    expect(describeCause("firestore", leakyCause(7)).causeCode).toBe("7");
    // '/' izinli DEĞİL — yol benzeri hiçbir şey geçemesin diye bilinçli dar.
    expect(
      describeCause("auth", leakyCause("auth/user-not-found")).causeCode,
    ).toBe("unknown");
  });

  it("failureStage: Firestore adımı hatası → firestore", async () => {
    const error = await deleteAccountCascade(
      SENTINEL_UID,
      portsThatFail("firestore", leakyCause()),
    ).catch((e) => e as Error);

    const diagnostic = deletionDiagnosticOf(error);
    expect(diagnostic?.failureStage).toBe("firestore");
    assertNoSentinels(diagnostic, "firestore teşhisi");
  });

  it("failureStage: Auth adımı hatası → auth", async () => {
    const error = await deleteAccountCascade(
      SENTINEL_UID,
      portsThatFail("auth", leakyCause()),
    ).catch((e) => e as Error);

    const diagnostic = deletionDiagnosticOf(error);
    expect(diagnostic?.failureStage).toBe("auth");
    assertNoSentinels(diagnostic, "auth teşhisi");
  });

  it("fırlatılan hataya HAM cause İLİŞTİRİLMEZ", async () => {
    const error = (await deleteAccountCascade(
      SENTINEL_UID,
      portsThatFail("firestore", leakyCause()),
    ).catch((e) => e)) as Error;

    expect(error.cause).toBeUndefined();
    assertNoSentinels({ message: error.message }, "AppError mesajı");
  });

  it("handler'ın YAZDIĞI hiçbir log satırında sentinel yok", async () => {
    const written: unknown[] = [];
    for (const level of ["debug", "info", "warn", "error"] as const) {
      vi.spyOn(logger, level).mockImplementation((...args: unknown[]) => {
        written.push(args);
      });
    }

    await handleDeleteAccount(
      request(SENTINEL_UID),
      portsThatFail("firestore", leakyCause()),
    ).catch(() => undefined);

    expect(written.length).toBeGreaterThan(0);
    assertNoSentinels(written, "handler log çıktısı");
  });

  it("handler log'u güvenli teşhis alanlarını GERÇEKTEN taşır", async () => {
    const written: Record<string, unknown>[] = [];
    vi.spyOn(logger, "error").mockImplementation(
      (_event: unknown, payload?: unknown) => {
        written.push(payload as Record<string, unknown>);
      },
    );

    await handleDeleteAccount(
      request(SENTINEL_UID),
      portsThatFail("auth", leakyCause("NOT_FOUND")),
    ).catch(() => undefined);

    const diagnostic = written.find((p) => p?.failureStage !== undefined);
    expect(diagnostic).toMatchObject({
      failureStage: "auth",
      causeType: "Error",
      causeCode: "NOT_FOUND",
    });
  });

  it("istemciye giden details'e ham cause KONMAZ", async () => {
    const thrown = (await handleDeleteAccount(
      request(SENTINEL_UID),
      portsThatFail("firestore", leakyCause()),
    ).catch((e) => e)) as { message: string; details?: unknown };

    assertNoSentinels(thrown.details, "HttpsError details");
    assertNoSentinels({ message: thrown.message }, "HttpsError mesajı");
  });
});
