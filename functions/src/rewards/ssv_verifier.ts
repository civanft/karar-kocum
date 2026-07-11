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
    const signatureIndex = rawQuery.indexOf("&signature=");
    if (signatureIndex < 0) return null;

    const message = rawQuery.slice(0, signatureIndex);
    const params = new URLSearchParams(rawQuery);
    const signature = params.get("signature");
    const keyId = params.get("key_id");
    if (!signature || !keyId) return null;

    const pem = await this.keyProvider(keyId);
    if (!pem) return null;

    const verifier = createVerify("SHA256");
    verifier.update(message);
    const valid = verifier.verify(
      pem,
      Buffer.from(signature, "base64url"),
    );
    if (!valid) return null;

    return {
      userId: params.get("user_id") ?? "",
      customData: params.get("custom_data") ?? "",
      transactionId: params.get("transaction_id") ?? "",
    };
  }
}
