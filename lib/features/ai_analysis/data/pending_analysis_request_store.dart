import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/analysis_request_id.dart';
import '../domain/pending_analysis_request.dart';

export '../domain/pending_analysis_request.dart';

/// [PendingAnalysisRequestStore]'un SharedPreferences uygulaması.
///
/// Neden kalıcı: uygulama süreci analiz sürerken kesilirse, kullanıcı geri
/// döndüğünde AYNI requestId ile devam edebilmeli — böylece sunucudaki
/// journal kaydı sağlayıcı çağrısı YAPILMADAN finalize edilir.
///
/// Saklanan tek şey idempotency anahtarıdır; karar içeriği saklanmaz.
class PrefsPendingAnalysisRequestStore implements PendingAnalysisRequestStore {
  /// [prefs] verilmezse örnek tembel çözülür (mevcut journey deseni).
  const PrefsPendingAnalysisRequestStore([this._injected]);

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _resolve async =>
      _injected ?? await SharedPreferences.getInstance();

  static final RegExp _canonical =
      RegExp('^[a-z0-9]{$analysisRequestIdLength}\$');

  /// Tüm bekleyen istek anahtarlarının ortak öneki — clearAll bunu kullanır
  /// ve ilgisiz tercihlere DOKUNMAZ.
  static const String _prefix = 'ai.pendingRequest.';

  @override
  Future<String?> read({
    required String uid,
    required String decisionId,
  }) async {
    final prefs = await _resolve;
    final value = prefs.getString(
      pendingRequestKey(uid: uid, decisionId: decisionId),
    );
    // Bozuk/biçimsiz kayıt sunucuya gönderilmez: yok sayılır.
    if (value == null || !_canonical.hasMatch(value)) return null;
    return value;
  }

  @override
  Future<void> write({
    required String uid,
    required String decisionId,
    required String requestId,
  }) async {
    final prefs = await _resolve;
    await prefs.setString(
      pendingRequestKey(uid: uid, decisionId: decisionId),
      requestId,
    );
  }

  @override
  Future<void> clear({
    required String uid,
    required String decisionId,
  }) async {
    final prefs = await _resolve;
    await prefs.remove(pendingRequestKey(uid: uid, decisionId: decisionId));
  }

  @override
  Future<void> clearAll() async {
    final prefs = await _resolve;
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

/// Testlerde override edilebilir bağlama noktası.
final pendingAnalysisRequestStoreProvider =
    Provider<PendingAnalysisRequestStore>(
  (_) => const PrefsPendingAnalysisRequestStore(),
);
