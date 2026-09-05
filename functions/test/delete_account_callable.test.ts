/**
 * PR-R1B — deleteAccount callable sözleşmesi.
 *
 * Handler saf fonksiyon olarak test edilir (portlar enjekte edilir);
 * runtime seçenekleri deploy edilen fonksiyonun endpoint metadata'sından
 * okunur — App Check zorunluluğu sessizce düşerse test yakalar.
 */
import type { CallableRequest } from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { describe, expect, it, vi } from "vitest";

import {
  deleteAccount,
  deleteAccountOptions,
  handleDeleteAccount,
} from "../src/privacy/deleteAccount";
import type { AccountDeletionPorts } from "../src/privacy/delete_account_service";

const UID = "gercek-kullanici";
const SAHTE_UID = "saldirgan-hedefi";

function makePorts(overrides: Partial<AccountDeletionPorts> = {}) {
  const seen: string[] = [];
  const ports: AccountDeletionPorts = {
    raiseBarrier: vi.fn(async () => {}),
    drainOpenReservations: vi.fn(async () => ({ open: 0, exhausted: false })),
    recursiveDeleteUser: vi.fn(async (uid: string) => {
      seen.push(uid);
    }),
    deleteDocument: vi.fn(async (path: string) => {
      seen.push(path);
    }),
    userDataRemains: vi.fn(async () => false),
    completeBarrier: vi.fn(async () => {}),
    deleteAuthUser: vi.fn(async (uid: string) => {
      seen.push(uid);
    }),
    ...overrides,
  };
  return { ports, seen };
}

/** Minimum CallableRequest taklidi — yalnız handler'ın okuduğu alanlar. */
function request(options: {
  uid?: string;
  data?: unknown;
}): CallableRequest {
  return {
    data: options.data ?? {},
    auth: options.uid
      ? { uid: options.uid, token: { firebase: {} } }
      : undefined,
    rawRequest: {},
    acceptsStreaming: false,
  } as unknown as CallableRequest;
}

describe("deleteAccount callable", () => {
  it("auth yoksa unauthenticated döner (internal DEĞİL)", async () => {
    const { ports } = makePorts();

    const error = await handleDeleteAccount(request({}), ports).catch(
      (e) => e as HttpsError,
    );

    expect(error).toBeInstanceOf(HttpsError);
    expect(error.code).toBe("unauthenticated");
    expect((error.details as { appCode?: string }).appCode).toBe(
      "unauthenticated",
    );
    // Hiçbir silme adımı çalışmamalı.
    expect(ports.recursiveDeleteUser).not.toHaveBeenCalled();
    expect(ports.deleteAuthUser).not.toHaveBeenCalled();
  });

  it("payload'daki uid YOK SAYILIR; yalnız auth.uid kullanılır", async () => {
    const { ports, seen } = makePorts();

    await handleDeleteAccount(
      request({ uid: UID, data: { uid: SAHTE_UID, userId: SAHTE_UID } }),
      ports,
    );

    expect(seen.every((s) => !s.includes(SAHTE_UID))).toBe(true);
    expect(ports.recursiveDeleteUser).toHaveBeenCalledWith(UID);
    expect(ports.deleteAuthUser).toHaveBeenCalledWith(UID);
  });

  it("ham hata metni istemciye sızmaz", async () => {
    const { ports } = makePorts({
      recursiveDeleteUser: vi.fn(async () => {
        throw new Error("SIZMAMASI GEREKEN upstream detay");
      }),
    });

    const error = await handleDeleteAccount(request({ uid: UID }), ports).catch(
      (e) => e as HttpsError,
    );

    expect(error).toBeInstanceOf(HttpsError);
    expect(error.message).not.toContain("SIZMAMASI");
    expect(error.message).not.toContain(UID);
  });

  it("beklenmedik hata bile HttpsError'a çevrilir (ham Error kaçmaz)", async () => {
    const { ports } = makePorts({
      deleteAuthUser: vi.fn(async () => {
        throw new Error("auth patladı");
      }),
    });

    const error = await handleDeleteAccount(request({ uid: UID }), ports).catch(
      (e) => e as unknown,
    );

    expect(error).toBeInstanceOf(HttpsError);
  });

  it("başarıda { deleted: true } döner", async () => {
    const { ports } = makePorts();
    await expect(
      handleDeleteAccount(request({ uid: UID }), ports),
    ).resolves.toEqual({ deleted: true });
  });

  it("runtime: App Check zorunlu ve token tek kullanımlık", () => {
    // Seçenek nesnesi doğrudan doğrulanır; bu SDK sürümünde App Check
    // bayrakları endpoint metadata'sına yansımıyor.
    expect(deleteAccountOptions.enforceAppCheck).toBe(true);
    expect(deleteAccountOptions.consumeAppCheckToken).toBe(true);
  });

  it("runtime: aynı seçenek nesnesi onCall'a bağlanmış", () => {
    // enforceAppCheck endpoint'te görünmediği için, seçeneklerin GERÇEKTEN
    // bu fonksiyona verildiği görünen alanlarla kanıtlanır.
    const endpoint = (deleteAccount as unknown as { __endpoint: Record<string, unknown> })
      .__endpoint;

    expect(endpoint.availableMemoryMb).toBe(512);
    expect(endpoint.timeoutSeconds).toBe(deleteAccountOptions.timeoutSeconds);
    expect(endpoint.maxInstances).toBe(deleteAccountOptions.maxInstances);
    expect(endpoint.callableTrigger).toBeDefined();
  });
});
