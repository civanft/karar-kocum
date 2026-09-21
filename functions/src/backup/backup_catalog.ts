/**
 * Yedek KATALOĞU portu (6C4) — iş mantığı ile Firestore Backup Admin API
 * arasındaki tek sınır.
 *
 * Modelde KASITLI OLARAK bulunmayanlar: yedek kimliği (UUID), tam kaynak
 * adı, `databaseUid` ve her türlü belge/koleksiyon verisi. Alan yoksa
 * yanlışlıkla loglanamaz; veri minimizasyonu tip düzeyinde garanti edilir.
 */

/** Kontrolün BAŞARISIZ olma biçimleri. Hiçbiri "yedek yok" anlamına gelmez. */
export type BackupErrorType =
  | "auth"
  | "permission"
  | "not_found"
  | "rate_limited"
  | "server"
  | "http"
  | "timeout"
  | "network"
  | "parse"
  | "unreachable"
  | "page_limit"
  | "config"
  | "unknown";

/**
 * Kontrol hatası. Mesaj SABİTTİR: HTTP gövdesi, kaynak adı veya sağlayıcı
 * metni taşınmaz — bunlar loga ve dolayısıyla metriğe sızardı.
 */
export class BackupCheckError extends Error {
  readonly errorType: BackupErrorType;
  readonly httpStatus?: number;

  constructor(errorType: BackupErrorType, httpStatus?: number) {
    super(`backup_check_error:${errorType}`);
    this.name = "BackupCheckError";
    this.errorType = errorType;
    this.httpStatus = httpStatus;
  }
}

/** Hata → `errorType`; tanınmayan istisnalar fail-closed sınıflanır. */
export function backupErrorTypeOf(error: unknown): BackupErrorType {
  return error instanceof BackupCheckError ? error.errorType : "unknown";
}

export function backupHttpStatusOf(error: unknown): number | undefined {
  return error instanceof BackupCheckError ? error.httpStatus : undefined;
}

/**
 * Tek bir yedeğin tazelik kararı için gereken TÜM metadata'sı.
 * Zaman damgaları ham RFC3339 dizeleridir: ayrıştırma saf değerlendirmenin
 * işidir, çünkü BOZUK bir damganın fail-closed davranışı da test edilir.
 */
export interface BackupRecord {
  /** Yedek kaynağının ait olduğu proje (kaynak adından çözülür). */
  readonly projectId: string;
  /** Yedeğin konumu (kaynak adından çözülür), örn. `eur3`. */
  readonly location: string;
  /** Yedeklenen veritabanı kimliği, örn. `(default)`. */
  readonly databaseId: string;
  /** Veritabanı yolundaki proje — kaynak adındakiyle aynı olmalıdır. */
  readonly databaseProjectId: string;
  /** API'nin bildirdiği durum (`READY`, `CREATING`, …). */
  readonly state: string;
  readonly snapshotTime: string;
  readonly expireTime: string;
}

export interface BackupCatalogPort {
  listBackups(): Promise<readonly BackupRecord[]>;
}

/** `fetch` sözleşmesinin kullandığımız EN DAR dilimi (test seam'i). */
export interface FetchResponse {
  readonly ok: boolean;
  readonly status: number;
  json(): Promise<unknown>;
}

export type FetchLike = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    signal?: AbortSignal;
  },
) => Promise<FetchResponse>;
