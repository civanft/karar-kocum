/** İstek bağlamı — her callable'da kurulur, tüm log/metriklere damgalanır. */
export interface RequestContext {
  /** Fonksiyon adı (metrik etiketi). */
  fn: string;
  /** İş kimliği — istek başına benzersiz; destek/iz sürme anahtarı. */
  jobId: string;
  /** SHA-256 kısaltılmış uid — ham uid loglara YAZILMAZ (PII ilkesi §9). */
  uidHash: string;
  /** Ham uid — yalnız Firestore yolları için; loglara geçmez. */
  uid: string;
  startedAtMs: number;
}
