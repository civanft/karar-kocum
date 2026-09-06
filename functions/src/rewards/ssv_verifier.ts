/**
 * AdMob SSV (Server-Side Verification) imza doğrulayıcı — PR #7A.
 *
 * AdMob, ödül callback'ini ECDSA-SHA256 ile imzalar:
 *   mesaj  = query string'in '&signature=' öncesindeki kısmı (geldiği sırayla)
 *   imza   = base64url DER, 'signature' parametresi
 *   anahtar= key_id ile https://gstatic.com/admob/reward/verifier-keys.json
 *
 * İMZA DOĞRULANMADAN HİÇBİR ÖDÜL VERİLMEZ — "reklam tamamlanmadan kredi
 * yok" kuralının sunucu tarafı temeli.
 */
import { createVerify } from "node:crypto";

export const ADMOB_KEYS_URL =
  "https://www.gstatic.com/admob/reward/verifier-keys.json";

export interface SsvPayload {
  userId: string;
  /** custom_data — bizde rewardTicketId taşır. */
  customData: string;
  transactionId: string;
}

export type KeyProvider = (keyId: string) => Promise<string | null>; // PEM

/** Üretim anahtar sağlayıcısı — 1 saat önbellekli gstatic fetch'i. */
export function createGstaticKeyProvider(
  fetchImpl: typeof fetch = fetch,
  now: () => number = Date.now,
): KeyProvider {
  let cache: { keys: Map<string, string>; expiresAtMs: number } | null = null;

  return async (keyId) => {
    if (!cache || cache.expiresAtMs < now()) {
      const response = await fetchImpl(ADMOB_KEYS_URL);
      const body = (await response.json()) as {
        keys: Array<{ keyId: number; pem: string }>;
      };
      cache = {
        keys: new Map(body.keys.map((k) => [String(k.keyId), k.pem])),
        expiresAtMs: now() + 3_600_000,
      };
    }
    return cache.keys.get(keyId) ?? null;
  };
}

export class SsvVerifier {
  constructor(private readonly keyProvider: KeyProvider) {}

  /**
   * Ham query string'i doğrular; imza geçersizse null döner.
   * (Örn. "ad_network=..&custom_data=t1&user_id=u1&signature=..&key_id=1")
   */
  async verify(rawQuery: string): Promise<SsvPayload | null> {
    if (rawQuery.length > 8192) return null;
    const signatureIndex = rawQuery.indexOf("&signature=");
    if (signatureIndex < 0) return null;

    const message = rawQuery.slice(0, signatureIndex);
    // Only the prefix is signed. Never read reward/identity fields from
    // the unsigned suffix: a valid signature must not authenticate appended
    // user_id/custom_data/transaction_id parameters.
    const params = new URLSearchParams(message);
    const trailer = new URLSearchParams(rawQuery.slice(signatureIndex + 1));
    const trailerKeys = [...trailer.keys()];
    if (trailerKeys.length !== 2 ||
        trailer.getAll("signature").length !== 1 ||
        trailer.getAll("key_id").length !== 1) return null;
    const signature = trailer.get("signature");
    const keyId = trailer.get("key_id");
    if (!signature || !/^[A-Za-z0-9_-]{1,256}={0,2}$/.test(signature) ||
        !keyId || !/^\d{1,20}$/.test(keyId)) return null;
    if (params.has("signature") || params.has("key_id")) return null;
    const required = ["user_id", "custom_data", "transaction_id"];
    for (const field of required) {
      const values = params.getAll(field);
      if (values.length !== 1 || !values[0]?.trim() ||
          values[0].length > 256 || values[0].includes("/") ||
          [...values[0]].some((char) => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127) ||
          values[0] === "." || values[0] === "..") return null;
    }

    const pem = await this.keyProvider(keyId);
    if (!pem) return null;

    try {
      const verifier = createVerify("SHA256");
      verifier.update(message);
      if (!verifier.verify(pem, Buffer.from(signature, "base64url"))) return null;
    } catch {
      return null;
    }

    return {
      userId: params.get("user_id") ?? "",
      customData: params.get("custom_data") ?? "",
      transactionId: params.get("transaction_id") ?? "",
    };
  }
}
