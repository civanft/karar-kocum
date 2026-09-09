/**
 * AI işleme izni — SÜRÜMLÜ sözleşme (İş Paketi 5).
 *
 * Kullanıcı içeriği (karar başlığı, seçenekler, kriterler) üçüncü taraf bir
 * sağlayıcıya (OpenAI) aktarılmadan önce AÇIK izin gerekir. İstemcideki kapı
 * atlatılabilir olduğu için karar SUNUCUDA verilir.
 *
 * Sürüm neden var: izin metni maddi olarak değişirse (yeni veri kategorisi,
 * yeni alıcı) eski onay o değişikliği KAPSAMAZ. Sürüm yükseltilir ve
 * kullanıcıdan yeniden izin istenir. Eski kullanıcılar otomatik kabul etmiş
 * SAYILMAZ: kaydı olmayan kullanıcı izinsizdir.
 */
import { AppError } from "../core/errors.js";

/**
 * Geçerli izin metni sürümü.
 *
 * YÜKSELTME KURALI: `hosting/privacy/index.html` içindeki AI aktarım
 * açıklaması ya da uygulamadaki disclosure metni maddi olarak değişirse
 * burayı artır — mevcut tüm onaylar geçersizleşir ve yeniden istenir.
 * Yazım/biçim düzeltmeleri sürümü yükseltmez.
 */
export const AI_CONSENT_VERSION = 1;

/** İzin belgesinin alt koleksiyonu — silme kaskadı bunu tarar. */
export const AI_CONSENT_COLLECTION = "privacy";
export const AI_CONSENT_DOC = "aiConsent";

/** `users/{uid}/` altına eklenen göreli yol. */
export const AI_CONSENT_PATH = `${AI_CONSENT_COLLECTION}/${AI_CONSENT_DOC}`;

/** İzin belgesinin TEK meşru alan kümesi. */
const ALLOWED_FIELDS = new Set(["granted", "version", "updatedAt"]);

/** Kullanıcıya gösterilen SABİT mesaj — upstream metni taşımaz. */
const CONSENT_REQUIRED_MESSAGE =
  "AI analizi için önce yapay zekâ işleme iznini vermen gerekiyor.";

export interface AiConsentRecord {
  granted: boolean;
  version: number;
  updatedAt: unknown;
}

/** Sabit, güvenli hata — çağıran tarafların TEK kaynağı. */
export function aiConsentRequiredError(): AppError {
  return new AppError("ai-consent-required", CONSENT_REQUIRED_MESSAGE);
}

/**
 * Ham belgeyi doğrular. Geçersiz her durum aynı sonuca çıkar: FAIL CLOSED.
 *
 * Beklenmeyen alan reddedilir: ileride eklenen bir alanın eski sunucuda
 * sessizce yok sayılması, izin sözleşmesinin sunucu ve istemcide farklı
 * anlaşılması demekti.
 */
export function isAiConsentValid(raw: unknown): raw is AiConsentRecord {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) return false;
  const record = raw as Record<string, unknown>;

  for (const key of Object.keys(record)) {
    if (!ALLOWED_FIELDS.has(key)) return false;
  }
  if (record.granted !== true) return false;
  if (typeof record.version !== "number" || !Number.isInteger(record.version)) {
    return false;
  }
  // Eski sürüm onayı GEÇERSİZ; ileri sürüm (istemci daha yeni) kabul edilir.
  if (record.version < AI_CONSENT_VERSION) return false;
  if (record.updatedAt == null) return false;
  return true;
}

/**
 * İzin kapısı. Okuma başarısızlığı da dahil HER belirsizlik engeller:
 * "okuyamadım" asla "izin var" anlamına gelmez.
 */
export async function assertAiConsent(
  read: () => Promise<unknown | null>,
): Promise<void> {
  let raw: unknown | null;
  try {
    raw = await read();
  } catch {
    // Ham hata YUTULMAZ ama İSTEMCİYE de geçmez: belge yolu ve UID taşır.
    throw aiConsentRequiredError();
  }
  if (!isAiConsentValid(raw)) throw aiConsentRequiredError();
}
