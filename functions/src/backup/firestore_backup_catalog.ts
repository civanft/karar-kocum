/**
 * Firestore Backup Admin API istemcisi (6C4) — `backups.list`, SALT OKUNUR.
 *
 * Bu istemci hiçbir belge okumaz: çağrılan tek uç nokta yedek metadata'sıdır.
 * En kritik davranış, BAŞARISIZLIĞIN BOŞ LİSTEYE DÖNÜŞMEMESİDİR — 403 veya
 * zaman aşımı "yedek yok" diye yorumlanırsa alarm sessizce kapanır.
 */
import {
  PROD_BACKUP_LOCATION,
  PROD_PROJECT_ID,
} from "../core/deployment.js";
import {
  BackupCheckError,
  type BackupCatalogPort,
  type BackupRecord,
  type FetchLike,
} from "./backup_catalog.js";

const API_ORIGIN = "https://firestore.googleapis.com";
/** Sayfa döngüsüne karşı sert üst sınır. */
const MAX_PAGES = 10;
const RETRYABLE = new Set(["server", "rate_limited", "timeout", "network"]);
const RETRY_DELAY_MS = 1_000;

const BACKUP_NAME = /^projects\/([^/]+)\/locations\/([^/]+)\/backups\/[^/]+$/;
const DATABASE_PATH = /^projects\/([^/]+)\/databases\/(.+)$/;

export interface AccessTokenProvider {
  getAccessToken(): Promise<string | null | undefined>;
}

export interface FirestoreBackupCatalogDeps {
  readonly projectId: string;
  readonly location: string;
  readonly auth: AccessTokenProvider;
  readonly fetchImpl: FetchLike;
  readonly timeoutMs: number;
  /** Toplam deneme sayısı (yalnız GÜVENLİ GET için, varsayılan 2). */
  readonly maxAttempts?: number;
  readonly delay?: (ms: number) => Promise<void>;
}

/** Hedef proje/konum sözleşmesi — production dışında istek ATILMAZ. */
export function assertBackupTarget(
  projectId: string,
  location: string,
  expectedProjectId: string,
  expectedLocation: string,
): void {
  if (projectId !== expectedProjectId || location !== expectedLocation) {
    throw new BackupCheckError("config");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function errorTypeForStatus(status: number): BackupCheckError {
  if (status === 401) return new BackupCheckError("auth", status);
  if (status === 403) return new BackupCheckError("permission", status);
  if (status === 404) return new BackupCheckError("not_found", status);
  if (status === 429) return new BackupCheckError("rate_limited", status);
  if (status >= 500) return new BackupCheckError("server", status);
  return new BackupCheckError("http", status);
}

/** API gövdesi → model. Beklenmeyen biçim SESSİZCE atlanmaz, parse hatasıdır. */
function toRecord(raw: unknown): BackupRecord {
  if (!isRecord(raw)) throw new BackupCheckError("parse");
  const { name, database, state, snapshotTime, expireTime } = raw;
  if (
    typeof name !== "string" ||
    typeof database !== "string" ||
    typeof state !== "string" ||
    typeof snapshotTime !== "string" ||
    typeof expireTime !== "string"
  ) {
    throw new BackupCheckError("parse");
  }
  const nameParts = BACKUP_NAME.exec(name);
  const databaseParts = DATABASE_PATH.exec(database);
  if (nameParts === null || databaseParts === null) {
    throw new BackupCheckError("parse");
  }
  // Yedek kimliği (son segment) KASITLI olarak modele alınmaz.
  return {
    projectId: nameParts[1] as string,
    location: nameParts[2] as string,
    databaseProjectId: databaseParts[1] as string,
    databaseId: databaseParts[2] as string,
    state,
    snapshotTime,
    expireTime,
  };
}

export class FirestoreBackupCatalog implements BackupCatalogPort {
  private readonly deps: FirestoreBackupCatalogDeps;

  constructor(deps: FirestoreBackupCatalogDeps) {
    this.deps = deps;
  }

  async listBackups(): Promise<readonly BackupRecord[]> {
    const { projectId, location } = this.deps;
    // FAIL-CLOSED: yanlış projede/konumda İSTEK BİLE ATILMAZ. Yanlış hedefe
    // yapılan başarılı bir çağrı, boş yanıtıyla "yedek yok" sanılabilirdi.
    assertBackupTarget(
      projectId,
      location,
      PROD_PROJECT_ID,
      PROD_BACKUP_LOCATION,
    );
    const base =
      `${API_ORIGIN}/v1/projects/${projectId}/locations/${location}/backups`;
    const records: BackupRecord[] = [];
    const seenTokens = new Set<string>();
    let pageToken: string | undefined;

    for (let page = 0; page < MAX_PAGES; page += 1) {
      const url =
        pageToken === undefined
          ? base
          : `${base}?pageToken=${encodeURIComponent(pageToken)}`;
      const body = await this.getJson(url);
      if (!isRecord(body)) throw new BackupCheckError("parse");

      const unreachable = body.unreachable;
      if (Array.isArray(unreachable) && unreachable.length > 0) {
        // Kısmi sonuç: eksik konum "yedek yok" DEĞİLDİR.
        throw new BackupCheckError("unreachable");
      }

      const backups = body.backups;
      if (backups !== undefined) {
        if (!Array.isArray(backups)) throw new BackupCheckError("parse");
        for (const entry of backups) records.push(toRecord(entry));
      }

      const next = body.nextPageToken;
      if (typeof next !== "string" || next.length === 0) return records;
      if (seenTokens.has(next)) throw new BackupCheckError("page_limit");
      seenTokens.add(next);
      pageToken = next;
    }
    throw new BackupCheckError("page_limit");
  }

  /** Tek bir GÜVENLİ GET; yalnız geçici hata sınıflarında tekrar denenir. */
  private async getJson(url: string): Promise<unknown> {
    const attempts = Math.max(1, this.deps.maxAttempts ?? 2);
    const delay =
      this.deps.delay ??
      ((ms: number) => new Promise<void>((done) => setTimeout(done, ms)));

    let lastError: BackupCheckError = new BackupCheckError("unknown");
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        return await this.fetchJson(url);
      } catch (error) {
        if (!(error instanceof BackupCheckError)) throw error;
        lastError = error;
        if (!RETRYABLE.has(error.errorType) || attempt === attempts) break;
        await delay(RETRY_DELAY_MS);
      }
    }
    throw lastError;
  }

  private async fetchJson(url: string): Promise<unknown> {
    const token = await this.deps.auth.getAccessToken();
    if (typeof token !== "string" || token.length === 0) {
      throw new BackupCheckError("auth");
    }

    let response;
    try {
      response = await this.deps.fetchImpl(url, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
          "x-goog-user-project": this.deps.projectId,
        },
        signal: AbortSignal.timeout(this.deps.timeoutMs),
      });
    } catch (error) {
      const name = error instanceof Error ? error.name : "";
      const timedOut = name === "TimeoutError" || name === "AbortError";
      throw new BackupCheckError(timedOut ? "timeout" : "network");
    }

    if (!response.ok) throw errorTypeForStatus(response.status);

    try {
      return await response.json();
    } catch {
      // Gövde metni BİLEREK taşınmaz: hata mesajına sızarsa loga da sızar.
      throw new BackupCheckError("parse");
    }
  }
}
