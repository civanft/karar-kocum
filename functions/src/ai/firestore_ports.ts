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
  QuotaSnapshot,
  StoredAnalysis,
} from "./analyze_service.js";

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

  async peekQuota(currentMonth: string): Promise<QuotaSnapshot> {
    const user = await this.db.doc(`users/${this.uid}`).get();
    const data = user.data() ?? {};
    const plan = data["plan"] === "premium" ? "premium" : "free";
    const quota = data["quota"] as { month?: string; used?: number } | undefined;
    // Lazy aylık sıfırlama (§5.1 fonksiyon envanteri notu):
    const used = quota?.month === currentMonth ? (quota.used ?? 0) : 0;
    return { plan, month: currentMonth, used };
  }

  async commitAnalysis(params: {
    decisionId: string;
    analysis: Omit<StoredAnalysis, "id">;
    currentMonth: string;
    freeQuotaLimit: number;
  }): Promise<string> {
    const userRef = this.db.doc(`users/${this.uid}`);
    const decisionRef = this.decisionRef(params.decisionId);
    const analysisRef = decisionRef.collection("aiAnalyses").doc();

    await this.db.runTransaction(async (tx) => {
      const user = await tx.get(userRef);
      const data = user.data() ?? {};
      const plan = data["plan"] === "premium" ? "premium" : "free";
      const quota = data["quota"] as
        | { month?: string; used?: number }
        | undefined;
      const used =
        quota?.month === params.currentMonth ? (quota.used ?? 0) : 0;

      // Yarış koruması: ön kontrolden sonra kota dolmuş olabilir.
      if (plan === "free" && used >= params.freeQuotaLimit) {
        throw new AppError("quota-exceeded", "Aylık analiz hakkın doldu.", {
          limit: params.freeQuotaLimit,
        });
      }

      tx.set(analysisRef, {
        ...params.analysis,
        generatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(decisionRef, {
        latestAnalysisId: analysisRef.id,
        status: "analyzed",
      });
      tx.set(
        userRef,
        { quota: { month: params.currentMonth, used: used + 1 } },
        { merge: true },
      );
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
