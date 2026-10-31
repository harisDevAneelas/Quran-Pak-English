/// Whether the floating playing-ayah bar should be on screen.
bool shouldShowPlayingAyahBar({
  required bool audioActive,
  required bool pageAboveHome,
  required bool playingAyahOnScreen,
}) {
  if (!audioActive) return false;
  return pageAboveHome || !playingAyahOnScreen;
}

/// Surah caption for the chip (`سورۃ البقرة`).
String playingSurahCaption(String name) {
  final trimmed = name.trim();
  if (trimmed.startsWith('سورۃ') || trimmed.startsWith('سورة')) {
    return trimmed;
  }
  return trimmed.isEmpty ? 'سورۃ' : 'سورۃ $trimmed';
}

/// Ayah caption for the chip (`Ayah 46`).
String playingAyahCaption(int ayah) => 'Ayah $ayah';

/// Gap above the safe area, plus any visible bottom chrome (transport / prompt).
double playingAyahBarLift({
  required double safeBottom,
  required double gap,
  required double chromeHeight,
}) {
  if (chromeHeight <= 0) return safeBottom + gap;
  return chromeHeight + safeBottom + gap;
}

/// Empty space so the last ayah is not hidden under the chip.
double playingAyahBarListReserve({
  required bool audioActive,
  required double barHeight,
  required double gap,
}) {
  if (!audioActive) return 0;
  return barHeight + gap;
}

/// Whether the mushaf should scroll to each ayah as it starts.
bool shouldFollowPlayingAyah({
  required bool followDetached,
  required bool pageAboveHome,
}) {
  return !followDetached && !pageAboveHome;
}
