/**
 * SAF tazelik değerlendirmesi (6C4) — ağ, saat ve log YOK.
 *
 * Programın VARLIĞI değil, snapshot'ın BAŞARISI belirleyicidir; bu yüzden
 * karar yalnız yedeklerin kendi metadata'sından çıkarılır. Her belirsizlik
 * fail-closed tarafa düşer: sınıflandırılamayan bir yedek "taze" sayılmaz.
 */
import type { BackupRecord } from "./backup_catalog.js";

const HOUR_MS = 3_600_000;

/** 6B'de gözlenen program sözleşmesi: günlük 7 gün, haftalık 28 gün saklanır. */
export const DAILY_RETENTION_HOURS = 7 * 24;
export const WEEKLY_RETENTION_HOURS = 28 * 24;
/**
 * Saklama süresi sınıflandırma toleransı. Yedek kaynağı kendisini üreten
 * PROGRAMA işaret etmez (API'de böyle bir alan yoktur), bu yüzden ayrım
 * `expireTime - snapshotTime` süresinden yapılır. 7 gün ile 28 gün arasında
 * 21 günlük mesafe olduğundan ±12 saatlik bant iki sınıfı karıştıramaz.
 */
export const RETENTION_TOLERANCE_HOURS = 12;

/** Saat kayması payı: bundan ileri tarihli bir snapshot veri hatasıdır. */
const FUTURE_SKEW_MS = 5 * 60_000;

export type RetentionClass = "daily" | "weekly" | "unknown";

export function classifyRetention(retentionHours: number): RetentionClass {
  if (!Number.isFinite(retentionHours)) return "unknown";
  if (Math.abs(retentionHours - DAILY_RETENTION_HOURS) <= RETENTION_TOLERANCE_HOURS) {
    return "daily";
  }
  if (Math.abs(retentionHours - WEEKLY_RETENTION_HOURS) <= RETENTION_TOLERANCE_HOURS) {
    return "weekly";
  }
  return "unknown";
}

export interface FreshnessCriteria {
  readonly projectId: string;
  readonly location: string;
  readonly databaseId: string;
  readonly thresholdHours: number;
  /** `CREATING` durumunun normal sayıldığı süre. */
  readonly stateGraceHours: number;
  readonly nowMs: number;
}

/** Anormal yedek özeti — YALNIZ düşük kardinaliteli alanlar. */
export interface UnexpectedBackup {
  readonly state: string;
  readonly ageHours: number | null;
}

export type FreshnessReason = "fresh" | "stale" | "no_daily_backup";

export interface FreshnessVerdict {
  readonly fresh: boolean;
  readonly reason: FreshnessReason;
  /** En yeni uygun günlük yedeğin yaşı; aday yoksa `null`. */
  readonly ageHours: number | null;
  readonly thresholdHours: number;
  /** Kapsamdaki (proje/konum/veritabanı eşleşen) yedek sayısı. */
  readonly backupCount: number;
  /** Tazelik adayı olabilen READY günlük yedek sayısı. */
  readonly readyDailyCount: number;
  readonly unexpected: readonly UnexpectedBackup[];
}

/**
 * Düşük kardinalite: RAPORLANAN yaş 0,1 saate yuvarlanır.
 * Karşılaştırmalar HAM yaşla yapılır — yuvarlanmış bir yaşla kıyaslamak
 * 30 saat sınırını ±3 dakika bulanıklaştırır ve sınır testini anlamsız
 * kılardı.
 */
const round1 = (value: number): number => Math.round(value * 10) / 10;

function instantOf(value: string): number | null {
  if (typeof value !== "string" || value.length === 0) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function inScope(backup: BackupRecord, criteria: FreshnessCriteria): boolean {
  return (
    backup.projectId === criteria.projectId &&
    backup.databaseProjectId === criteria.projectId &&
    backup.location === criteria.location &&
    backup.databaseId === criteria.databaseId
  );
}

export function evaluateBackupFreshness(
  backups: readonly BackupRecord[],
  criteria: FreshnessCriteria,
): FreshnessVerdict {
  const scoped = backups.filter((backup) => inScope(backup, criteria));
  const unexpected: UnexpectedBackup[] = [];
  let newestDailyMs: number | null = null;
  let readyDailyCount = 0;

  for (const backup of scoped) {
    const snapshotMs = instantOf(backup.snapshotTime);
    const expireMs = instantOf(backup.expireTime);
    if (snapshotMs === null || expireMs === null) {
      // Ayrıştırılamayan damga: aday DEĞİL ve veri bütünlüğü anomalisi.
      unexpected.push({ state: "INVALID_TIMESTAMP", ageHours: null });
      continue;
    }
    if (snapshotMs > criteria.nowMs + FUTURE_SKEW_MS) {
      unexpected.push({ state: "FUTURE_SNAPSHOT", ageHours: null });
      continue;
    }

    const exactAgeHours = (criteria.nowMs - snapshotMs) / HOUR_MS;
    if (backup.state !== "READY") {
      // `CREATING` yeni bir snapshot için normaldir; SAATLERCE sürmesi
      // değildir. Diğer tüm durumlar (NOT_AVAILABLE, bilinmeyen) anında
      // anormaldir.
      const stillNormal =
        backup.state === "CREATING" && exactAgeHours <= criteria.stateGraceHours;
      if (!stillNormal) {
        unexpected.push({ state: backup.state, ageHours: round1(exactAgeHours) });
      }
      continue;
    }

    if (expireMs <= criteria.nowMs) continue; // süresi dolmuş: aday olamaz
    const retentionHours = (expireMs - snapshotMs) / HOUR_MS;
    if (classifyRetention(retentionHours) !== "daily") continue;

    readyDailyCount += 1;
    if (newestDailyMs === null || snapshotMs > newestDailyMs) {
      newestDailyMs = snapshotMs;
    }
  }

  const base = {
    thresholdHours: criteria.thresholdHours,
    backupCount: scoped.length,
    readyDailyCount,
    unexpected,
  };

  if (newestDailyMs === null) {
    return { fresh: false, reason: "no_daily_backup", ageHours: null, ...base };
  }

  const exactAgeHours = (criteria.nowMs - newestDailyMs) / HOUR_MS;
  const fresh = exactAgeHours <= criteria.thresholdHours;
  return {
    fresh,
    reason: fresh ? "fresh" : "stale",
    ageHours: round1(exactAgeHours),
    ...base,
  };
}
