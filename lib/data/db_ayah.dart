/// Maps app mushaf ayah numbers to `english_db.sqlite` / CDN ayah numbers.
///
/// App Surah 1 has 6 ayahs (bismillah is a shared header). The DB and audio
/// CDN count بسم الله as Fatiha ayah 1, so app ayah N → DB/CDN ayah N+1.
abstract final class DbAyah {
  /// DB / CDN file ayah for an app [surah]:[ayah].
  static int of(int surah, int ayah) => surah == 1 ? ayah + 1 : ayah;

  /// App ayah for a DB [surah]:[dbAyah], or `null` if that DB row is the
  /// Fatiha bismillah (not an app ayah).
  static int? toApp(int surah, int dbAyah) {
    if (surah == 1) {
      if (dbAyah <= 1) return null;
      return dbAyah - 1;
    }
    return dbAyah;
  }
}
