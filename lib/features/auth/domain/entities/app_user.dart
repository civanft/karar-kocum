/// Oturum kullanıcısı — saf domain (firebase_auth tipleri data'da kalır).
class AppUser {
  const AppUser({
    required this.uid,
    required this.isAnonymous,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  final String uid;
  final bool isAnonymous;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.isAnonymous == isAnonymous &&
      other.displayName == displayName &&
      other.email == email &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode =>
      Object.hash(uid, isAnonymous, displayName, email, photoUrl);
}
