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

/// Silme denetleyicisi. State = "silme sürüyor mu".
///
/// Guard BURADA: ekran butonu devre dışı bıraksa bile ikinci bir tetik
/// (ör. hızlı çift dokunuş) sunucuya ikinci istek göndermemeli.
class DeleteAccountController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Başarıda null, başarısızlıkta gösterilecek hatayı döner.
  /// Hata FIRLATMAZ: çağıran ekran her durumda spinner'ı kapatabilsin.
  Future<AccountDeletionFailure?> deleteAccount() async {
    if (state) return null; // zaten sürüyor
    state = true;
    try {
      await ref.read(deleteAccountProvider)();
      _refreshSessionScopedCaches();
      return null;
    } on AccountDeletionFailure catch (failure) {
      return failure;
    } catch (_) {
      // Beklenmedik istisna da ürün diline çevrilir; ham detay sızmaz.
      return const AccountDeletionFailure(
        kind: AccountDeletionFailureKind.retryable,
        message: 'Hesap silinemedi, birazdan tekrar dene.',
      );
    } finally {
      state = false;
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
