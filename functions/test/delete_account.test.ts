/**
 * PR-R1 — hesap silme kaskadı (KVKK / Store P0).
 *
 * Orkestrasyon Admin SDK global'lerinden AYRIK test edilir: servis yalnız
 * port arayüzlerini bilir (recursiveDelete / deleteDoc / deleteAuthUser).
 * Böylece "Firestore önce, Auth sonra", idempotency ve yol izolasyonu
 * gerçek Firebase olmadan kanıtlanır.
 */
import { describe, expect, it, vi } from "vitest";

import { AppError } from "../src/core/errors";
import {
  deleteAccountCascade,
  type AccountDeletionPorts,
} from "../src/privacy/delete_account_service";

const UID = "user-123";
const OTHER = "baska-kullanici";

/** Çağrı sırasını da kaydeden sahte portlar. */
function makePorts(overrides: Partial<AccountDeletionPorts> = {}) {
  const calls: string[] = [];
  const ports: AccountDeletionPorts = {
    recursiveDeleteUser: vi.fn(async (uid: string) => {
      calls.push(`recursiveDelete:${uid}`);
    }),
    deleteDocument: vi.fn(async (path: string) => {
      calls.push(`deleteDoc:${path}`);
    }),
    deleteAuthUser: vi.fn(async (uid: string) => {
      calls.push(`deleteAuth:${uid}`);
    }),
    ...overrides,
  };
  return { ports, calls };
}

describe("deleteAccountCascade", () => {
  it("1-2) yalnız verilen uid kullanılır; payload uid'i akışa giremez", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports);
    // Tüm yollar UID'den türetilir:
    expect(calls.every((c) => !c.includes(OTHER))).toBe(true);
    expect(ports.recursiveDeleteUser).toHaveBeenCalledWith(UID);
    expect(ports.recursiveDeleteUser).toHaveBeenCalledTimes(1);
  });

  it("3-5) users/{uid} recursive silinir (decisions/aiAnalyses/rewardTickets/subscriptions dahil)", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports);
    expect(calls).toContain(`recursiveDelete:${UID}`);
    // Alt koleksiyonlar için AYRI çağrı YOK — recursiveDelete kapsar:
    expect(calls.filter((c) => c.startsWith("recursiveDelete:"))).toHaveLength(1);
  });

  it("6-7) rateLimits/{uid} VE rateLimits/{uid}:reward silinir", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports);
    expect(calls).toContain(`deleteDoc:rateLimits/${UID}`);
    expect(calls).toContain(`deleteDoc:rateLimits/${UID}:reward`);
  });

  it("8) başka kullanıcının yolu hiç oluşturulmaz", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports);
    for (const c of calls) expect(c).not.toContain(OTHER);
  });

  it("9) ops/* belgelerine dokunulmaz", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports);
    expect(calls.some((c) => c.includes("ops/"))).toBe(false);
  });

  it("10) Firestore adımları Auth silmeden ÖNCE tamamlanır", async () => {
    const { ports, calls } = makePorts();
    await deleteAccountCascade(UID, ports);
    const authIndex = calls.findIndex((c) => c.startsWith("deleteAuth:"));
    const firestoreIndexes = calls
      .map((c, i) => (c.startsWith("deleteAuth:") ? -1 : i))
      .filter((i) => i >= 0);
    expect(authIndex).toBeGreaterThan(Math.max(...firestoreIndexes));
  });

  it("11) Firestore hata verirse Auth SİLİNMEZ", async () => {
    const { ports } = makePorts({
      recursiveDeleteUser: vi.fn(async () => {
        throw new Error("firestore patladı");
      }),
    });
    await expect(deleteAccountCascade(UID, ports)).rejects.toBeInstanceOf(
      AppError,
    );
    expect(ports.deleteAuthUser).not.toHaveBeenCalled();
  });

  it("12) auth/user-not-found BAŞARI kabul edilir", async () => {
    const notFound = Object.assign(new Error("no user"), {
      code: "auth/user-not-found",
    });
    const { ports } = makePorts({
      deleteAuthUser: vi.fn(async () => {
        throw notFound;
      }),
    });
    await expect(deleteAccountCascade(UID, ports)).resolves.toEqual({
      deleted: true,
    });
  });

  it("13) ikinci çalıştırma idempotenttir (boş ağaç + olmayan belgeler)", async () => {
    const { ports } = makePorts();
    await deleteAccountCascade(UID, ports);
    await expect(deleteAccountCascade(UID, ports)).resolves.toEqual({
      deleted: true,
    });
    expect(ports.recursiveDeleteUser).toHaveBeenCalledTimes(2);
  });

  it("14) beklenmedik Auth hatası güvenli internal AppError'a çevrilir", async () => {
    const { ports } = makePorts({
      deleteAuthUser: vi.fn(async () => {
        throw new Error("upstream detay SIZMAMALI");
      }),
    });
    const err = await deleteAccountCascade(UID, ports).catch((e) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).code).toBe("internal");
    expect((err as AppError).message).not.toContain("upstream detay");
  });

  it("15) ham UID hata mesajına sızmaz", async () => {
    const { ports } = makePorts({
      recursiveDeleteUser: vi.fn(async () => {
        throw new Error("bir şey oldu");
      }),
    });
    const err = (await deleteAccountCascade(UID, ports).catch(
      (e) => e,
    )) as AppError;
    expect(err.message).not.toContain(UID);
  });

  it("16) hata nedeni cause olarak KORUNUR (üretimde teşhis için)", async () => {
    const cause = new Error("firestore quota");
    const { ports } = makePorts({
      recursiveDeleteUser: vi.fn(async () => {
        throw cause;
      }),
    });

    const err = (await deleteAccountCascade(UID, ports).catch(
      (e) => e,
    )) as AppError;

    // İstemciye giden mesaj güvenli kalır; neden yalnız cause'ta durur.
    expect(err.message).not.toContain("quota");
    expect((err as Error).cause).toBe(cause);
  });

  it("başarılı akış { deleted: true } döner", async () => {
    const { ports } = makePorts();
    await expect(deleteAccountCascade(UID, ports)).resolves.toEqual({
      deleted: true,
    });
  });
});
