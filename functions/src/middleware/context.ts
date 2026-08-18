/**
 * İstek bağlamı kurulumu — boru hattı adım [1-2] (AI-ANALIZ-TASARIMI.md §1.2).
 * App Check doğrulaması runtime seçeneğiyle yapılır (enforceAppCheck: true,
 * consumeAppCheckToken: true) — token'sız/replay istek handler'a hiç ulaşmaz.
 * Burada yalnız auth (anonim dahil) doğrulanır ve bağlam damgalanır.
 */
import { randomUUID } from "node:crypto";

import type { CallableRequest } from "firebase-functions/v2/https";

import { AppError } from "../core/errors.js";
import { hashUid, log } from "../core/logger.js";
import type { RequestContext } from "../core/types.js";

/**
 * Auth bağlamı kurulmadan hata oluştuğunda güvenli hata eşleme/loglama bağlamı.
 * Ham UID yoktur; sabit değerler PII sızıntısını ve AppError'ın `internal`
 * olarak maskelenmesini önler.
 */
export function contextlessLogContext(fn: string): RequestContext {
  return {
    fn,
    jobId: "no-auth",
    uid: "",
    uidHash: "anonymous",
    startedAtMs: Date.now(),
  };
}

export function buildContext(
  fn: string,
  request: CallableRequest,
): RequestContext {
  const uid = request.auth?.uid;
  if (!uid) {
    // Bağlamsız fırlatma: uid yok, hash'lenecek kimlik de yok.
    throw new AppError("unauthenticated", "Oturum gerekli.");
  }
  const ctx: RequestContext = {
    fn,
    jobId: randomUUID(),
    uid,
    uidHash: hashUid(uid),
    startedAtMs: Date.now(),
  };
  log("info", "request_started", ctx, {
    appCheckVerified: request.app != null, // enforceAppCheck garantisi; izleme
    authProvider: request.auth?.token.firebase?.sign_in_provider,
  });
  return ctx;
}
