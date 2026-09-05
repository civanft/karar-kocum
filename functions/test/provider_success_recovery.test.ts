/**
 * İŞ PAKETİ 2D — legacy/anormal kayıt sözleşmesi.
 *
 * Emulator testleri gerçek transaction davranışını kanıtlar; burada
 * kanıtlanan şey SÖZLEŞMEDİR: köken eksik, usage eksik ya da rezervasyon
 * zaten kapatılmışken kredi ve maliyet İKİNCİ kez uygulanmaz.
 */
import { describe, expect, it } from "vitest";

import {
  buildService,
  ctx,
  openReservationWithResult,
  reqId,
} from "./helpers/analyze_harness";
import { JournalState } from "../src/ai/analysis_journal";

const decisionId = "d1";
const payload = (rid: string) => ({ decisionId, requestId: rid });

describe("anormal kayıt: rezervasyon kapalı ama provider_succeeded", () => {
  it("muhasebe İKİNCİ kez uygulanmaz", async () => {
    const h = buildService();
    const rid = reqId("a");
    await openReservationWithResult(h, rid);

    // 2C artığını taklit et: rezervasyon kapatılmış, kayıt hâlâ açık.
    const prov = h.ports.provenance.get(rid)!;
    h.ports.provenance.set(rid, { ...prov, open: false, expiresAtMs: null });
    const spendBefore = h.spend.records;
    const tokensBefore = h.tokens.records;

    await h.service.run(ctx, payload(rid));

    // Analiz uygulandı, ama rezervasyon sayaçları TEKRAR kapatılmadı.
    expect(h.ports.journal.get(rid)!.state).toBe(JournalState.completed);
    expect(h.spend.records).toBe(spendBefore);
    expect(h.tokens.records).toBe(tokensBefore);
    expect(h.ports.commits).toBe(1);
  });

  it("kredi TAM BİR kez düşer", async () => {
    const h = buildService();
    h.ports.credits = 3;
    const rid = reqId("b");
    await openReservationWithResult(h, rid);
    const prov = h.ports.provenance.get(rid)!;
    h.ports.provenance.set(rid, { ...prov, open: false, expiresAtMs: null });

    await h.service.run(ctx, payload(rid));
    await h.service.run(ctx, payload(rid)); // tekrar: etkisiz

    expect(h.ports.credits).toBe(2);
  });
});

describe("kurtarma idempotency'si", () => {
  it("asılı provider_succeeded kaydı TEK finalization üretir", async () => {
    const h = buildService();
    h.ports.credits = 3;
    const rid = reqId("c");
    await openReservationWithResult(h, rid);

    // Zaman ilerler: kayıt ASILI sayılır.
    const later = Date.now() + 60 * 60 * 1000;
    h.ports.now = () => later;

    await h.service.run(ctx, payload(reqId("d")));
    await h.service.run(ctx, payload(reqId("e")));

    // Asılı kayıt bir kez kapandı; kendi kredisi bir kez tüketildi.
    expect(h.ports.provenance.get(rid)!.open).toBe(false);
    expect(h.ports.reserved.credits).toBe(0);
  });

  it("kurtarma sağlayıcıyı YENİDEN çağırmaz", async () => {
    const h = buildService();
    h.ports.credits = 5;
    const rid = reqId("f");
    await openReservationWithResult(h, rid);
    const before = h.gateway.attempts;

    h.ports.now = () => Date.now() + 60 * 60 * 1000;
    await h.service.run(ctx, payload(reqId("g")));

    // Yalnız YENİ analizin çağrısı eklendi.
    expect(h.gateway.attempts).toBe(before + 1);
  });
});

describe("rezerve sayaçlar hiçbir akışta negatif olamaz", () => {
  it("art arda üç analiz sonrası tüm sayaçlar >= 0", async () => {
    const h = buildService();
    h.ports.credits = 5;

    for (const c of ["h", "i", "j"]) {
      await h.service.run(ctx, payload(reqId(c)));
      expect(h.ports.reserved.credits).toBeGreaterThanOrEqual(0);
      expect(h.ports.reserved.tokens).toBeGreaterThanOrEqual(0);
      expect(h.ports.reserved.usd).toBeGreaterThanOrEqual(0);
    }
    expect(h.ports.credits).toBe(2);
  });
});
