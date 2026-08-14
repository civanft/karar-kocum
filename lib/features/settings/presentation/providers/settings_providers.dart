import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../../journey/presentation/providers/journey_providers.dart';
import '../../../journey/presentation/providers/pending_check_in.dart';
import '../../../quota/presentation/providers/credits_providers.dart';
import '../../data/auth_account_session.dart';
import '../../data/firebase_account_deletion_client.dart';
import '../../data/journey_local_user_data_cleaner.dart';
import '../../domain/account_deletion.dart';
import '../../domain/delete_account.dart';

/// Silme portları — testlerde sahtelerle override edilir.
final accountDeletionClientProvider = Provider<AccountDeletionClient>(
  (_) => FirebaseAccountDeletionClient(FirebaseFunctions.instance),
);

final localUserDataCleanerProvider = Provider<LocalUserDataCleaner>(
  (ref) => JourneyLocalUserDataCleaner(
    preferences: ref.watch(followUpPreferencesProvider),
    scheduler: ref.watch(followUpSchedulerProvider),
  ),
);

final accountSessionProvider = Provider<AccountSession>(
  (ref) => AuthAccountSession(ref.watch(authRepositoryProvider)),
);

final deleteAccountProvider = Provider<DeleteAccount>(
  (ref) => DeleteAccount(
    client: ref.watch(accountDeletionClientProvider),
    cleaner: ref.watch(localUserDataCleanerProvider),
    session: ref.watch(accountSessionProvider),
  ),
);

/// Silme işleminin nihai raporu.
///
/// Hata ve "silindi ama oturum kurulamadı" AYRI durumlardır: ikincisi
/// başarıdır, yalnız kullanıcıya farklı mesaj gösterilir.
class DeleteAccountReport {
  const DeleteAccountReport.success(this.outcome) : failure = null;
  const DeleteAccountReport.failed(this.failure) : outcome = null;

  final AccountDeletionOutcome? outcome;
  final AccountDeletionFailure? failure;

  bool get succeeded => failure == null;
}

/// Silme denetleyicisi. State = "silme sürüyor mu".
///
/// Çift tetik AYNI Future'ı paylaşır: ikinci dokunuş ne yeni sunucu
/// isteği üretir ne de sahte bir başarı döndürür — birincinin gerçek
/// sonucunu bekler. Erken "null" dönmek, çağıranın bunu başarı sanıp
/// Home'a yönlendirmesine yol açardı.
class DeleteAccountController extends Notifier<bool> {
  Future<DeleteAccountReport>? _inFlight;

  @override
  bool build() => false;

  Future<DeleteAccountReport> deleteAccount() => _inFlight ??= _run();

  Future<DeleteAccountReport> _run() async {
    state = true;
    try {
      final outcome = await ref.read(deleteAccountProvider)();
      // Oturum kurulamamış olsa da eski hesabın verisi DÜŞÜRÜLÜR.
      _refreshSessionScopedCaches();
      return DeleteAccountReport.success(outcome);
    } on AccountDeletionFailure catch (failure) {
      return DeleteAccountReport.failed(failure);
    } catch (_) {
      // Beklenmedik istisna da ürün diline çevrilir; ham detay sızmaz.
      return const DeleteAccountReport.failed(
        AccountDeletionFailure(
          kind: AccountDeletionFailureKind.retryable,
          message: 'Hesap silinemedi, birazdan tekrar dene.',
        ),
      );
    } finally {
      state = false;
      _inFlight = null;
    }
  }

  /// Eski hesabın verisi yeni misafir oturumunda GÖRÜNMEMELİ.
  ///
  /// Depolar zaten uid'i izler (auth akışı yeni uid'i yayınca yeniden
  /// kurulurlar); burada ek olarak açıkça düşürülür ki yayın gecikse bile
  /// arada eski veri gösterilmesin.
  void _refreshSessionScopedCaches() {
    ref.invalidate(decisionRepositoryProvider);
    ref.invalidate(creditsRepositoryProvider);
    ref.invalidate(pendingCheckInProvider);
  }
}

final deleteAccountControllerProvider =
    NotifierProvider<DeleteAccountController, bool>(
  DeleteAccountController.new,
);
