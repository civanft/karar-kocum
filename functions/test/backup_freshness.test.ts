/**
 * 6C4 — backup freshness checker: saf değerlendirme, katalog istemcisi ve
 * zamanlanmış kontrol gövdesi.
 *
 * Checker'ın tek işi YEDEK METADATA'sını okumaktır. Bu yüzden testler iki
 * şeyi birlikte sabitler: (1) tazelik kararının doğruluğu, (2) hiçbir hata
 * yolunun "yedek yok" veya "sağlıklı" diye yorumlanmaması. Bir 403'ün boş
 * listeye dönüşmesi, alarmı sessizce kapatan en tehlikeli hatadır.
 */
import { logger } from "firebase-functions/v2";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type {
  BackupRecord,
  FetchLike,
  FetchResponse,
} from "../src/backup/backup_catalog";
import { BackupCheckError } from "../src/backup/backup_catalog";
import { runBackupFreshnessCheck } from "../src/backup/check_backup_freshness";
import { FirestoreBackupCatalog } from "../src/backup/firestore_backup_catalog";
import {
  classifyRetention,
  evaluateBackupFreshness,
  type FreshnessCriteria,
} from "../src/backup/freshness";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const NOW = Date.parse("2026-09-20T12:00:00.000Z");
const PROJECT = "karar-kocum-production";

const iso = (ms: number): string => new Date(ms).toISOString();

const criteria: FreshnessCriteria = {
  projectId: PROJECT,
  location: "eur3",
  databaseId: "(default)",
  thresholdHours: 30,
  stateGraceHours: 2,
  nowMs: NOW,
};

function record(overrides: Partial<BackupRecord> = {}): BackupRecord {
  const snapshotMs = NOW - 2 * HOUR;
  return {
    projectId: PROJECT,
    location: "eur3",
    databaseId: "(default)",
    databaseProjectId: PROJECT,
    state: "READY",
    snapshotTime: iso(snapshotMs),
    expireTime: iso(snapshotMs + 7 * DAY),
    ...overrides,
  };
}

/** Günlük programın imzası: retention ≈ 7 gün (6B'de gözlendi). */
function daily(ageMs: number, overrides: Partial<BackupRecord> = {}) {
  const snapshotMs = NOW - ageMs;
  return record({
    snapshotTime: iso(snapshotMs),
    expireTime: iso(snapshotMs + 7 * DAY),
    ...overrides,
  });
}

/** Haftalık programın imzası: retention ≈ 28 gün. */
function weekly(ageMs: number, overrides: Partial<BackupRecord> = {}) {
  const snapshotMs = NOW - ageMs;
  return record({
    snapshotTime: iso(snapshotMs),
    expireTime: iso(snapshotMs + 28 * DAY),
    ...overrides,
  });
}

describe("retention sınıflandırması (string varsayımı YOK)", () => {
  it("7 gün → daily, 28 gün → weekly", () => {
    expect(classifyRetention(7 * 24)).toBe("daily");
    expect(classifyRetention(28 * 24)).toBe("weekly");
  });

  it("tolerans bandı içinde kalır", () => {
    expect(classifyRetention(7 * 24 + 11)).toBe("daily");
    expect(classifyRetention(7 * 24 - 11)).toBe("daily");
    expect(classifyRetention(28 * 24 + 11)).toBe("weekly");
  });

  it("tolerans bandı dışı sınıflandırılamaz (aday olamaz)", () => {
    expect(classifyRetention(7 * 24 + 13)).toBe("unknown");
    expect(classifyRetention(14 * 24)).toBe("unknown");
    expect(classifyRetention(0)).toBe("unknown");
    expect(classifyRetention(Number.NaN)).toBe("unknown");
  });
});

