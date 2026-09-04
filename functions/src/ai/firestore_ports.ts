/**
 * AnalysisPorts üretim implementasyonu — sadeleştirilmiş MVP (6B):
 * aiAnalyses/latest SABİT belge, aiJobs yok, latestAnalysisId yok.
 * commitAnalysis TEK transaction: kredi yeniden doğrula + düş + analiz
 * + status — remaining > 0 şartıyla düşüm → NEGATİF DEĞER İMKÂNSIZ.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import {
  ANALYSIS_REQUESTS_COLLECTION,
  canTransition,
  JournalState,
} from "./analysis_journal.js";
import {
  LATEST_ANALYSIS_ID,
  type AnalysisPorts,
  type CreditsSnapshot,
  type JournalRecord,
  type StoredAnalysis,
} from "./analyze_service.js";
import { contentFingerprint } from "./analysis_fingerprint.js";
import type { TokenUsage } from "./openai_gateway.js";
import { INITIAL_FREE_CREDITS } from "./config.js";

export class FirestoreAnalysisPorts implements AnalysisPorts {
  constructor(private readonly uid: string) {}

  private get db() {
    return getFirestore();
  }

  private decisionRef(decisionId: string) {
    return this.db.doc(`users/${this.uid}/decisions/${decisionId}`);
  }

  async readDecisionContent(decisionId: string): Promise<unknown | null> {
    const snapshot = await this.decisionRef(decisionId).get();
    if (!snapshot.exists) return null;
    const data = snapshot.data()!;
    return {
      title: data["title"],
      options: data["options"],
      criteria: data["criteria"],
    };
  }

  /** Alan hiç yazılmamışsa BAŞLANGIÇ kabul edilir (sunucu lazy-init). */
  async peekCredits(): Promise<CreditsSnapshot> {
    const user = await this.db.doc(`users/${this.uid}`).get();
    const data = user.data() ?? {};
    const plan = data["plan"] === "premium" ? "premium" : "free";
    const pools = readPools(data);
    return { plan, remaining: pools.free + pools.reward };
  }

  private journalRef(requestId: string) {
    return this.db.doc(
      `users/${this.uid}/${ANALYSIS_REQUESTS_COLLECTION}/${requestId}`,
    );
  }

  private static toRecord(data: Record<string, unknown>): JournalRecord {
    return {
      state: data["state"] as JournalState,
      decisionId: String(data["decisionId"] ?? ""),
      contentFingerprint: String(data["contentFingerprint"] ?? ""),
      analysis: data["analysis"] as StoredAnalysis | undefined,
      usage: data["usage"] as TokenUsage | undefined,
      failureCode: data["failureCode"] as string | undefined,
    };
  }

  async readJournal(requestId: string): Promise<JournalRecord | null> {
    const snap = await this.journalRef(requestId).get();
    if (!snap.exists) return null;
    return FirestoreAnalysisPorts.toRecord(snap.data()!);
  }

  /** create-if-absent: iki paralel çağrıdan YALNIZ biri `created` alır. */
  async reserve(params: {
    requestId: string;
    decisionId: string;
    contentFingerprint: string;
  }): Promise<{ created: boolean; record: JournalRecord }> {
    const ref = this.journalRef(params.requestId);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) {
        return {
          created: false,
          record: FirestoreAnalysisPorts.toRecord(snap.data()!),
        };
      }
      const record: JournalRecord = {
        state: JournalState.reserved,
        decisionId: params.decisionId,
        contentFingerprint: params.contentFingerprint,
      };
      tx.create(ref, {
        state: JournalState.reserved,
        decisionId: params.decisionId,
        contentFingerprint: params.contentFingerprint,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { created: true, record };
    });
  }

  /** reserved → provider_call_started; yarışta yalnız biri true alır. */
  async markProviderCallStarted(requestId: string): Promise<boolean> {
    const ref = this.journalRef(requestId);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const from = snap.data()!["state"] as JournalState;
      if (!canTransition(from, JournalState.providerCallStarted)) return false;
      tx.update(ref, {
        state: JournalState.providerCallStarted,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  async recordProviderSuccess(params: {
    requestId: string;
    analysis: StoredAnalysis;
    usage: TokenUsage;
  }): Promise<void> {
    const ref = this.journalRef(params.requestId);
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const from = snap.data()!["state"] as JournalState;
      if (!canTransition(from, JournalState.providerSucceeded)) return;
      tx.update(ref, {
        state: JournalState.providerSucceeded,
        analysis: params.analysis,
        usage: params.usage,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  /** İdempotent: izin verilmeyen geçişte sessizce hiçbir şey yapmaz. */
  async markOutcome(params: {
    requestId: string;
    state: JournalState;
    failureCode?: string;
  }): Promise<void> {
    const ref = this.journalRef(params.requestId);
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const from = snap.data()!["state"] as JournalState;
      if (!canTransition(from, params.state)) return;
      tx.update(ref, {
        state: params.state,
        ...(params.failureCode ? { failureCode: params.failureCode } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  /**
   * TEK transaction: journal→completed + karar fingerprint doğrulaması +
   * aiAnalyses/latest + status + kredi düşümü. Retry edilse bile kredi ve
   * sayaçlar İKİ KEZ uygulanmaz (journal durumu geçiş kapısıdır).
   */
  async finalize(params: {
    requestId: string;
    decisionId: string;
    expectedFingerprint: string;
    analysis: StoredAnalysis;
    initialCredits: number;
  }): Promise<{ outcome: "completed" | "superseded"; analysisId: string }> {
    const userRef = this.db.doc(`users/${this.uid}`);
    const decisionRef = this.decisionRef(params.decisionId);
    const analysisRef = decisionRef
      .collection("aiAnalyses")
      .doc(LATEST_ANALYSIS_ID);
    const journalRef = this.journalRef(params.requestId);

    return this.db.runTransaction(async (tx) => {
      const journal = await tx.get(journalRef);
      if (!journal.exists) {
        throw new AppError("internal", "Analiz üretilemedi, lütfen tekrar dene.");
      }
      const state = journal.data()!["state"] as JournalState;

      // Zaten uygulanmış: kredi/sayaç TEKRAR uygulanmaz.
      if (state === JournalState.completed) {
        return { outcome: "completed" as const, analysisId: LATEST_ANALYSIS_ID };
      }
      if (state === JournalState.superseded) {
        return { outcome: "superseded" as const, analysisId: LATEST_ANALYSIS_ID };
      }
      if (!canTransition(state, JournalState.completed)) {
        throw new AppError("internal", "Analiz üretilemedi, lütfen tekrar dene.");
      }

      // Karar analiz sürerken DEĞİŞTİ mi?
      const decision = await tx.get(decisionRef);
      if (!decision.exists) {
        tx.update(journalRef, {
          state: JournalState.superseded,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { outcome: "superseded" as const, analysisId: LATEST_ANALYSIS_ID };
      }
      const current = decision.data()!;
      const currentFingerprint = contentFingerprint({
        content: {
          title: current["title"],
          options: current["options"],
          criteria: current["criteria"],
        } as never,
        model: params.analysis.model,
        promptVersion: params.analysis.promptVersion,
      });
      if (currentFingerprint !== params.expectedFingerprint) {
        // ESKİ içerik için üretilen analiz YENİ karara BAĞLANMAZ ve
        // kullanıcı kredisi YANMAZ.
        tx.update(journalRef, {
          state: JournalState.superseded,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { outcome: "superseded" as const, analysisId: LATEST_ANALYSIS_ID };
      }

      const user = await tx.get(userRef);
      const data = user.data() ?? {};
      const plan = data["plan"] === "premium" ? "premium" : "free";

      if (plan !== "premium") {
        const pools = readPools(data, params.initialCredits);
        // Düşüm sırası (7A): önce ücretsiz, sonra ödül; her iki havuz da
        // > 0 şartıyla düşer → NEGATİF DEĞER İMKÂNSIZ.
        if (pools.free > 0) {
          tx.set(userRef, { freeAnalysisCredits: pools.free - 1 }, { merge: true });
        } else if (pools.reward > 0) {
          tx.set(userRef, { rewardCredits: pools.reward - 1 }, { merge: true });
        } else {
          throw new AppError("quota-exceeded", "Ücretsiz analiz hakkın bitti.", {
            remaining: 0,
            initial: params.initialCredits,
          });
        }
      }

      tx.set(analysisRef, {
        ...params.analysis,
        generatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(decisionRef, { status: "analyzed" });
      tx.update(journalRef, {
        state: JournalState.completed,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { outcome: "completed" as const, analysisId: LATEST_ANALYSIS_ID };
    });
  }

}

/**
 * Kredi havuzları (7A): freeAnalysisCredits lazy-init'li (yazılmamışsa
 * BAŞLANGIÇ), rewardCredits yazılmamışsa 0; bozuk/negatif veri 0'a kırpılır.
 * Saf fonksiyon — birim testli.
 */
export function readPools(
  data: Record<string, unknown>,
  initialFree: number = INITIAL_FREE_CREDITS,
): { free: number; reward: number } {
  const clamp = (value: unknown, fallback: number) =>
    typeof value === "number" ? Math.max(0, Math.trunc(value)) : fallback;
  return {
    free: clamp(data["freeAnalysisCredits"], initialFree),
    reward: clamp(data["rewardCredits"], 0),
  };
}
