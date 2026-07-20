import 'package:shared_preferences/shared_preferences.dart';

import '../domain/follow_up_preferences.dart';

/// Yerel (cihaz) takip tercihi deposu — Firestore'a DOKUNMAZ.
/// Söz verilen karar kimlikleri tek bir string listesinde tutulur;
/// tipik kullanıcıda onlarca öğe olur, boyut önemsizdir.
class PrefsFollowUpPreferences implements FollowUpPreferences {
  const PrefsFollowUpPreferences();

  static const _key = 'journey.followUpOptedIn';

  @override
  Future<bool> isOptedIn(String decisionId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).contains(decisionId);
  }

  @override
  Future<void> setOptedIn(String decisionId, {required bool value}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = [...(prefs.getStringList(_key) ?? const <String>[])];
    if (value) {
      if (!current.contains(decisionId)) current.add(decisionId);
    } else {
      current.remove(decisionId);
    }
    await prefs.setStringList(_key, current);
  }
}

/// Testler ve yerel mod için bellek içi uygulama.
class InMemoryFollowUpPreferences implements FollowUpPreferences {
  final _optedIn = <String>{};

  @override
  Future<bool> isOptedIn(String decisionId) async =>
      _optedIn.contains(decisionId);

  @override
  Future<void> setOptedIn(String decisionId, {required bool value}) async {
    value ? _optedIn.add(decisionId) : _optedIn.remove(decisionId);
  }
}