describe("evaluateBackupFreshness", () => {
  it("güncel READY daily yedek → fresh", () => {
    const verdict = evaluateBackupFreshness([daily(2 * HOUR)], criteria);
    expect(verdict.fresh).toBe(true);
    expect(verdict.reason).toBe("fresh");
    expect(verdict.ageHours).toBe(2);
    expect(verdict.readyDailyCount).toBe(1);
    expect(verdict.backupCount).toBe(1);
    expect(verdict.unexpected).toEqual([]);
  });

  it("TAM 30 saat sınırı hâlâ fresh (kapsayıcı eşik)", () => {
    const verdict = evaluateBackupFreshness([daily(30 * HOUR)], criteria);
    expect(verdict.fresh).toBe(true);
    expect(verdict.ageHours).toBe(30);
  });

  it("30 saati 1 ms aşan yedek stale (> ile >= ayrımı)", () => {
    const verdict = evaluateBackupFreshness([daily(30 * HOUR + 1)], criteria);
    expect(verdict.fresh).toBe(false);
    expect(verdict.reason).toBe("stale");
  });

  it("30 saatten eski yedek stale", () => {
    const verdict = evaluateBackupFreshness([daily(31 * HOUR)], criteria);
    expect(verdict.fresh).toBe(false);
    expect(verdict.reason).toBe("stale");
    expect(verdict.ageHours).toBe(31);
  });

  it("boş liste stale sayılır, 'sağlıklı' değil", () => {
    const verdict = evaluateBackupFreshness([], criteria);
    expect(verdict.fresh).toBe(false);
    expect(verdict.reason).toBe("no_daily_backup");
    expect(verdict.ageHours).toBeNull();
    expect(verdict.backupCount).toBe(0);
  });

  it("YALNIZ weekly yedek varsa daily tazeliği BAŞARILI sayılmaz", () => {
    const verdict = evaluateBackupFreshness([weekly(1 * HOUR)], criteria);
    expect(verdict.fresh).toBe(false);
    expect(verdict.reason).toBe("no_daily_backup");
    expect(verdict.readyDailyCount).toBe(0);
    expect(verdict.backupCount).toBe(1);
  });

  it("Pazar günü aynı snapshot'lı daily + weekly doğru ayrışır", () => {
    const verdict = evaluateBackupFreshness(
      [weekly(3 * HOUR), daily(3 * HOUR)],
      criteria,
    );
    expect(verdict.fresh).toBe(true);
    expect(verdict.readyDailyCount).toBe(1);
    expect(verdict.backupCount).toBe(2);
  });

  it("birden fazla daily içinden EN YENİSİ seçilir", () => {
    const verdict = evaluateBackupFreshness(
      [daily(50 * HOUR), daily(4 * HOUR), daily(26 * HOUR)],
      criteria,
    );
    expect(verdict.fresh).toBe(true);
    expect(verdict.ageHours).toBe(4);
    expect(verdict.readyDailyCount).toBe(3);
  });

  it("süresi dolmuş yedek aday olamaz", () => {
    const snapshotMs = NOW - 8 * DAY;
    const expired = record({
      snapshotTime: iso(snapshotMs),
      expireTime: iso(snapshotMs + 7 * DAY),
    });
    const verdict = evaluateBackupFreshness([expired], criteria);
    expect(verdict.fresh).toBe(false);
    expect(verdict.readyDailyCount).toBe(0);
  });

  it("bozuk snapshotTime fail-closed: aday DEĞİL ve anormal olarak raporlanır", () => {
    const verdict = evaluateBackupFreshness(
      [record({ snapshotTime: "gecerli-bir-tarih-degil" })],
      criteria,
    );
    expect(verdict.fresh).toBe(false);
    expect(verdict.readyDailyCount).toBe(0);
    expect(verdict.unexpected).toEqual([
      { state: "INVALID_TIMESTAMP", ageHours: null },
    ]);
  });

  it("bozuk expireTime de fail-closed", () => {
    const verdict = evaluateBackupFreshness(
      [record({ expireTime: "" })],
      criteria,
    );
    expect(verdict.fresh).toBe(false);
    expect(verdict.unexpected[0]?.state).toBe("INVALID_TIMESTAMP");
  });

  it("gelecek tarihli snapshot fail-closed (saat kayması)", () => {
    const verdict = evaluateBackupFreshness([daily(-2 * HOUR)], criteria);
    expect(verdict.fresh).toBe(false);
    expect(verdict.unexpected[0]?.state).toBe("FUTURE_SNAPSHOT");
  });

  it("YANLIŞ database kapsam dışıdır", () => {
    const verdict = evaluateBackupFreshness(
      [daily(1 * HOUR, { databaseId: "analytics" })],
      criteria,
    );
    expect(verdict.fresh).toBe(false);
    expect(verdict.backupCount).toBe(0);
  });

  it("YANLIŞ location kapsam dışıdır", () => {
    const verdict = evaluateBackupFreshness(
      [daily(1 * HOUR, { location: "nam5" })],
      criteria,
    );
    expect(verdict.fresh).toBe(false);
    expect(verdict.backupCount).toBe(0);
  });

  it("YANLIŞ proje kapsam dışıdır (yedek adı ve veritabanı yolu)", () => {
    expect(
      evaluateBackupFreshness(
        [daily(1 * HOUR, { projectId: "baska-proje" })],
        criteria,
      ).backupCount,
    ).toBe(0);
    expect(
      evaluateBackupFreshness(
        [daily(1 * HOUR, { databaseProjectId: "baska-proje" })],
        criteria,
      ).backupCount,
    ).toBe(0);
  });

  it("READY olmayan durum anormal olarak raporlanır", () => {
    const verdict = evaluateBackupFreshness(
      [daily(4 * HOUR), daily(1 * HOUR, { state: "NOT_AVAILABLE" })],
      criteria,
    );
    expect(verdict.fresh).toBe(true);
    expect(verdict.unexpected).toEqual([
      { state: "NOT_AVAILABLE", ageHours: 1 },
    ]);
  });

  it("CREATING tolerans içinde normaldir, tolerans dışında anormaldir", () => {
    expect(
      evaluateBackupFreshness(
        [daily(4 * HOUR), daily(1 * HOUR, { state: "CREATING" })],
        criteria,
      ).unexpected,
    ).toEqual([]);
    expect(
      evaluateBackupFreshness(
        [daily(4 * HOUR), daily(5 * HOUR, { state: "CREATING" })],
        criteria,
      ).unexpected,
    ).toEqual([{ state: "CREATING", ageHours: 5 }]);
  });

  it("yaş düşük kardinalite için 0.1 saate yuvarlanır", () => {
    const verdict = evaluateBackupFreshness(
      [daily(2 * HOUR + 187_000)],
      criteria,
    );
    expect(verdict.ageHours).toBe(2.1);
  });

  it("eşik dışarıdan verilir (koda gömülü değil)", () => {
    const verdict = evaluateBackupFreshness([daily(31 * HOUR)], {
      ...criteria,
      thresholdHours: 48,
    });
    expect(verdict.fresh).toBe(true);
    expect(verdict.thresholdHours).toBe(48);
  });
});

