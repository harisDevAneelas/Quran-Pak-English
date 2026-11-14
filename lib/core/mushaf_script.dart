/// Which mushaf script + face the reader paints.
enum MushafScript {
  /// IndoPak word text + KFGQPC Nastaleeq.
  indopak,

  /// Uthmani word text + DigitalKhatt V2.
  uthmani;

  static const MushafScript defaultScript = MushafScript.uthmani;

  static MushafScript fromName(String? name) {
    return switch (name) {
      'uthmani' => MushafScript.uthmani,
      'indopak' => MushafScript.indopak,
      _ => MushafScript.defaultScript,
    };
  }

  String get prefsName => name;

  String get label => switch (this) {
        MushafScript.indopak => 'IndoPak',
        MushafScript.uthmani => 'Uthmani',
      };

  String get coloredAssetPath => switch (this) {
        MushafScript.indopak => 'assets/data/quran.colored.json',
        MushafScript.uthmani => 'assets/data/quran.colored.uthmani.json',
      };

  String get fontFamily => switch (this) {
        MushafScript.indopak => 'KFGQPCNastaleeq',
        MushafScript.uthmani => 'DigitalKhattV2',
      };

  String get fontAssetKey => switch (this) {
        MushafScript.indopak =>
          'assets/fonts/KFGQPCNastaleeq-Regular.ttf',
        MushafScript.uthmani => 'assets/fonts/DigitalKhattV2.otf',
      };

  /// An-Nur 24:35 opening (Ayat-e-Noor) — orthography differs clearly.
  /// Used on the mushaf-script picker (not Bismillah, which looks similar).
  String get comparisonSample => switch (this) {
        MushafScript.indopak =>
          'اَللّٰهُ نُوْرُ السَّمٰوٰتِ وَالْاَرْضِ',
        MushafScript.uthmani =>
          'ٱللَّهُ نُورُ ٱلسَّمَـٰوَٰتِ وَٱلْأَرْضِ',
      };

  static const String comparisonSampleLabel = 'Ayat-e-Noor';

  static const List<MushafScript> pickerOrder = [
    MushafScript.uthmani,
    MushafScript.indopak,
  ];
}
