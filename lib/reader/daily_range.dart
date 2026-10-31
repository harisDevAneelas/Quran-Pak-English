import '../core/surah_ayah_counts.dart';
import '../data/ayah_ref.dart';
import '../data/mushaf_divisions.dart';
import 'daily_plan.dart';

/// Resolves a saved [DailyPlan] into an inclusive ayah window for today's reading.
abstract final class DailyRangeResolver {
  static AyahWindow resolve(DailyPlan plan, MushafDivisions divisions) {
    final start = AyahRef(plan.startSurah, plan.startAyah).clampToSurah();
    final end = switch (plan.kind) {
      DailyPlanKind.ayah => _advanceAyahs(start, plan.amount.round()),
      DailyPlanKind.page =>
        _advanceUnits(start, plan.amount.round(), divisions.pageEnds),
      DailyPlanKind.ruku =>
        _advanceUnits(start, plan.amount.round(), divisions.rukuEnds),
      DailyPlanKind.para => _advanceParas(start, plan.amount, divisions),
    };
    if (end.absoluteIndex < start.absoluteIndex) {
      return AyahWindow(start: start, end: start);
    }
    return AyahWindow(start: start, end: end);
  }

  static AyahRef _advanceAyahs(AyahRef start, int count) {
    final n = count < 1 ? 1 : count;
    final endIdx = (start.absoluteIndex + n - 1).clamp(
      0,
      SurahAyahCounts.totalAyahs - 1,
    );
    return AyahRef.fromAbsolute(endIdx);
  }

  /// The unit that contains [start] counts as the first. The window ends on
  /// the last ayah of unit `first + count - 1`.
  static AyahRef _advanceUnits(AyahRef start, int count, List<AyahRef> ends) {
    if (ends.isEmpty) return start;
    final n = count < 1 ? 1 : count;
    final first = _indexContaining(start, ends);
    final last = (first + n - 1).clamp(0, ends.length - 1);
    return ends[last];
  }

  static AyahRef _advanceParas(
    AyahRef start,
    double amount,
    MushafDivisions divisions,
  ) {
    if (amount >= 1) {
      return _advanceUnits(start, amount.round(), divisions.paraEnds);
    }
    final sections = (amount * 4).round().clamp(1, 3);
    return _advanceUnits(start, sections, divisions.quarterEnds);
  }

  static int _indexContaining(AyahRef start, List<AyahRef> ends) {
    for (var i = 0; i < ends.length; i++) {
      if (start.absoluteIndex <= ends[i].absoluteIndex) return i;
    }
    return ends.length - 1;
  }

  /// Start of the next plan portion after [window] (wraps to 1:1 at the end).
  static AyahRef nextStartAfter(AyahWindow window) {
    final next = window.end.absoluteIndex + 1;
    if (next >= SurahAyahCounts.totalAyahs) return AyahRef.first;
    return AyahRef.fromAbsolute(next);
  }
}
