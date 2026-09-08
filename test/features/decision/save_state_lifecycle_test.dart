import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

/// İŞ PAKETİ 4 — KAYIT DURUMU YAŞAM DÖNGÜSÜ.
///
/// Kayıt durumu karar bazındaydı ve HİÇ temizlenmiyordu: oturum boyunca
/// açılan her karar kalıcı bir aile elemanı bırakıyordu (sınırsız birikim).
/// Burada sınırın gerçekten var olduğu kanıtlanır — ve bunu yaparken
/// `autoDispose`'a YAZMA yasağı korunur (dispose zamanlayıcısı regresyonu).
class _Repo implements DecisionRepository {
  _Repo();
  bool failPatch = false;
  int patchCalls = 0;
  final List<DecisionPatch> patches = <DecisionPatch>[];

  /// Doluyken yazım BLOKE olur — eşzamanlılık gözlemlenebilsin.
  Completer<void>? gate;
  final Map<String, Decision> _byId = {};

  Decision _seed(String id) => _byId.putIfAbsent(
        id,
        () => Decision(
          id: id,
          ownerUid: 'u1',
          title: 'K-$id',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

  @override
  Future<Decision?> getById(String id) async => _seed(id);

  @override
  Stream<Decision?> watchById(String id) => const Stream.empty();

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async {
    patchCalls++;
    patches.add(patch);
    if (gate != null) await gate!.future;
    if (failPatch) throw StateError('offline');
    _byId[id] = _seed(id).copyWith(updatedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Repo repo;
  late ProviderContainer container;
  late SaveStateRegistry registry;

  setUp(() {
    repo = _Repo();
    container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(repo),
        autosaveDebounceProvider.overrideWithValue(const Duration(minutes: 5)),
      ],
    );
    registry = container.read(saveStateRegistryProvider);
  });
  tearDown(() => container.dispose());

  Future<ProviderSubscription<AsyncValue<Decision>>> open(String id) async {
    final sub = container.listen(decisionEditorProvider(id), (_, __) {});
    await container.read(decisionEditorProvider(id).future);
    return sub;
  }

  /// Editörün gerçekten dispose olmasını bekler (autoDispose sonraki tura).
  Future<void> close(
    ProviderSubscription<AsyncValue<Decision>> sub,
  ) async {
    sub.close();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('1. IDLE durum SAKLANMAZ — birikim kaynağı kapalı', () async {
    expect(registry.trackedCount, 0);
    registry.write('d1', const SaveIdle());
    expect(registry.trackedCount, 0);
    expect(registry.stateOf('d1'), isA<SaveIdle>());
  });

  test('2. BAŞARILI yazımdan sonra girdi SİLİNİR', () async {
    final sub = await open('d1');
    await container
        .read(decisionEditorProvider('d1').notifier)
        .toggleFavorite();
    expect(container.read(decisionSaveStateProvider('d1')), isA<SaveIdle>());
    expect(registry.trackedCount, 0);
    await close(sub);
  });

  test('3. BAŞARISIZ yazımda girdi KORUNUR (niyet silinmez)', () async {
    final sub = await open('d1');
    repo.failPatch = true;
    await container
        .read(decisionEditorProvider('d1').notifier)
        .toggleFavorite();

    expect(container.read(decisionSaveStateProvider('d1')), isA<SaveFailed>());
    expect(registry.trackedCount, 1);
    await close(sub);
  });

  test('4. TEMİZ kapanışta (bekleyen/uçuşta iş yok) girdi TEMİZLENİR',
      () async {
    final sub = await open('d1');
    repo.failPatch = true;
    await container
        .read(decisionEditorProvider('d1').notifier)
        .toggleFavorite();
    expect(registry.trackedCount, 1);

    repo.failPatch = false;
    await container.read(decisionEditorProvider('d1').notifier).retrySave();
    expect(registry.trackedCount, 0);

    await close(sub);
    expect(registry.trackedCount, 0);
  });

  test('5. dispose yolundaki SON yazım bitince girdi temizlenir', () async {
    final sub = await open('d1');
    // Debounce 5 dk: yazım gönderilmemiş, niyet bekliyor.
    container
        .read(decisionEditorProvider('d1').notifier)
        .setScore('o1', 'c1', 4);

    await close(sub);
    await Future<void>.delayed(Duration.zero);

    expect(registry.trackedCount, 0);
  });

  test('6. dispose SONRASI gelen hata defterde girdi BIRAKMAZ', () async {
    final sub = await open('d1');
    repo.failPatch = true;
    // Yazım UÇUŞTAYKEN editör kapanır: hata dispose'dan SONRA gelir.
    final pending =
        container.read(decisionEditorProvider('d1').notifier).toggleFavorite();
    await close(sub);
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(
      registry.trackedCount,
      0,
      reason: 'ölü editörün durumu defterde kalamaz',
    );
  });

  test('7. 20 karar açılıp kapanınca kayıt defteri BÜYÜMEZ', () async {
    for (var i = 0; i < 20; i++) {
      final id = 'd$i';
      final sub = await open(id);
      await container
          .read(decisionEditorProvider(id).notifier)
          .toggleFavorite();
      await close(sub);
    }
    expect(registry.trackedCount, 0);
  });

  test('8. decisionSaveStateProvider kayıt defterini YANSITIR', () async {
    final sub = container.listen(decisionSaveStateProvider('d1'), (_, __) {});
    addTearDown(sub.close);
    expect(container.read(decisionSaveStateProvider('d1')), isA<SaveIdle>());

    registry.write('d1', const SaveFailed('x'));
    expect(container.read(decisionSaveStateProvider('d1')), isA<SaveFailed>());

    registry.write('d1', const SaveIdle());
    expect(container.read(decisionSaveStateProvider('d1')), isA<SaveIdle>());
  });

  test('9. UÇUŞTAKİ yazım sürerken ikinci flush İKİNCİ yazım açmaz', () async {
    final sub = await open('d1');
    addTearDown(() => sub.close());

    final editor = container.read(decisionEditorProvider('d1').notifier);
    repo.gate = Completer<void>();

    editor.setScore('o1', 'c1', 3);
    final first = editor.flushPendingWrites();
    await Future<void>.delayed(Duration.zero);
    expect(repo.patchCalls, 1);

    // Uçuştaki yazım sürerken YENİ niyet ve ikinci flush.
    editor.setScore('o1', 'c1', 5);
    final second = editor.flushPendingWrites();
    await Future<void>.delayed(Duration.zero);
    expect(
      repo.patchCalls,
      1,
      reason: 'eşzamanlı ikinci yazım sıralamayı bozardı',
    );

    repo.gate!.complete();
    await first;
    await second;
    expect(repo.patchCalls, 1);
  });

  test('10. BAŞARISIZ flush sonrası AYNI niyet yeniden yazılır', () async {
    final sub = await open('d1');
    addTearDown(() => sub.close());
    final editor = container.read(decisionEditorProvider('d1').notifier);

    repo.failPatch = true;
    editor.setScore('o1', 'c1', 4);
    await editor.flushPendingWrites();
    expect(container.read(decisionSaveStateProvider('d1')), isA<SaveFailed>());
    expect(repo.patchCalls, 1);

    repo.failPatch = false;
    await editor.retrySave();

    expect(repo.patchCalls, 2, reason: 'niyet kuyrukta kalmamış');
    expect(repo.patches.last.scores?['o1']?['c1']?.value, 4);
    expect(container.read(decisionSaveStateProvider('d1')), isA<SaveIdle>());
  });

  test('11. kayıt defteri KARARLARI KARIŞTIRMAZ', () async {
    registry.write('d1', const SaveFailed('x'));
    expect(registry.stateOf('d1'), isA<SaveFailed>());
    expect(registry.stateOf('d2'), isA<SaveIdle>());
    expect(registry.trackedCount, 1);
  });
}
