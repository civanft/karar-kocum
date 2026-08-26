import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/legal_links.dart';
import 'package:karar_veriyorum/core/services/external_link_launcher.dart';

/// PR-LEGAL-1 — dış bağlantı adapter'ı.
///
/// Adapter allowlist'i kendi içinde uygular: çağıran taraf yanlış bir URL
/// geçse bile platform kanalına hiçbir şey gitmez.
void main() {
  test('allowlist dışı URL platform kanalına HİÇ gitmez', () async {
    final probe = <String>[];
    final launcher = AllowlistedLinkLauncher(
      openUrl: (uri) async {
        probe.add(uri.toString());
        return true;
      },
    );

    final ok = await launcher.open('https://evil.example.com/privacy');

    expect(ok, isFalse);
    expect(probe, isEmpty, reason: 'engellenen URL yine de açılmış');
  });

  test('allowlist içi URL harici uygulamada açılır', () async {
    final probe = <String>[];
    final launcher = AllowlistedLinkLauncher(
      openUrl: (uri) async {
        probe.add(uri.toString());
        return true;
      },
    );

    final ok = await launcher.open(LegalLinks.privacy);

    expect(ok, isTrue);
    expect(probe, [LegalLinks.privacy]);
  });

  test('platform false dönerse sonuç false (sessiz başarı yok)', () async {
    final launcher = AllowlistedLinkLauncher(openUrl: (_) async => false);
    expect(await launcher.open(LegalLinks.terms), isFalse);
  });

  test('platform fırlatırsa hata yutulur, false döner', () async {
    final launcher = AllowlistedLinkLauncher(
      openUrl: (_) async => throw Exception('kanal yok'),
    );
    expect(await launcher.open(LegalLinks.support), isFalse);
  });
}