// ---------------------------------------------------------------- katalog

interface FakePage {
  status?: number;
  body?: unknown;
  throws?: unknown;
  jsonThrows?: boolean;
}

function fakeFetch(pages: FakePage[]): {
  impl: FetchLike;
  calls: Array<{ url: string; headers: Record<string, string> }>;
} {
  const calls: Array<{ url: string; headers: Record<string, string> }> = [];
  const impl: FetchLike = async (url, init) => {
    calls.push({ url, headers: init.headers });
    const page = pages[Math.min(calls.length - 1, pages.length - 1)];
    if (page === undefined) throw new Error("beklenmeyen çağrı");
    if (page.throws !== undefined) throw page.throws;
    const status = page.status ?? 200;
    const response: FetchResponse = {
      ok: status >= 200 && status < 300,
      status,
      json: async () => {
        if (page.jsonThrows === true) throw new SyntaxError("bozuk gövde");
        return page.body;
      },
    };
    return response;
  };
  return { impl, calls };
}

function catalogWith(
  pages: FakePage[],
  overrides: Partial<{
    projectId: string;
    location: string;
    maxAttempts: number;
  }> = {},
) {
  const { impl, calls } = fakeFetch(pages);
  const catalog = new FirestoreBackupCatalog({
    projectId: overrides.projectId ?? PROJECT,
    location: overrides.location ?? "eur3",
    auth: { getAccessToken: async () => "test-access-token" },
    fetchImpl: impl,
    timeoutMs: 1_000,
    maxAttempts: overrides.maxAttempts ?? 2,
    delay: async () => {},
  });
  return { catalog, calls };
}

