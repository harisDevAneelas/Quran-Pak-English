/// How many times the current ayah audio should play before advancing.
enum AyahRepeatMode {
  /// Play once, then move to the next ayah.
  once,

  /// Play twice.
  twice,

  /// Play three times.
  thrice,

  /// Keep replaying the same ayah until the user skips or stops.
  unlimited;

  static const defaultMode = AyahRepeatMode.once;

  AyahRepeatMode get next => switch (this) {
        AyahRepeatMode.once => AyahRepeatMode.twice,
        AyahRepeatMode.twice => AyahRepeatMode.thrice,
        AyahRepeatMode.thrice => AyahRepeatMode.unlimited,
        AyahRepeatMode.unlimited => AyahRepeatMode.once,
      };

  /// Target play count, or `null` for unlimited.
  int? get playCount => switch (this) {
        AyahRepeatMode.once => 1,
        AyahRepeatMode.twice => 2,
        AyahRepeatMode.thrice => 3,
        AyahRepeatMode.unlimited => null,
      };

  /// Badge text shown in the center of the refresh button.
  String get badgeLabel => switch (this) {
        AyahRepeatMode.once => '1',
        AyahRepeatMode.twice => '2',
        AyahRepeatMode.thrice => '3',
        AyahRepeatMode.unlimited => '∞',
      };

  String get tooltip => switch (this) {
        AyahRepeatMode.once => 'Ayah once',
        AyahRepeatMode.twice => 'Ayah twice',
        AyahRepeatMode.thrice => 'Ayah three times',
        AyahRepeatMode.unlimited => 'Ayah without limit',
      };

  static AyahRepeatMode fromName(String? name) {
    for (final value in AyahRepeatMode.values) {
      if (value.name == name) return value;
    }
    return defaultMode;
  }
}
