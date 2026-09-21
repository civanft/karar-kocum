/**
 * `checkBackupFreshness` — saatlik yedek tazelik kontrolü (6C4).
 *
 * Programlı yedeklerin BAŞARISI için native bir Cloud Monitoring sinyali
 * yoktur; bu fonksiyon o boşluğu doldurur. Her çalıştırmada tek bir
 * heartbeat üretir (AL-11 çalışmamayı yakalar) ve sorun varsa ayrı bir
 * problem olayı yazar (AL-10 onu yakalar).
 *
 * Fonksiyon İSTİSNA FIRLATMAZ: hata zaten `backup_check_failed` olarak
 * yapılandırılmış biçimde raporlanır; ayrıca fırlatmak loglara sanitize
 * edilmemiş bir yığın izi eklerdi.
 */
import { randomUUID } from "node:crypto";

import { onSchedule } from "firebase-functions/v2/scheduler";
import { GoogleAuth } from "google-auth-library";

import {
  BACKUP_FRESHNESS_THRESHOLD_HOURS,
  BACKUP_LIST_TIMEOUT_MS,
  BACKUP_STATE_GRACE_HOURS,
} from "../config.js";
import {
  BACKUP_DATABASE_ID,
  backupCheckerRuntimeServiceAccount,
  functionRegion,
  PROD_BACKUP_LOCATION,
} from "../core/deployment.js";
import { log } from "../core/logger.js";
import type { RequestContext } from "../core/types.js";
import {
  backupErrorTypeOf,
  backupHttpStatusOf,
  type BackupCatalogPort,
} from "./backup_catalog.js";
import { FirestoreBackupCatalog } from "./firestore_backup_catalog.js";
import { evaluateBackupFreshness } from "./freshness.js";

/** Yedek metadata'sı için EN DAR OAuth kapsamı. */
const DATASTORE_SCOPE = "https://www.googleapis.com/auth/datastore";

export const checkBackupFreshnessOptions = {
  region: functionRegion,
  serviceAccount: backupCheckerRuntimeServiceAccount,
  schedule: "0 * * * *",
  timeZone: "UTC",
  memory: "256MiB",
  timeoutSeconds: 60,
  // Tek çalıştırma yeter: eşzamanlı kopyalar yalnız mükerrer log üretir.
  maxInstances: 1,
  // Scheduler'ın tekrar denemesi mükerrer heartbeat demektir; bir sonraki
  // saatlik çalıştırma zaten yeni bir ölçüm yapar.
  retryCount: 0,
} as const;

export interface BackupCheckDeps {
  readonly catalog: BackupCatalogPort;
  readonly nowMs: () => number;
  readonly thresholdHours: number;
  readonly stateGraceHours: number;
  readonly projectId: string;
  readonly location: string;
  readonly databaseId: string;
}

type CheckResult = "fresh" | "stale" | "failed";

/**
 * Kontrol gövdesi. Portlar enjekte edilebilir olduğu için ağ ve saat
 * olmadan test edilir.
 */
export async function runBackupFreshnessCheck(
  deps: BackupCheckDeps,
): Promise<void> {
  const ctx: RequestContext = {
    fn: "checkBackupFreshness",
    jobId: randomUUID(),
    // Zamanlanmış çalıştırmanın kullanıcısı yoktur; sabit değer, ham uid
    // sızıntısını yapısal olarak imkânsız kılar.
    uid: "",
    uidHash: "system",
    startedAtMs: deps.nowMs(),
  };

  let checkResult: CheckResult = "failed";
  let heartbeat: Record<string, unknown> = {
    thresholdHours: deps.thresholdHours,
    location: deps.location,
  };

  try {
    const backups = await deps.catalog.listBackups();
    const verdict = evaluateBackupFreshness(backups, {
      projectId: deps.projectId,
      location: deps.location,
      databaseId: deps.databaseId,
      thresholdHours: deps.thresholdHours,
      stateGraceHours: deps.stateGraceHours,
      nowMs: deps.nowMs(),
    });

    checkResult = verdict.fresh ? "fresh" : "stale";
    heartbeat = {
      ageHours: verdict.ageHours,
      thresholdHours: verdict.thresholdHours,
      backupCount: verdict.backupCount,
      readyDailyCount: verdict.readyDailyCount,
      unexpectedCount: verdict.unexpected.length,
      location: deps.location,
      database: deps.databaseId,
    };

    if (!verdict.fresh) {
      log("warn", "backup_freshness_stale", ctx, {
        reason: verdict.reason,
        checkResult,
        ageHours: verdict.ageHours,
        thresholdHours: verdict.thresholdHours,
        backupCount: verdict.backupCount,
        readyDailyCount: verdict.readyDailyCount,
        location: deps.location,
        database: deps.databaseId,
      });
    }

    for (const anomaly of verdict.unexpected) {
      log("warn", "backup_state_unexpected", ctx, {
        state: anomaly.state,
        ageHours: anomaly.ageHours,
        location: deps.location,
        database: deps.databaseId,
      });
    }
  } catch (error) {
    // 403/401/timeout/parse: "yedek yok" DEĞİL, "kontrol edilemedi".
    const errorType = backupErrorTypeOf(error);
    const httpStatus = backupHttpStatusOf(error);
    checkResult = "failed";
    heartbeat = {
      thresholdHours: deps.thresholdHours,
      location: deps.location,
      errorType,
    };
    log("error", "backup_check_failed", ctx, {
      errorType,
      ...(httpStatus === undefined ? {} : { httpStatus }),
      location: deps.location,
      database: deps.databaseId,
    });
  } finally {
    // HER çalıştırmada tam olarak bir heartbeat — AL-11'in dayanağı.
    log("info", "backup_check_heartbeat", ctx, { checkResult, ...heartbeat });
  }
}

/** Production bağlantıları — çalışma zamanında kurulur (global env YOK). */
function productionDeps(): BackupCheckDeps {
  const projectId =
    process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "";
  const auth = new GoogleAuth({ scopes: [DATASTORE_SCOPE] });
  return {
    catalog: new FirestoreBackupCatalog({
      projectId,
      location: PROD_BACKUP_LOCATION,
      auth: { getAccessToken: () => auth.getAccessToken() },
      fetchImpl: (url, init) => fetch(url, init),
      timeoutMs: BACKUP_LIST_TIMEOUT_MS,
    }),
    nowMs: () => Date.now(),
    thresholdHours: BACKUP_FRESHNESS_THRESHOLD_HOURS,
    stateGraceHours: BACKUP_STATE_GRACE_HOURS,
    projectId,
    location: PROD_BACKUP_LOCATION,
    databaseId: BACKUP_DATABASE_ID,
  };
}

export const checkBackupFreshness = onSchedule(
  checkBackupFreshnessOptions,
  async () => {
    await runBackupFreshnessCheck(productionDeps());
  },
);
