/**
 * İŞ PAKETİ 2C — settlement hatası ve fırsatçı kurtarma sözleşmesi.
 *
 * Emulator testleri gerçek transaction ve sayaç davranışını kanıtlar;
 * burada kanıtlanan şey SERVİS sözleşmesidir: settlement çökerse ne olur,
 * kurtarma ne zaman tetiklenir ve kullanıcı ne görür.
 */
import { describe, expect, it, vi } from "vitest";

import { buildService, ctx, reqId } from "./helpers/analyze_harness";
import { JournalState } from "../src/ai/analysis_journal";
import { AppError } from "../src/core/errors";

const decisionId = "d1";
const payload = (rid: string) => ({ decisionId, requestId: rid });

async function attempt(h: ReturnType<typeof buildService>, rid: string) {
  try {
    await h.service.run(ctx, payload(rid));
    return null;
  } catch (e) {
    return e;
  }
}

describe("settlement başarısızlığı", () => {
  it("settleFailure çökse bile kullanıcı ASIL sağlayıcı hatasını görür", async () => {
    const h = buildService();
    h.gateway.failWith = new AppError("moderated", "İçerik uygun değil.");
    h.ports.failOn.settleFailure = true;

    const error = await attempt(h, reqId("a"));

    // Settlement hatası, sağlayıcı hatasının YERİNE GEÇMEZ.
    expect(error).toBeInstanceOf(AppError);
    expect((error as AppError).code).toBe("moderated");
  });

  it("settlement çökerse kayıt KURTARILABİLİR kalır (rezervasyon açık)", async () => {
    const h = buildService();
    h.gateway.failWith = new AppError("moderated", "İçerik uygun değil.");
    h.ports.failOn.settleFailure = true;
    const rid = reqId("b");

    await attempt(h, rid);

    // Terminal işaretlenemedi: kayıt hâlâ açık ve rezervasyon duruyor.
    expect(h.ports.journal.get(rid)!.state).toBe(
      JournalState.providerCallStarted,
    );
    expect(h.ports.provenance.get(rid)!.open).toBe(true);
    expect(h.ports.reserved.credits).toBe(1);
  });

  it("asılı kalan kayıt SONRAKİ analizde fırsatçı olarak kapatılır", async () => {
    const h = buildService();
    h.gateway.failWith = new AppError("moderated", "İçerik uygun değil.");
    h.ports.failOn.settleFailure = true;
    const stale = reqId("c");
    await attempt(h, stale);
    expect(h.ports.reserved.credits).toBe(1);

    // Zaman ilerler: rezervasyon artık ASILI sayılır.
    const later = Date.now() + 60 * 60 * 1000;
    h.ports.now = () => later;
    h.gateway.failWith = null;

    await h.service.run(ctx, payload(reqId("d")));

    // Asılı kayıt kapandı: kredi rezervasyonu kullanıcıya iade edildi.
    expect(h.ports.journal.get(stale)!.state).toBe(JournalState.uncertain);
    expect(h.ports.provenance.get(stale)!.open).toBe(false);
    expect(h.ports.reserved.credits).toBe(0);
    // Sağlayıcı asılı kayıt için YENİDEN çağrılmadı (yalnız yeni analiz).
    expect(h.gateway.attempts).toBe(2);
  });
});

describe("fırsatçı kurtarma sözleşmesi", () => {
  it("kurtarma HATA verse bile kullanıcının analizi engellenmez", async () => {
    const h = buildService();
    vi.spyOn(h.ports, "reconcileStaleReservations").mockRejectedValueOnce(
      new Error("Firestore geçici hata"),
    );

    const result = await h.service.run(ctx, payload(reqId("e")));

    expect(result.analysis.summary).toBeTruthy();
    expect(h.ports.commits).toBe(1);
  });

  it("kurtarma SINIRLIDIR: bir istekte en fazla `limit` kayıt kapatılır", async () => {
    const h = buildService();
    const spy = vi.spyOn(h.ports, "reconcileStaleReservations");

    await h.service.run(ctx, payload(reqId("f")));

    expect(spy).toHaveBeenCalledTimes(1);
    const [, limit] = spy.mock.calls[0]!;
    expect(limit).toBeGreaterThan(0);
    expect(limit).toBeLessThanOrEqual(20); // sınırsız tarama YOK
  });

  it("AKTİF (süresi dolmamış) rezervasyon kurtarmaya girmez", async () => {
    const h = buildService();
    h.gateway.failWith = new AppError("moderated", "İçerik uygun değil.");
    h.ports.failOn.settleFailure = true;
    const active = reqId("g");
    await attempt(h, active);

    // Zaman İLERLEMEDİ: kayıt hâlâ aktif sayılmalı.
    h.gateway.failWith = null;
    await h.service.run(ctx, payload(reqId("h")));

    expect(h.ports.journal.get(active)!.state).toBe(
      JournalState.providerCallStarted,
    );
    expect(h.ports.provenance.get(active)!.open).toBe(true);
  });
});

describe("stale eşiği", () => {
  it("eşik fonksiyon timeout'undan (60 sn) BÜYÜKTÜR", async () => {
    const { ANALYSIS_RESERVATION_STALE_MS } = await import("../src/config");
    expect(ANALYSIS_RESERVATION_STALE_MS).toBeGreaterThan(60_000);
  });
});
