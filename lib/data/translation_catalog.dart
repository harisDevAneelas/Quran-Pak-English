/// Built-in Quran translation options from `english_db.sqlite`.
///
/// [id] matches the column name on the `Quran` table.
library;

class TranslationOption {
  const TranslationOption({
    required this.id,
    required this.label,
    this.creditLabel,
  });

  final String id;

  /// Full name in the picker list.
  final String label;

  /// Person name under an ayah when credits are shown.
  /// Falls back to [label] when the picker name is already the person.
  final String? creditLabel;

  String get credit => creditLabel ?? label;
}

abstract final class TranslationCatalog {
  static const String defaultId = 'SaheehInternational';

  /// Sidebar order — all translations available in the app.
  static const List<TranslationOption> all = <TranslationOption>[
    TranslationOption(
      id: 'SaheehInternational',
      label: 'Saheeh International',
    ),
    TranslationOption(
      id: 'AbdullahYusufAli',
      label: 'Abdullah Yusuf Ali',
    ),
    TranslationOption(
      id: 'WilliamPickthall',
      label: 'Marmaduke Pickthall',
    ),
    TranslationOption(
      id: 'HilaliandMuhsinKhan',
      label: 'Hilali and Muhsin Khan',
    ),
    TranslationOption(
      id: 'AbulAlaMaududi',
      label: 'Abul Ala Maududi',
    ),
    TranslationOption(
      id: 'WahiduddinKhan',
      label: 'Wahiduddin Khan',
    ),
    TranslationOption(
      id: 'MohammadHabibShakir',
      label: 'Mohammad Habib Shakir',
    ),
    TranslationOption(
      id: 'MuhammadSarwar',
      label: 'Muhammad Sarwar',
    ),
    TranslationOption(
      id: 'TalalItani',
      label: 'Talal Itani',
    ),
    TranslationOption(
      id: 'AbdulMajidDaryabadi',
      label: 'Abdul Majid Daryabadi',
    ),
    TranslationOption(
      id: 'AJArberry',
      label: 'A. J. Arberry',
    ),
    TranslationOption(
      id: 'AhmedRazaKhan',
      label: 'Ahmed Raza Khan',
    ),
    TranslationOption(
      id: 'AhmedAli',
      label: 'Ahmed Ali',
    ),
    TranslationOption(
      id: 'AliQuliQarai',
      label: 'Ali Quli Qarai',
    ),
    TranslationOption(
      id: 'HasanQaribullahandAhmad',
      label: 'Hasan Qaribullah and Ahmad Darwish',
    ),
    TranslationOption(
      id: 'English',
      label: 'English',
    ),
    TranslationOption(
      id: 'Translit',
      label: 'Transliteration',
    ),
    TranslationOption(
      id: 'phonetic',
      label: 'Phonetic',
    ),
    TranslationOption(
      id: 'IbneAbbas',
      label: 'Ibn Abbas',
    ),
    TranslationOption(
      id: 'Jalalyn',
      label: 'Jalalayn',
    ),
  ];

  /// Tafsir-style columns, shown after the translation list.
  static const List<String> tafsirIds = <String>[
    'IbneAbbas',
    'Jalalyn',
  ];

  static bool isTafsir(String id) => tafsirIds.contains(resolveId(id));

  static TranslationOption get defaultOption => all.first;

  static const List<String> defaultIds = <String>[defaultId];

  static TranslationOption? byId(String id) {
    for (final option in all) {
      if (option.id == id) return option;
    }
    return null;
  }

  static TranslationOption? byLabel(String label) {
    for (final option in all) {
      if (option.label == label || option.credit == label) return option;
    }
    return null;
  }

  /// Resolves a stored settings value to a catalog id.
  ///
  /// An unknown id, including a saved Urdu translator, becomes [defaultId].
  static String resolveId(String? stored) {
    if (stored == null || stored.isEmpty) return defaultId;
    if (byId(stored) != null) return stored;
    return byLabel(stored)?.id ?? defaultId;
  }

  /// Normalizes a multi-select list. An empty saved list stays empty.
  static List<String> resolveIds(Iterable<String>? stored) {
    if (stored == null) return List<String>.from(defaultIds);
    final items = stored.toList();
    if (items.isEmpty) return <String>[];
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      if (raw.isEmpty) continue;
      final id = resolveId(raw);
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  static String labelFor(String id) =>
      byId(resolveId(id))?.label ?? defaultOption.label;

  static String creditFor(String id) =>
      byId(resolveId(id))?.credit ?? defaultOption.credit;

  /// English translations, tafsir, and transliteration are left to right.
  static bool isLtr(String id) => resolveId(id).isNotEmpty;

  static List<String> get labels =>
      [for (final option in all) option.label];
}
