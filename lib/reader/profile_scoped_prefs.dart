/// Namespaces SharedPreferences keys by profile id: `p:{id}:{base}`.
abstract final class ProfileScopedPrefs {
  static String key(String profileId, String base) => 'p:$profileId:$base';

  static String prefix(String profileId) => 'p:$profileId:';
}