const apiBackup = (suffix: string, snapshot: string, retentionDays: number) => ({
  name: `projects/${PROJECT}/locations/eur3/backups/${suffix}`,
  database: `projects/${PROJECT}/databases/(default)`,
  databaseUid: "db-uid",
  state: "READY",
  snapshotTime: snapshot,
  expireTime: iso(Date.parse(snapshot) + retentionDays * DAY),
});

describe("FirestoreBackupCatalog", () => {
  it("yedek metadata'sını ayrıştırır (proje/konum/veritabanı ad yolundan)", async () => {
    const { catalog, calls } = catalogWith([
      { body: { backups: [apiBackup("a", iso(NOW - HOUR), 7)] } },
    ]);
    const backups = await catalog.listBackups();
    expect(backups).toHaveLength(1);
    expect(backups[0]).toMatchObject({
      projectId: PROJECT,
      location: "eur3",
      databaseId: "(default)",
      databaseProjectId: PROJECT,
      state: "READY",
    });
    expect(calls[0]?.url).toBe(
      `https://firestore.googleapis.com/v1/projects/${PROJECT}` +
        "/locations/eur3/backups",
    );
    expect(calls[0]?.headers.Authorization).toBe("Bearer test-access-token");
  });

  it("modelde belge/koleksiyon verisi veya yedek kimliği YOKTUR", async () => {
    const { catalog } = catalogWith([
      { body: { backups: [apiBackup("gizli-uuid", iso(NOW - HOUR), 7)] } },
    ]);
    const [backup] = await catalog.listBackups();
    expect(Object.keys(backup ?? {}).sort()).toEqual([
      "databaseId",
      "databaseProjectId",
      "expireTime",
      "location",
      "projectId",
      "snapshotTime",
      "state",
    ]);
    expect(JSON.stringify(backup)).not.toContain("gizli-uuid");
  });

  it("sayfalamayı takip eder", async () => {
    const { catalog, calls } = catalogWith([
      {
        body: {
          backups: [apiBackup("a", iso(NOW - HOUR), 7)],
          nextPageToken: "sayfa-2",
        },
      },
      { body: { backups: [apiBackup("b", iso(NOW - 2 * HOUR), 28)] } },
    ]);
    expect(await catalog.listBackups()).toHaveLength(2);
    expect(calls).toHaveLength(2);
    expect(calls[1]?.url).toContain("pageToken=sayfa-2");
  });

  it("aynı sayfa token'ı tekrar ederse döngüye girmez", async () => {
    const { catalog } = catalogWith([
      { body: { backups: [], nextPageToken: "ayni" } },
    ]);
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "page_limit",
    });
  });

  it("401 auth hatasıdır", async () => {
    const { catalog } = catalogWith([{ status: 401, body: {} }]);
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "auth",
      httpStatus: 401,
    });
  });

  it("403 BOŞ LİSTEYE dönüşmez; yetki hatasıdır ve tekrar denenmez", async () => {
    const { catalog, calls } = catalogWith([{ status: 403, body: {} }]);
    await expect(catalog.listBackups()).rejects.toBeInstanceOf(
      BackupCheckError,
    );
    await expect(
      catalogWith([{ status: 403, body: {} }]).catalog.listBackups(),
    ).rejects.toMatchObject({ errorType: "permission" });
    expect(calls).toHaveLength(1);
  });

  it("500 sunucu hatasıdır ve sınırlı sayıda tekrar denenir", async () => {
    const { catalog, calls } = catalogWith([{ status: 500, body: {} }]);
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "server",
    });
    expect(calls).toHaveLength(2);
  });

  it("zaman aşımı ayrı bir hata türüdür", async () => {
    const timeoutError = new Error("zaman aşımı");
    timeoutError.name = "TimeoutError";
    const { catalog } = catalogWith([{ throws: timeoutError }]);
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "timeout",
    });
  });

  it("ağ hatası ayrı bir hata türüdür", async () => {
    const { catalog } = catalogWith([{ throws: new TypeError("fetch failed") }]);
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "network",
    });
  });

  it("bozuk gövde parse hatasıdır", async () => {
    const { catalog } = catalogWith([{ jsonThrows: true }]);
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "parse",
    });
  });

  it("beklenmeyen alan biçimi parse hatasıdır", async () => {
    await expect(
      catalogWith([{ body: { backups: [{ name: 42 }] } }]).catalog.listBackups(),
    ).rejects.toMatchObject({ errorType: "parse" });
    await expect(
      catalogWith([{ body: { backups: "hepsi" } }]).catalog.listBackups(),
    ).rejects.toMatchObject({ errorType: "parse" });
  });

  it("ulaşılamayan konum boş liste sayılmaz", async () => {
    const { catalog } = catalogWith([
      { body: { backups: [], unreachable: ["eur3"] } },
    ]);
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "unreachable",
    });
  });

  it("production dışı proje/konumda fail-closed: istek bile atılmaz", async () => {
    const wrongProject = catalogWith([{ body: { backups: [] } }], {
      projectId: "karar-veriyorum-dev",
    });
    await expect(wrongProject.catalog.listBackups()).rejects.toMatchObject({
      errorType: "config",
    });
    expect(wrongProject.calls).toHaveLength(0);

    const wrongLocation = catalogWith([{ body: { backups: [] } }], {
      location: "nam5",
    });
    await expect(wrongLocation.catalog.listBackups()).rejects.toMatchObject({
      errorType: "config",
    });
    expect(wrongLocation.calls).toHaveLength(0);
  });

  it("erişim token'ı alınamazsa auth hatasıdır", async () => {
    const { impl } = fakeFetch([{ body: { backups: [] } }]);
    const catalog = new FirestoreBackupCatalog({
      projectId: PROJECT,
      location: "eur3",
      auth: { getAccessToken: async () => null },
      fetchImpl: impl,
      timeoutMs: 1_000,
      delay: async () => {},
    });
    await expect(catalog.listBackups()).rejects.toMatchObject({
      errorType: "auth",
    });
  });
});

