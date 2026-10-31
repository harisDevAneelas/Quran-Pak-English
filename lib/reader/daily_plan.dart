import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'profile_scoped_prefs.dart';
import 'reminder_schedule.dart';

enum DailyPlanKind { ruku, ayah, para, page }

extension DailyPlanKindX on DailyPlanKind {
  String get question => switch (this) {
    DailyPlanKind.page => 'How many pages a day?',
    DailyPlanKind.para => 'How many paras a day?',
    DailyPlanKind.ayah => 'How many ayahs a day?',
    DailyPlanKind.ruku => 'How many rukus a day?',
  };

  double get defaultAmount => switch (this) {
    DailyPlanKind.page => 3,
    DailyPlanKind.para => 0.5,
    DailyPlanKind.ayah => 10,
    DailyPlanKind.ruku => 3,
  };

  int get minAmount => 1;

  int get maxAmount => switch (this) {
    DailyPlanKind.page => 30,
    DailyPlanKind.ayah => 50,
    DailyPlanKind.ruku => 20,
    DailyPlanKind.para => 3,
  };

  bool get usesFractionChips => this == DailyPlanKind.para;

  /// Picker and summary labels for a para-count amount.
  static String paraAmountLabel(double amount) => switch (amount) {
    0.25 => 'A quarter para',
    0.5 => 'Half a para',
    0.75 => 'Three quarters',
    1 => 'One para',
    2 => 'Two paras',
    3 => 'Three paras',
    _ => amount == amount.roundToDouble()
        ? '${amount.round()} paras'
        : '$amount paras',
  };

  static DailyPlanKind? fromName(String name) {
    for (final kind in DailyPlanKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

class DailyPlan {
  const DailyPlan({
    required this.kind,
    required this.amount,
    required this.startSurah,
    required this.startAyah,
    required this.reminderEnabled,
    required this.hour,
    required this.minute,
    required this.isPm,
  });

  final DailyPlanKind kind;

  final double amount;
  final int startSurah;
  final int startAyah;
  final bool reminderEnabled;
  final int hour;
  final int minute;
  final bool isPm;

  int get hour24 => hour12To24(hour, isPm);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'amount': amount,
    'startSurah': startSurah,
    'startAyah': startAyah,
    'reminderEnabled': reminderEnabled,
    'hour': hour,
    'minute': minute,
    'isPm': isPm,
  };

  factory DailyPlan.fromJson(Map<String, dynamic> json) {
    final kind =
        DailyPlanKindX.fromName(json['kind'] as String? ?? '') ??
        DailyPlanKind.page;
    return DailyPlan(
      kind: kind,
      amount: (json['amount'] as num?)?.toDouble() ?? kind.defaultAmount,
      startSurah: json['startSurah'] as int? ?? 1,
      startAyah: json['startAyah'] as int? ?? 1,
      reminderEnabled: json['reminderEnabled'] as bool? ?? true,
      hour: json['hour'] as int? ?? 5,
      minute: json['minute'] as int? ?? 0,
      isPm: json['isPm'] as bool? ?? true,
    );
  }

  DailyPlan copyWith({
    int? startSurah,
    int? startAyah,
  }) {
    return DailyPlan(
      kind: kind,
      amount: amount,
      startSurah: startSurah ?? this.startSurah,
      startAyah: startAyah ?? this.startAyah,
      reminderEnabled: reminderEnabled,
      hour: hour,
      minute: minute,
      isPm: isPm,
    );
  }
}

class DailyPlanStore {
  DailyPlanStore({required String profileId}) : _profileId = profileId;

  static const _baseKey = 'daily_recitation_plan_v1';
  static const _completedBaseKey = 'daily_recitation_completed_v1';

  String _profileId;

  String get profileId => _profileId;

  void bind(String profileId) {
    _profileId = profileId;
  }

  String get _key => ProfileScopedPrefs.key(_profileId, _baseKey);

  String get _completedKey =>
      ProfileScopedPrefs.key(_profileId, _completedBaseKey);

  Future<DailyPlan?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return DailyPlan.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(DailyPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(plan.toJson()));
  }

  Future<void> markCompletedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await prefs.setString(_completedKey, stamp);
  }
}
