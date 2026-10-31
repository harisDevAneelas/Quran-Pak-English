import 'reciter_catalog.dart';

/// Spoken translation pack hosted under `/quran/languages/{id}/`.
///
/// [id] is the CDN folder name. Flag lives at [imageAsset]
/// (`assets/flags/{id}.png`, or [AudioLanguageCatalog.dummyImageAsset]).
class AudioLanguageOption {
  const AudioLanguageOption({required this.id, required this.name});

  final String id;
  final String name;

  /// Bundled country flag for this language.
  String get imageAsset => AudioLanguageCatalog.imageAssetFor(id);
}

/// Ayah-level spoken translations from qurancompany.com.
///
/// [turkish] is omitted — it only has whole-surah files, not `SSSAAA.mp3`.
/// Off is controlled by the sidebar toggle, not a list row.
abstract final class AudioLanguageCatalog {
  static const noneId = 'none';
  static const defaultId = 'english';

  static const _base = 'https://qurancompany.com/quran/languages';

  static const imageAssetDir = 'assets/flags';
  static const dummyImageAsset = '$imageAssetDir/dummy.png';

  /// Flag path for [id] (`assets/flags/{id}.png`).
  static String imageAssetFor(String id) =>
      '$imageAssetDir/${resolveSelectableId(id)}.png';

  /// Selectable languages shown in spoken translation (no Off row).
  static const all = <AudioLanguageOption>[
    AudioLanguageOption(id: 'english', name: 'English'),
    AudioLanguageOption(id: 'english2', name: 'English 2'),
    AudioLanguageOption(id: 'urdu', name: 'Urdu'),
    AudioLanguageOption(id: 'urdu2', name: 'Urdu 2'),
    AudioLanguageOption(id: 'persian', name: 'Persian'),
    AudioLanguageOption(id: 'persian2', name: 'Persian 2'),
    AudioLanguageOption(id: 'azerbaijani', name: 'Azerbaijani'),
    AudioLanguageOption(id: 'bosnian', name: 'Bosnian'),
    AudioLanguageOption(id: 'chinese', name: 'Chinese'),
    AudioLanguageOption(id: 'dutch', name: 'Dutch'),
    AudioLanguageOption(id: 'french', name: 'French'),
    AudioLanguageOption(id: 'portuguese', name: 'Portuguese'),
    AudioLanguageOption(id: 'russian', name: 'Russian'),
    AudioLanguageOption(id: 'spanish', name: 'Spanish'),
    AudioLanguageOption(id: 'swedish', name: 'Swedish'),
    AudioLanguageOption(id: 'turkish2', name: 'Turkish 2'),
    AudioLanguageOption(id: 'turkish3', name: 'Turkish 3'),
  ];

  static List<String> get labels => [for (final o in all) o.name];

  static AudioLanguageOption byId(String id) {
    for (final o in all) {
      if (o.id == id) return o;
    }
    return all.first;
  }

  static String labelFor(String id) => byId(resolveSelectableId(id)).name;

  static bool isEnabled(String? id) {
    final resolved = resolveId(id);
    return resolved != noneId;
  }

  /// Playback id — may be [noneId] when spoken translation is off.
  static String resolveId(String? raw) {
    if (raw == null ||
        raw.isEmpty ||
        raw == noneId ||
        raw == 'Off' ||
        raw == 'بند') {
      return noneId;
    }
    for (final o in all) {
      if (o.id == raw || o.name == raw) return o.id;
    }
    return noneId;
  }

  /// Always a playable language (for prefs / picker).
  static String resolveSelectableId(String? raw) {
    final id = resolveId(raw);
    if (id == noneId) return defaultId;
    return id;
  }

  static String _url(String languageId, int surah, int fileAyahNo) {
    final s = surah.clamp(1, 114).toString().padLeft(3, '0');
    final a = fileAyahNo.clamp(1, 999).toString().padLeft(3, '0');
    return '$_base/$languageId/$s$a.mp3';
  }

  /// Fatiha 2nd verse only (`001002`) for list preview.
  static String previewUrl(String languageId) {
    final id = resolveSelectableId(languageId);
    return _url(id, 1, 2);
  }

  /// Spoken-translation MP3s for an app ayah (same Fatiha shift as reciters).
  static List<String> audioUrls({
    required String languageId,
    required int surah,
    required int ayah,
  }) {
    final id = resolveId(languageId);
    if (id == noneId) return const [];
    if (surah == 1 && ayah == 1) {
      return [_url(id, 1, 1), _url(id, 1, 2)];
    }
    return [_url(id, surah, ReciterCatalog.fileAyah(surah, ayah))];
  }
}
