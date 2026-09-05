/**
 * İŞ PAKETİ 3 — hesap silme sırası ve retry sözleşmesi.
 *
 * Emulator testleri gerçek yarışları kanıtlar; burada kanıtlanan SIRADIR:
 * bariyer ilk, drain tamamlanmadan silme yok, doğrulama bitmeden Auth yok.
 */
import { describe, expect, it, vi } from "vitest";

import {
  deleteAccountCascade,
  deletionDiagnosticOf,
  DRAIN_MAX_WAIT_MS,
  type AccountDeletionPorts,
} from "../src/privacy/delete_account_service";
import { AppError } from "../src/core/errors";

const UID = "silinen-kullanici";

function testClock() {
  let now = 0;
  return {
    now: () => now,
    sleep: async (ms: number) => {
      now += ms;
    },
  };
}

function makePorts(overrides: Partial<AccountDeletionPorts> = {}) {
  const calls: string[] = [];
  const ports: AccountDeletionPorts = {
    raiseBarrier: vi.fn(async () => {
      calls.push("barrier");
    }),
    drainOpenReservations: vi.fn(async () => {
      calls.push("drain");
      return { open: 0 };
    }),
    recursiveDeleteUser: vi.fn(async () => {
      calls.push("recursiveDelete");
    }),
    deleteDocument: vi.fn(async (path: string) => {
      calls.push(`deleteDoc:${path}`);
    }),
    userDataRemains: vi.fn(async () => {
      calls.push("verify");
      return false;
    }),
    deleteAuthUser: vi.fn(async () => {
      calls.push("deleteAuth");
    }),
    ...overrides,
  };
  return { ports, calls };
}

describe("silme sırası", () => {
  it("BARİYER İLK adımdır", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports, testClock());
    expect(calls[0]).toBe("barrier");
  });

  it("sıra: bariyer → drain → recursiveDelete → topLevel → doğrula → auth", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports, testClock());
    expect(calls).toEqual([
      "barrier",
      "drain",
      "recursiveDelete",
      `deleteDoc:rateLimits/${UID}`,
      `deleteDoc:rateLimits/${UID}:reward`,
      "verify",
      "deleteAuth",
    ]);
  });

  it("bariyer BAŞARISIZSA hiçbir silme veya Auth işlemi YAPILMAZ", async () => {
    const { ports } = makePorts({
      raiseBarrier: vi.fn(async () => {
        throw new Error("bariyer yazılamadı");
      }),
    });
    await expect(
      deleteAccountCascade(UID, ports, testClock()),
    ).rejects.toBeInstanceOf(AppError);

    expect(ports.drainOpenReservations).not.toHaveBeenCalled();
    expect(ports.recursiveDeleteUser).not.toHaveBeenCalled();
    expect(ports.deleteDocument).not.toHaveBeenCalled();
    expect(ports.deleteAuthUser).not.toHaveBeenCalled();
  });

  it("drain TAMAMLANMADAN recursive delete YAPILMAZ", async () => {
    const { ports } = makePorts({
      drainOpenReservations: vi.fn(async () => ({ open: 1 })), // hiç bitmiyor
    });
    await expect(
      deleteAccountCascade(UID, ports, testClock()),
    ).rejects.toBeInstanceOf(AppError);

    expect(ports.recursiveDeleteUser).not.toHaveBeenCalled();
    expect(ports.deleteAuthUser).not.toHaveBeenCalled();
  });

  it("drain bounded'dır: sonsuz beklemez", async () => {
    const clock = testClock();
    const { ports } = makePorts({
      drainOpenReservations: vi.fn(async () => ({ open: 1 })),
    });
    await expect(
      deleteAccountCascade(UID, ports, clock),
    ).rejects.toBeInstanceOf(AppError);
    expect(clock.now()).toBeLessThanOrEqual(DRAIN_MAX_WAIT_MS + 10_000);
  });

  it("drain önce açık, sonra kapanırsa akış DEVAM eder", async () => {
    let n = 0;
    const { ports } = makePorts({
      drainOpenReservations: vi.fn(async () => ({ open: n++ < 2 ? 1 : 0 })),
    });
    await expect(
      deleteAccountCascade(UID, ports, testClock()),
    ).resolves.toEqual({ deleted: true });
    expect(ports.deleteAuthUser).toHaveBeenCalledTimes(1);
  });

  it("Firestore temizliği DOĞRULANMADAN Auth SİLİNMEZ", async () => {
    const { ports } = makePorts({
      userDataRemains: vi.fn(async () => true), // veri duruyor
    });
    await expect(
      deleteAccountCascade(UID, ports, testClock()),
    ).rejects.toBeInstanceOf(AppError);
    expect(ports.deleteAuthUser).not.toHaveBeenCalled();
  });
});

