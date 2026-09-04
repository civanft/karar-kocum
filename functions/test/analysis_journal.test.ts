/**
 * İŞ PAKETİ 2 / DİLİM E-1 — journal durum makinesi (saf sözleşme).
 */
import { describe, expect, it } from "vitest";

import {
  canFinalizeWithoutProvider,
  canTransition,
  isAlreadyApplied,
  isTerminal,
  JournalState,
  mayCallProvider,
} from "../src/ai/analysis_journal";

describe("geçiş tablosu", () => {
  it("mutlu yol: null → reserved → started → succeeded → completed", () => {
    expect(canTransition(null, JournalState.reserved)).toBe(true);
    expect(canTransition(JournalState.reserved, JournalState.providerCallStarted)).toBe(true);
    expect(canTransition(JournalState.providerCallStarted, JournalState.providerSucceeded)).toBe(true);
    expect(canTransition(JournalState.providerSucceeded, JournalState.completed)).toBe(true);
  });

  it("sağlayıcı çağrısı atlanamaz: reserved → succeeded YASAK", () => {
    expect(canTransition(JournalState.reserved, JournalState.providerSucceeded)).toBe(false);
  });

  it("rezervasyon atlanamaz: null → started YASAK", () => {
    expect(canTransition(null, JournalState.providerCallStarted)).toBe(false);
  });

  it("terminal durumlardan çıkış YOK", () => {
    for (const t of [JournalState.completed, JournalState.superseded, JournalState.terminalFailed]) {
      expect(isTerminal(t)).toBe(true);
      for (const to of Object.values(JournalState)) {
        expect(canTransition(t, to)).toBe(false);
      }
    }
  });

  it("uncertain YALNIZ started'dan gelir", () => {
    expect(canTransition(JournalState.providerCallStarted, JournalState.uncertain)).toBe(true);
    expect(canTransition(JournalState.reserved, JournalState.uncertain)).toBe(false);
    expect(canTransition(JournalState.providerSucceeded, JournalState.uncertain)).toBe(false);
  });

  it("superseded sağlayıcı çağrısından SONRA mümkündür", () => {
    expect(canTransition(JournalState.providerSucceeded, JournalState.superseded)).toBe(true);
    expect(canTransition(JournalState.providerCallStarted, JournalState.superseded)).toBe(true);
    expect(canTransition(null, JournalState.superseded)).toBe(false);
  });
});

describe("sağlayıcı çağrı izni", () => {
  it("yalnız yeni veya reserved kayıt sağlayıcıyı çağırabilir", () => {
    expect(mayCallProvider(null)).toBe(true);
    expect(mayCallProvider(JournalState.reserved)).toBe(true);
  });

  it("started sonrası ASLA ikinci sağlayıcı çağrısı yok", () => {
    for (const s of [
      JournalState.providerCallStarted,
      JournalState.providerSucceeded,
      JournalState.completed,
      JournalState.uncertain,
      JournalState.superseded,
      JournalState.terminalFailed,
    ]) {
      expect(mayCallProvider(s), `${s} sağlayıcıyı çağıramamalı`).toBe(false);
    }
  });

  it("uncertain kayıt aynı requestId ile YENİDEN çağrı yapamaz", () => {
    expect(mayCallProvider(JournalState.uncertain)).toBe(false);
  });
});

describe("kurtarma", () => {
  it("provider_succeeded sağlayıcısız finalize edilebilir", () => {
    expect(canFinalizeWithoutProvider(JournalState.providerSucceeded)).toBe(true);
  });

  it("diğer durumlar sağlayıcısız finalize EDİLEMEZ", () => {
    for (const s of [null, JournalState.reserved, JournalState.providerCallStarted, JournalState.completed]) {
      expect(canFinalizeWithoutProvider(s)).toBe(false);
    }
  });

  it("completed kayıt yeniden uygulanmaz", () => {
    expect(isAlreadyApplied(JournalState.completed)).toBe(true);
    expect(isAlreadyApplied(JournalState.providerSucceeded)).toBe(false);
  });
});
