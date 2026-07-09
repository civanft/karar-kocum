/**
 * AnalysisPorts üretim implementasyonu — sadeleştirilmiş MVP (6B):
 * aiAnalyses/latest SABİT belge, aiJobs yok, latestAnalysisId yok.
 * commitAnalysis TEK transaction: kredi yeniden doğrula + düş + analiz
 * + status — remaining > 0 şartıyla düşüm → NEGATİF DEĞER İMKÂNSIZ.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import {
  LATEST_ANALYSIS_ID,
  type AnalysisPorts,
  type CreditsSnapshot,
  type StoredAnalysis,
} from "./analyze_service.js";
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
    const raw = data["freeAnalysisCredits"];
    const remaining =
      typeof raw === "number"
        ? Math.max(0, Math.trunc(raw)) // bozuk/negatif veri savunması
        : INITIAL_FREE_CREDITS;
    return { plan, remaining };
  }

  async commitAnalysis(params: {
    decisionId: string;
    analysis: StoredAnalysis;
    initialCredits: number;
  }): Promise<string> {
    const userRef = this.db.doc(`users/${this.uid}`);
    const decisionRef = this.decisionRef(params.decisionId);
    const analysisRef = decisionRef
      .collection("aiAnalyses")
      .doc(LATEST_ANALYSIS_ID);

    await this.db.runTransaction(async (tx) => {
      const user = await tx.get(userRef);
      const data = user.data() ?? {};
      const plan = data["plan"] === "premium" ? "premium" : "free";

      if (plan !== "premium") {
        const raw = data["freeAnalysisCredits"];
        const remaining =
          typeof raw === "number"
            ? Math.max(0, Math.trunc(raw))
            : params.initialCredits; // ilk analiz: 5'ten başla

        // Yarış koruması: ön kontrolden sonra kredi bitmiş olabilir.
        if (remaining <= 0) {
          throw new AppError(
            "quota-exceeded",
            "Ücretsiz analiz hakkın bitti.",
            { remaining: 0, initial: params.initialCredits },
          );
        }
        tx.set(
          userRef,
          { freeAnalysisCredits: remaining - 1 },
          { merge: true },
        );
      }

      // Sabit kimlik: yeniden analiz üzerine yazar (geçmiş yok — 6B).
      tx.set(analysisRef, {
        ...params.analysis,
        generatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(decisionRef, { status: "analyzed" });
    });

    return LATEST_ANALYSIS_ID;
  }
}
