import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'decision_editor.dart';

/// Puanlama ilerlemesi (PR-A3) — SPRINT-A §1.3.
///
/// Hiçbir veri persist edilmez; her şey decision.scores'tan türetilir.
/// PERFORMANSIN KENDİSİ `select`: slider sürüklemede her tick editör
/// state'i üretir; select record'u yalnız SAYI değişince yeni değer
/// bildirir (aynı hücrede 6→7 = sıfır rebuild).
typedef ScoringProgress = ({int filled, int total});

final scoringProgressProvider =
    Provider.autoDispose.family<ScoringProgress, String>(
  (ref, decisionId) => ref.watch(
    decisionEditorProvider(decisionId).select((async) {
      final decision = async.valueOrNull;
      return decision == null
          ? (filled: 0, total: 0)
          : (
              filled: decision.filledScoreCells,
              total: decision.totalScoreCells,
            );
    }),
  ),
);
