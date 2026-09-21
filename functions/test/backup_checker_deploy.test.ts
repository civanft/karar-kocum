/**
 * 6C4 — checker'ın DEPLOY SÖZLEŞMESİ.
 *
 * Bu dosya canlı rollout'un iki tehlikesini repoda sabitler:
 *   1. Checker'a gereksiz yetki/secret bağlanması,
 *   2. Hedefli deploy'un mevcut callable'ları da yeniden deploy etmesi.
 * İkincisi production'da çalışan analiz ve hesap silme yüzeyini, bu turun
 * kapsamı dışında olmasına rağmen yeni bir revizyona taşırdı.
 */
import { describe, expect, it } from "vitest";

import { BACKUP_FRESHNESS_THRESHOLD_HOURS } from "../src/config";
import {
  BACKUP_CHECKER_DEPLOY_TARGET,
  BACKUP_DATABASE_ID,
  backupCheckerRuntimeServiceAccount,
  functionRegion,
  PROD_BACKUP_CHECKER_RUNTIME_SERVICE_ACCOUNT,
  PROD_BACKUP_LOCATION,
  PROD_PROJECT_ID,
} from "../src/core/deployment";
import { checkBackupFreshnessOptions } from "../src/backup/check_backup_freshness";
import * as api from "../src/index";

type Endpoint = {
  region?: unknown;
  serviceAccountEmail?: unknown;
  secretEnvironmentVariables?: unknown;
  scheduleTrigger?: { schedule?: unknown; timeZone?: unknown };
  maxInstances?: unknown;
};

const endpointOf = (name: string): Endpoint => {
  const fn = (api as Record<string, unknown>)[name] as {
    __endpoint?: Endpoint;
  };
  expect(fn?.__endpoint).toBeDefined();
  return fn.__endpoint as Endpoint;
};

describe("checker deploy yüzeyi", () => {
  it("checkBackupFreshness export edilmiş", () => {
    expect(typeof (api as Record<string, unknown>).checkBackupFreshness).toBe(
      "function",
    );
  });

  it("mevcut callable'lar yüzeyde korunur (düşmemiş)", () => {
    for (const name of [
      "analyzeDecision",
      "createRewardTicket",
      "admobRewardCallback",
      "deleteAccount",
    ]) {
      expect(typeof (api as Record<string, unknown>)[name]).toBe("function");
    }
  });

  it("checker mevcut callable'larla AYNI bölge ifadesini kullanır", () => {
    const region = endpointOf("checkBackupFreshness").region;
    expect(Array.isArray(region) ? region[0] : region).toBe(functionRegion);
  });

  it("saatlik UTC zamanlama", () => {
    const trigger = endpointOf("checkBackupFreshness").scheduleTrigger;
    expect(trigger).toBeDefined();
    expect(checkBackupFreshnessOptions.schedule).toBe("0 * * * *");
    expect(checkBackupFreshnessOptions.timeZone).toBe("UTC");
  });

  it("tek instance, küçük bellek, makul timeout, retry yok", () => {
    expect(checkBackupFreshnessOptions.maxInstances).toBe(1);
    expect(checkBackupFreshnessOptions.memory).toBe("256MiB");
    expect(checkBackupFreshnessOptions.timeoutSeconds).toBeLessThanOrEqual(120);
    expect(checkBackupFreshnessOptions.retryCount).toBe(0);
  });

  it("ADANMIŞ runtime service account kullanır", () => {
    expect(endpointOf("checkBackupFreshness").serviceAccountEmail).toBe(
      backupCheckerRuntimeServiceAccount,
    );
    expect(PROD_BACKUP_CHECKER_RUNTIME_SERVICE_ACCOUNT).toBe(
      `karar-backup-checker@${PROD_PROJECT_ID}.iam.gserviceaccount.com`,
    );
    expect(String(backupCheckerRuntimeServiceAccount)).toContain(
      "karar-backup-checker@",
    );
  });

  it("analiz/silme runtime hesaplarını ÖDÜNÇ ALMAZ", () => {
    const account = String(backupCheckerRuntimeServiceAccount);
    expect(account).not.toContain("karar-analyze-runtime@");
    expect(account).not.toContain("karar-delete-runtime@");
  });

  it("HİÇBİR secret bağlı değildir (OPENAI_API_KEY dahil)", () => {
    expect(
      (checkBackupFreshnessOptions as Record<string, unknown>).secrets,
    ).toBeUndefined();
    const bound = endpointOf("checkBackupFreshness").secretEnvironmentVariables;
    expect(bound === undefined || (bound as unknown[]).length === 0).toBe(true);
    expect(JSON.stringify(checkBackupFreshnessOptions)).not.toContain("OPENAI");
  });

  it("çağrılabilir (callable) değildir: App Check/consume seçeneği taşımaz", () => {
    const options = checkBackupFreshnessOptions as Record<string, unknown>;
    expect(options.enforceAppCheck).toBeUndefined();
    expect(options.consumeAppCheckToken).toBeUndefined();
  });
});

describe("hedefli deploy sözleşmesi", () => {
  it("hedef YALNIZ checker fonksiyonudur", () => {
    expect(BACKUP_CHECKER_DEPLOY_TARGET).toBe("functions:checkBackupFreshness");
    expect(BACKUP_CHECKER_DEPLOY_TARGET.split(",")).toHaveLength(1);
  });

  it("hedef mevcut callable'ları İÇERMEZ", () => {
    for (const existing of [
      "analyzeDecision",
      "deleteAccount",
      "createRewardTicket",
      "admobRewardCallback",
    ]) {
      expect(BACKUP_CHECKER_DEPLOY_TARGET).not.toContain(existing);
    }
  });
});

describe("checker sabitleri", () => {
  it("başlangıç tazelik eşiği 30 saattir", () => {
    expect(BACKUP_FRESHNESS_THRESHOLD_HOURS).toBe(30);
  });

  it("konum ve veritabanı production sözleşmesiyle aynıdır", () => {
    expect(PROD_BACKUP_LOCATION).toBe("eur3");
    expect(BACKUP_DATABASE_ID).toBe("(default)");
  });
});