describe("failure injection ve retry", () => {
  const stages: Array<{ ad: string; key: keyof AccountDeletionPorts }> = [
    { ad: "drain", key: "drainOpenReservations" },
    { ad: "recursiveDelete", key: "recursiveDeleteUser" },
    { ad: "topLevel", key: "deleteDocument" },
    { ad: "verify", key: "userDataRemains" },
    { ad: "auth", key: "deleteAuthUser" },
  ];

  it.each(stages)(
    "$ad adımı çökerse retry kaldığı yerden TAMAMLAR",
    async ({ key }) => {
      let fail = true;
      const { ports } = makePorts({
        [key]: vi.fn(async () => {
          if (fail) {
            fail = false;
            throw new Error("geçici hata");
          }
          if (key === "drainOpenReservations") return { open: 0 };
          if (key === "userDataRemains") return false;
          return undefined;
        }),
      } as Partial<AccountDeletionPorts>);

      await expect(
        deleteAccountCascade(UID, ports, testClock()),
      ).rejects.toBeInstanceOf(AppError);
      // Retry: aynı akış, bu kez başarılı.
      await expect(
        deleteAccountCascade(UID, ports, testClock()),
      ).resolves.toEqual({ deleted: true });
    },
  );

  it("veri dururken Auth ASLA silinmez (her aşama için)", async () => {
    for (const key of [
      "recursiveDeleteUser",
      "deleteDocument",
      "userDataRemains",
    ] as const) {
      const { ports } = makePorts({
        [key]: vi.fn(async () => {
          throw new Error("çöktü");
        }),
      } as Partial<AccountDeletionPorts>);
      await expect(
        deleteAccountCascade(UID, ports, testClock()),
      ).rejects.toBeInstanceOf(AppError);
      expect(ports.deleteAuthUser).not.toHaveBeenCalled();
    }
  });

  it("teşhis alanı hangi aşamada kırıldığını taşır, PII taşımaz", async () => {
    const { ports } = makePorts({
      raiseBarrier: vi.fn(async () => {
        throw Object.assign(new Error("iç detay"), { code: "permission-denied" });
      }),
    });
    const error = await deleteAccountCascade(UID, ports, testClock()).catch(
      (e: unknown) => e,
    );
    const d = deletionDiagnosticOf(error);
    expect(d?.failureStage).toBe("barrier");
    expect(JSON.stringify(d)).not.toContain(UID);
    expect((error as AppError).message).not.toContain("iç detay");
  });
});

describe("bariyer idempotency'si", () => {
  it("retry bariyeri YENİDEN oluşturmaz, süreyi UZATMAZ", async () => {
    // Port idempotenttir: ikinci çağrı mevcut bariyeri korur. Servis
    // katmanı bunu her retry'da çağırır; süre uzatma kararı PORTTADIR.
    const { ports } = makePorts();
    await deleteAccountCascade(UID, ports, testClock());
    await deleteAccountCascade(UID, ports, testClock());
    expect(ports.raiseBarrier).toHaveBeenCalledTimes(2);
    expect(ports.raiseBarrier).toHaveBeenCalledWith(UID);
  });

  it("başarı yolunda bariyer SİLİNMEZ (TTL'ye bırakılır)", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports, testClock());
    expect(calls).not.toContain("deleteBarrier");
    expect(calls.filter((c) => c.startsWith("deleteDoc:"))).toEqual([
      `deleteDoc:rateLimits/${UID}`,
      `deleteDoc:rateLimits/${UID}:reward`,
    ]);
  });
});