// ------------------------------------------------- zamanlanmış kontrol gövdesi

type LoggedLine = { level: string; event: string; fields: Record<string, unknown> };

function captureLogs(): LoggedLine[] {
  const lines: LoggedLine[] = [];
  for (const level of ["debug", "info", "warn", "error"] as const) {
    vi.spyOn(logger, level).mockImplementation((...args: unknown[]) => {
      lines.push({
        level,
        event: String(args[0]),
        fields: (args[1] ?? {}) as Record<string, unknown>,
      });
    });
  }
  return lines;
}

function depsWith(
  listBackups: () => Promise<readonly BackupRecord[]>,
  thresholdHours = 30,
) {
  return {
    catalog: { listBackups },
    nowMs: () => NOW,
    thresholdHours,
    stateGraceHours: 2,
    projectId: PROJECT,
    location: "eur3",
    databaseId: "(default)",
  };
}

describe("runBackupFreshnessCheck", () => {
  let lines: LoggedLine[];

  beforeEach(() => {
    lines = captureLogs();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  const events = () => lines.map((l) => l.event);
  const line = (event: string) => lines.find((l) => l.event === event);

  it("sağlıklı kontrolde YALNIZ heartbeat üretir", async () => {
    await runBackupFreshnessCheck(depsWith(async () => [daily(3 * HOUR)]));
    expect(events()).toEqual(["backup_check_heartbeat"]);
    const heartbeat = line("backup_check_heartbeat");
    expect(heartbeat?.level).toBe("info");
    expect(heartbeat?.fields).toMatchObject({
      checkResult: "fresh",
      ageHours: 3,
      thresholdHours: 30,
      backupCount: 1,
      readyDailyCount: 1,
      location: "eur3",
    });
  });

  it("bayat yedekte stale olayı + heartbeat üretir", async () => {
    await runBackupFreshnessCheck(depsWith(async () => [daily(40 * HOUR)]));
    expect(events()).toContain("backup_freshness_stale");
    expect(line("backup_freshness_stale")?.level).toBe("warn");
    expect(line("backup_freshness_stale")?.fields).toMatchObject({
      ageHours: 40,
      thresholdHours: 30,
      checkResult: "stale",
    });
    expect(line("backup_check_heartbeat")?.fields.checkResult).toBe("stale");
  });

  it("hiç daily yedek yoksa stale olayı üretir", async () => {
    await runBackupFreshnessCheck(depsWith(async () => [weekly(1 * HOUR)]));
    expect(events()).toContain("backup_freshness_stale");
    expect(line("backup_freshness_stale")?.fields.reason).toBe(
      "no_daily_backup",
    );
  });

  it("anormal durum olayı ayrı üretilir", async () => {
    await runBackupFreshnessCheck(
      depsWith(async () => [
        daily(2 * HOUR),
        daily(9 * HOUR, { state: "NOT_AVAILABLE" }),
      ]),
    );
    expect(events()).toContain("backup_state_unexpected");
    expect(line("backup_state_unexpected")?.level).toBe("warn");
    expect(line("backup_state_unexpected")?.fields).toMatchObject({
      state: "NOT_AVAILABLE",
      ageHours: 9,
    });
    expect(events()).not.toContain("backup_freshness_stale");
  });

  it("kontrol hatası 'yedek yok' DEĞİL, 'kontrol edilemedi' olarak raporlanır", async () => {
    await runBackupFreshnessCheck(
      depsWith(async () => {
        throw new BackupCheckError("permission", 403);
      }),
    );
    expect(events()).toContain("backup_check_failed");
    expect(events()).not.toContain("backup_freshness_stale");
    expect(line("backup_check_failed")?.level).toBe("error");
    expect(line("backup_check_failed")?.fields).toMatchObject({
      errorType: "permission",
      httpStatus: 403,
    });
  });

  it("hata yolunda da heartbeat üretilir (checkResult=failed)", async () => {
    await runBackupFreshnessCheck(
      depsWith(async () => {
        throw new BackupCheckError("timeout");
      }),
    );
    expect(events()).toContain("backup_check_heartbeat");
    expect(line("backup_check_heartbeat")?.fields).toMatchObject({
      checkResult: "failed",
      errorType: "timeout",
    });
  });

  it("beklenmeyen istisna da fail-closed sınıflandırılır ve fırlatılmaz", async () => {
    await expect(
      runBackupFreshnessCheck(
        depsWith(async () => {
          throw new Error("beklenmeyen");
        }),
      ),
    ).resolves.toBeUndefined();
    expect(line("backup_check_failed")?.fields.errorType).toBe("unknown");
  });

  it("hiçbir log satırı yasaklı içerik taşımaz", async () => {
    await runBackupFreshnessCheck(
      depsWith(async () => [
        daily(50 * HOUR),
        daily(3 * HOUR, { state: "NOT_AVAILABLE" }),
      ]),
    );
    const allowed = new Set([
      "fn",
      "jobId",
      "uidHash",
      "ageHours",
      "thresholdHours",
      "backupCount",
      "readyDailyCount",
      "state",
      "location",
      "database",
      "checkResult",
      "reason",
      "errorType",
      "httpStatus",
      "unexpectedCount",
    ]);
    for (const entry of lines) {
      for (const key of Object.keys(entry.fields)) {
        expect(allowed.has(key)).toBe(true);
      }
      const dump = JSON.stringify(entry.fields);
      expect(dump).not.toMatch(/backups\//);
      expect(dump.toLowerCase()).not.toContain("token");
      expect(dump.toLowerCase()).not.toContain("snapshottime");
    }
  });
});
