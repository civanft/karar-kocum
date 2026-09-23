import 'dart:async';

import 'package:flutter/material.dart';

import '../config/firebase_bootstrap.dart';
import '../theme/app_theme.dart';

/// Release başlangıç kapısı (PR-RELEASE-1).
///
/// [FirebaseStatus.unavailable] altında gerçek uygulama ağacı HİÇ kurulmaz:
/// router açılmaz, Home görünmez, hiçbir sahte karar/kredi/analiz üretilmez.
/// `ready` ve `localMode` yollarında davranış değişmez — geliştirme ve test
/// akışları aynen çalışır.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.initialStatus,
    required this.retry,
    required this.appBuilder,
  });

  final FirebaseStatus initialStatus;

  /// Yeniden başlatma denemesi.
  ///
  /// SÖZLEŞME: idempotent **ve SINIRLI** olmalıdır. Zaman aşımı artık
  /// gate'in işi DEĞİLDİR — sınırı `FirebaseBootstrap` koyar
  /// (`waitForFirebaseStartup`). Gate ikinci bir `.timeout()` katmanı
  /// uygulasaydı iki sınır üst üste biner, içteki DEĞER döndürdüğü için
  /// dıştaki hiç tetiklenmez ve release dışında yanlış duruma düşerdi.
  final Future<FirebaseStatus> Function() retry;

  /// Yalnız bağlantı sağlandığında çağrılır.
  final WidgetBuilder appBuilder;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late FirebaseStatus _status = widget.initialStatus;
  bool _retrying = false;

  /// Zaman aşımına uğramış denemenin GEÇ tamamlanması UI'ı değiştirmemeli.
  int _attempt = 0;

  @override
  void didUpdateWidget(StartupGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Üst katman yeni bir durum verdiyse gate ESKİ değerde takılı kalmaz.
    if (widget.initialStatus != oldWidget.initialStatus) {
      setState(() => _status = widget.initialStatus);
    }
  }

  Future<void> _onRetry() async {
    // Guard: spinner sürerken ikinci dokunuş ikinci başlatma başlatmasın.
    if (_retrying) return;
    final attempt = ++_attempt;
    setState(() => _retrying = true);
    FirebaseStatus next;
    try {
      // Sınırı `retry` kendisi koyar (bkz. [StartupGate.retry] sözleşmesi).
      // Geç tamamlanan bir sonuç `attempt` kontrolüyle yok sayılır.
      next = await widget.retry();
    } catch (_) {
      // Retry'ın kendisi patlarsa da ekran kilitlenmez; ham hata GÖSTERİLMEZ.
      next = FirebaseStatus.unavailable;
    }
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _status = next;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_status != FirebaseStatus.unavailable) {
      // NESTED MaterialApp YOK: uygulamanın kendi kökünü kuruyor.
      return widget.appBuilder(context);
    }
    // Bu dal PRODUCTION KÖKÜDÜR: yukarıda MaterialApp/Directionality yoktur,
    // bu yüzden kendi Material bağlamını kendisi kurar (P0, PR-RELEASE-1A).
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: _UnavailableScreen(busy: _retrying, onRetry: _onRetry),
    );
  }
}

/// Sahte veri İÇERMEZ: karar listesi, kredi sayacı ya da AI CTA yoktur.
class _UnavailableScreen extends StatelessWidget {
  const _UnavailableScreen({required this.busy, required this.onRetry});

  final bool busy;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                // Bu ekran, açılışta sessizce belirir: ekran okuyucunun
                // durumu duyurabilmesi için başlık hem BAŞLIK hem CANLI
                // BÖLGE olarak işaretlenir.
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    'Karar Koçum\'a bağlanılamadı',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bağlantını kontrol edip tekrar deneyebilirsin. '
                  'Kararların bu sırada değişmedi.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  // null → hem görsel hem davranışsal olarak kapalı.
                  onPressed: busy ? null : () => unawaited(onRetry()),
                  child: busy
                      // Meşgulken düğmenin metni yoktur; etiket olmazsa
                      // ekran okuyucu hiçbir şey okumaz ve kullanıcı ekranın
                      // donduğunu sanar.
                      ? Semantics(
                          label: 'Yeniden deneniyor',
                          liveRegion: true,
                          excludeSemantics: true,
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
