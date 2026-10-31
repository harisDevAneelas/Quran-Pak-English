/// Bundled azaan voices for namaz-start notifications and in-app preview.
class AzaanOption {
  const AzaanOption({
    required this.id,
    required this.name,
    required this.assetFile,
    required this.androidRawName,
    required this.iosSoundFile,
  });

  /// Stable prefs / channel id (matches asset basename without extension).
  final String id;
  final String name;

  /// Flutter asset under `assets/azan-audio/`.
  final String assetFile;

  /// Android `res/raw` name without extension (underscores only).
  final String androidRawName;

  /// Filename copied into the iOS Runner bundle.
  final String iosSoundFile;

  String get assetPath => 'assets/azan-audio/$assetFile';
}

abstract final class AzaanCatalog {
  static const defaultId = 'muhammad-ramadan-saad';

  static const all = <AzaanOption>[
    AzaanOption(
      id: 'mishary-rashid-alafasy',
      name: 'Mishary Rashid Alafasy',
      assetFile: 'mishary-rashid-alafasy.mp3',
      androidRawName: 'mishary_rashid_alafasy',
      iosSoundFile: 'mishary-rashid-alafasy.mp3',
    ),
    AzaanOption(
      id: 'muhammad-ramadan-saad',
      name: 'Muhammad Ramadan Saad',
      assetFile: 'muhammad-ramadan-saad.mp3',
      androidRawName: 'muhammad_ramadan_saad',
      iosSoundFile: 'muhammad-ramadan-saad.mp3',
    ),
    AzaanOption(
      id: 'ali-ibn-ahmad-mala',
      name: 'Ali ibn Ahmad Mala',
      assetFile: 'ali-ibn-ahmad-mala.mp3',
      androidRawName: 'ali_ibn_ahmad_mala',
      iosSoundFile: 'ali-ibn-ahmad-mala.mp3',
    ),
  ];

  static AzaanOption byId(String? id) {
    final resolved = resolveId(id);
    for (final o in all) {
      if (o.id == resolved) return o;
    }
    return all.firstWhere((o) => o.id == defaultId);
  }

  static String labelFor(String? id) => byId(id).name;

  static String resolveId(String? raw) {
    if (raw == null || raw.isEmpty) return defaultId;
    for (final o in all) {
      if (o.id == raw || o.name == raw) return o.id;
    }
    return defaultId;
  }
}
