/// How Arabic recitation and spoken translation are ordered for each ayah.
enum TilawatOrder {
  /// Recitation only.
  recitationOnly,

  /// Translation only.
  translationOnly,

  /// Recitation, then translation.
  recitationThenTranslation,

  /// Translation, then recitation.
  translationThenRecitation;

  static const defaultOrder = TilawatOrder.recitationThenTranslation;

  String get label => switch (this) {
        TilawatOrder.recitationOnly => 'Recitation only',
        TilawatOrder.translationOnly => 'Translation only',
        TilawatOrder.recitationThenTranslation => 'Recitation, then translation',
        TilawatOrder.translationThenRecitation => 'Translation, then recitation',
      };

  static TilawatOrder fromName(String? name) {
    for (final value in TilawatOrder.values) {
      if (value.name == name) return value;
    }
    return defaultOrder;
  }
}
