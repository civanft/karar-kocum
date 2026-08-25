/**
 * PR-PROD-2 — deploy hedefi ↔ bölge eşlemesi.
 *
 * Bölge, deploy zamanında `projectID` parametresinden çözülür; global
 * scope'ta `process.env` OKUNMAZ (emulator/analiz aşamasında env yoktur ve
 * `FUNCTION_REGION` reserved bir addır). Bu test iki sözleşmeyi sabitler:
 *   1. saf `regionForProject` eşlemesi,
 *   2. dört export'un da AYNI merkezi bölge ifadesini kullanması.
 */
import { describe, expect, it } from "vitest";

import {
  analyzeRuntimeServiceAccount,
  deleteRuntimeServiceAccount,
  DEV_PROJECT_ID,
  DEV_REGION,
  functionRegion,
  PROD_PROJECT_ID,
  PROD_REGION,
  regionForProject,
} from "../src/core/deployment";
import * as api from "../src/index";

describe("proje → bölge eşlemesi", () => {
  it("dev projesi us-central1'de kalır", () => {
    expect(regionForProject(DEV_PROJECT_ID)).toBe("us-central1");
    expect(DEV_REGION).toBe("us-central1");
  });

  it("production projesi europe-west1'e gider", () => {
    expect(regionForProject(PROD_PROJECT_ID)).toBe("europe-west1");
    expect(PROD_REGION).toBe("europe-west1");
  });

  it("proje kimlikleri beklenen değerler", () => {
    expect(DEV_PROJECT_ID).toBe("karar-veriyorum-dev");
    expect(PROD_PROJECT_ID).toBe("karar-kocum-production");
  });

  it("tanınmayan proje güvenli tarafa (dev bölgesi) düşer", () => {
    expect(regionForProject("baska-proje")).toBe(DEV_REGION);
  });
});

describe("deploy metadata", () => {
  const DEPLOYED = [
    "analyzeDecision",
    "createRewardTicket",
    "admobRewardCallback",
    "deleteAccount",
  ] as const;

  /** v2, bölge sabitse dizi, ifade ise ifadenin kendisini saklar. */
  const regionOf = (name: string): unknown => {
    const fn = (api as Record<string, unknown>)[name] as {
      __endpoint?: { region?: unknown };
    };
    expect(fn.__endpoint).toBeDefined();
    const region = fn.__endpoint?.region;
    return Array.isArray(region) ? region[0] : region;
  };

  it.each(DEPLOYED)("%s merkezi bölge ifadesini kullanır", (name) => {
    // toBe: aynı NESNE olmalı — kopyalanmış eşdeğer bir ifade geçmez.
    expect(regionOf(name)).toBe(functionRegion);
  });

  it("bölge sabit bir dize DEĞİL, deploy-zamanı ifadesidir", () => {
    // Sabit yazılırsa dev deploy'u da europe-west1'e taşınırdı.
    expect(typeof regionOf("analyzeDecision")).not.toBe("string");
  });

  it("dört fonksiyon da AYNI ifadeyi paylaşır (kopyalanmış sabit yok)", () => {
    const unique = new Set(DEPLOYED.map((name) => regionOf(name)));
    expect(unique.size).toBe(1);
    expect([...unique][0]).toBe(functionRegion);
  });

  it("analyzeDecision merkezi ve ortam-duyarlı runtime hesabını kullanır", () => {
    const endpoint = api.analyzeDecision.__endpoint;

    expect(endpoint.serviceAccountEmail).toBe(analyzeRuntimeServiceAccount);
    expect(String(endpoint.serviceAccountEmail)).toBe(
      'params.PROJECT_ID == "karar-kocum-production" ? ' +
        '"karar-analyze-runtime@karar-kocum-production.iam.gserviceaccount.com" : ' +
        '"740423241326-compute@developer.gserviceaccount.com"',
    );
  });

  it("deleteAccount merkezi ve ortam-duyarlı runtime hesabını kullanır", () => {
    const endpoint = api.deleteAccount.__endpoint;

    expect(endpoint.serviceAccountEmail).toBe(deleteRuntimeServiceAccount);
    expect(String(endpoint.serviceAccountEmail)).toBe(
      'params.PROJECT_ID == "karar-kocum-production" ? ' +
        '"karar-delete-runtime@karar-kocum-production.iam.gserviceaccount.com" : ' +
        '"740423241326-compute@developer.gserviceaccount.com"',
    );
  });
});
