/**
 * OpenAI SDK hata sınıflandırması (İş Paketi 2).
 *
 * NEDEN AYRI DOSYA: eski sınıflandırıcı "status alanı yoksa ağ hatasıdır"
 * varsayıyordu. openai 6.49.0'da `LengthFinishReasonError` ve
 * `ContentFilterFinishReasonError` `OpenAIError`'dan türer, `APIError`
 * DEĞİLDİR ve `status` TAŞIMAZ — yani moderasyon ve kesilmiş çıktı hataları
 * "ağ hatası" sanılıp yeniden deneniyordu: ikinci bir ÜCRETLİ provider
 * çağrısı ve kullanıcıya yanlış hata.
 *
 * Resmî retry kümesi (SDK README §Retries): connection hatası, 408, 409,
 * 429 ve >= 500. Sınıflandırma bu kümeye dayanır; `status` yokluğuna değil.
 */
import {
  APIConnectionError,
  APIError,
  ContentFilterFinishReasonError,
  LengthFinishReasonError,
} from "openai/core/error";

export enum ProviderErrorKind {
  /** Çıktı güvenlik filtresine takıldı (finish_reason: content_filter). */
  moderated = "moderated",
  /** Model açıkça reddetti (message.refusal). */
  refused = "refused",
  /** Token bütçesi bitti, yapılandırılmış çıktı tamamlanmadı. */
  outputTruncated = "outputTruncated",
  /** Yanıt şemaya ayrıştırılamadı. */
  schemaFailure = "schemaFailure",
  rateLimited = "rateLimited",
  serverError = "serverError",
  transport = "transport",
  /** Kalıcı istek hatası (400/401/403/404/422 …). */
  permanentRequest = "permanentRequest",
  /** Sınıflandırılamayan — programlama hatası olabilir; ASLA retry edilmez. */
  unknown = "unknown",
}

export interface ProviderErrorClass {
  kind: ProviderErrorKind;
  retryable: boolean;
  /** Yalnız biçim denetimli teşhis; ham mesaj/secret TAŞIMAZ. */
  status?: number;
}

/** SDK'nın resmî olarak yeniden denediği HTTP durumları. */
function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 409 || status === 429 || status >= 500;
}

/**
 * Gateway'in kendi ürettiği yapısal işaretler. Bunlar SDK hatası değildir;
 * ayrıştırma sonucundan türetilir ve ASLA yeniden denenmez.
 */
function structuralKind(error: unknown): ProviderErrorKind | undefined {
  if (typeof error !== "object" || error === null) return undefined;
  if ("__refusal" in error) return ProviderErrorKind.refused;
  if ("__schemaFailure" in error) return ProviderErrorKind.schemaFailure;
  return undefined;
}

export function classifyProviderError(error: unknown): ProviderErrorClass {
  // 1) finish-reason sınıfları: status TAŞIMAZLAR, önce bunlar denetlenir.
  if (error instanceof ContentFilterFinishReasonError) {
    return { kind: ProviderErrorKind.moderated, retryable: false };
  }
  if (error instanceof LengthFinishReasonError) {
    return { kind: ProviderErrorKind.outputTruncated, retryable: false };
  }

  // 2) Gateway'in kendi yapısal işaretleri.
  const structural = structuralKind(error);
  if (structural) return { kind: structural, retryable: false };

  // 3) Bağlantı/timeout: APIError alt sınıfı ama status'suz.
  if (error instanceof APIConnectionError) {
    return { kind: ProviderErrorKind.transport, retryable: true };
  }

  // 4) HTTP durumu olan API hataları.
  if (error instanceof APIError) {
    const status = typeof error.status === "number" ? error.status : undefined;
    if (status === undefined) {
      // APIError ama status yok → taşıma katmanı sorunu.
      return { kind: ProviderErrorKind.transport, retryable: true };
    }
    if (status === 429) {
      return { kind: ProviderErrorKind.rateLimited, retryable: true, status };
    }
    if (status >= 500) {
      return { kind: ProviderErrorKind.serverError, retryable: true, status };
    }
    if (isRetryableStatus(status)) {
      return { kind: ProviderErrorKind.transport, retryable: true, status };
    }
    return { kind: ProviderErrorKind.permanentRequest, retryable: false, status };
  }

  // 5) SDK sınıfı olmayan ama SAYISAL status taşıyan hata (proxy/sarmalayıcı).
  //    status'un VARLIĞI sınıflandırır; YOKLUĞU asla "ağ hatası" demek değildir.
  if (typeof error === "object" && error !== null && "status" in error) {
    const raw = (error as { status: unknown }).status;
    const status = typeof raw === "number" ? raw : Number(raw);
    if (Number.isFinite(status)) {
      if (status === 429) {
        return { kind: ProviderErrorKind.rateLimited, retryable: true, status };
      }
      if (status >= 500) {
        return { kind: ProviderErrorKind.serverError, retryable: true, status };
      }
      if (isRetryableStatus(status)) {
        return { kind: ProviderErrorKind.transport, retryable: true, status };
      }
      return {
        kind: ProviderErrorKind.permanentRequest,
        retryable: false,
        status,
      };
    }
  }

  // 6) TypeError gibi programlama hataları ağ hatası SAYILMAZ.
  return { kind: ProviderErrorKind.unknown, retryable: false };
}
