/**
 * AnalysisPorts üretim implementasyonu — FIRESTORE-VERI-MODELI.md şemaları.
 * Kritik: commitAnalysis TEK transaction'dır — kota yeniden doğrulanır,
 * analiz + latestAnalysisId + status + kota artışı ya hep ya hiç (§8.2).
 */
import {
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import type {
  AnalysisPorts,
  CreditsSnapshot,
  StoredAnalysis,
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

  async findCachedAnalysis(
    decisionId: string,
    inputHash: string,
  ): Promise<StoredAnalysis | null> {
    const query = await this.decisionRef(decisionId)
      .collection("aiAnalyses")
      .where("inputHash", "==", inputHash)
      .limit(1)
      .get();
    const doc = query.docs[0];
    if (!doc) return null;
    return { id: doc.id, ...(doc.data() as Omit<StoredAnalysis, "id">) };
  }

  /** Kredi okuma — alan hiç yazılmamışsa BAŞLANGIÇ değeri kabul edilir
   *  (sunucu lazy-init: istemcinin krediyi yazma ihtiyacı/yetkisi yok). */
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
    analysis: Omit<StoredAnalysis, "id">;
    initialCredits: number;
  }): Promise<string> {
    const userRef = this.db.doc(`users/${this.uid}`);
    const decisionRef = this.decisionRef(params.decisionId);
    const analysisRef = decisionRef.collection("aiAnalyses").doc();

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
        // remaining > 0 şartıyla düşüldüğünden NEGATİF DEĞER İMKÂNSIZ.
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

      tx.set(analysisRef, {
        ...params.analysis,
        generatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(decisionRef, {
        latestAnalysisId: analysisRef.id,
        status: "analyzed",
      });
    });

    return analysisRef.id;
  }

  async writeJob(
    job: Parameters<AnalysisPorts["writeJob"]>[0],
  ): Promise<void> {
    await this.db.collection("aiJobs").add({
      uid: this.uid,
      ...job,
      createdAt: Timestamp.now(),
    });
  }
}
