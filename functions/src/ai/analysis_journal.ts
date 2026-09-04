/**
 * Analiz istek journal'ı — idempotency ve kurtarma çekirdeği (İş Paketi 2).
 *
 * NEDEN: OpenAI Chat Completions için BELGELENMİŞ bir provider-side
 * idempotency garantisi yoktur ve Firestore ile OpenAI arasında tek bir
 * dağıtık transaction kurulamaz. Bu yüzden "exactly once external side
 * effect" İDDİA EDİLMEZ. Bunun yerine, sağlayıcı çağrısının ETRAFINA dayanıklı
 * bir journal konur: her adım kalıcı olarak işaretlenir, böylece aynı
 * requestId ile gelen retry sağlayıcıyı YENİDEN ÇAĞIRMADAN önceki sonucu
 * finalize edebilir.
 *
 * Yol: users/{uid}/analysisRequests/{requestId}
 * İstemci bu yola erişemez (rules default-deny; emulator testiyle kanıtlı).
 * Ham karar metni journal'a YAZILMAZ — yalnız fingerprint ve üretilen sonuç.
 */

export const ANALYSIS_REQUESTS_COLLECTION = "analysisRequests";

/** Journal durum makinesi. */
export enum JournalState {
  /** Kotalar/rezervasyonlar alındı, sağlayıcı henüz çağrılmadı. */
  reserved = "reserved",
  /** Sağlayıcı çağrısı BAŞLADI — sonucu bilinmiyor. */
  providerCallStarted = "provider_call_started",
  /** Sağlayıcı sonucu alındı ve dayanıklı olarak yazıldı. */
  providerSucceeded = "provider_succeeded",
  /** Karar yazıldı, kredi/sayaçlar finalize edildi. */
  completed = "completed",
  /** Karar analiz sürerken değişti; sonuç YENİ karara bağlanmaz. */
  superseded = "superseded",
  /** Kalıcı hata (moderasyon, şema, geçersiz istek). */
  terminalFailed = "terminal_failed",
  /**
   * Sağlayıcı çağrısının sonucu ÇÖZÜLEMEDİ (timeout/5xx/transport).
   * Bu requestId ile OTOMATİK ikinci sağlayıcı çağrısı YAPILMAZ; yeni bir
   * çağrı ancak YENİ kullanıcı eylemi + YENİ requestId ile başlar.
   */
  uncertain = "uncertain",
}

/** Her duruma hangi durumlardan geçilebileceği. Boş küme = başlangıç. */
const ALLOWED_PREVIOUS: Record<JournalState, readonly (JournalState | null)[]> = {
  [JournalState.reserved]: [null],
  [JournalState.providerCallStarted]: [JournalState.reserved],
  [JournalState.providerSucceeded]: [JournalState.providerCallStarted],
  [JournalState.completed]: [JournalState.providerSucceeded],
  [JournalState.superseded]: [
    JournalState.providerSucceeded,
    JournalState.providerCallStarted,
  ],
  [JournalState.terminalFailed]: [
    JournalState.reserved,
    JournalState.providerCallStarted,
    JournalState.providerSucceeded,
  ],
  [JournalState.uncertain]: [JournalState.providerCallStarted],
};

/** Bir daha değişmeyecek durumlar. */
const TERMINAL: readonly JournalState[] = [
  JournalState.completed,
  JournalState.superseded,
  JournalState.terminalFailed,
];

export function isTerminal(state: JournalState): boolean {
  return TERMINAL.includes(state);
}

export function canTransition(
  from: JournalState | null,
  to: JournalState,
): boolean {
  if (from !== null && isTerminal(from)) return false;
  return ALLOWED_PREVIOUS[to].includes(from);
}

/**
 * Aynı requestId ile gelen istek sağlayıcıyı yeniden çağırabilir mi?
 * `provider_call_started` sonrası ASLA: sonucu bilinmeyen bir çağrı ücretli
 * bir duplicate üretebilir.
 */
export function mayCallProvider(state: JournalState | null): boolean {
  return state === null || state === JournalState.reserved;
}

/** Aynı requestId retry'ı sağlayıcısız finalize edilebilir mi? */
export function canFinalizeWithoutProvider(state: JournalState | null): boolean {
  return state === JournalState.providerSucceeded;
}

/** Kayıt zaten uygulanmış bir sonucu mu taşıyor? */
export function isAlreadyApplied(state: JournalState | null): boolean {
  return state === JournalState.completed;
}
