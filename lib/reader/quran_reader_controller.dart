import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/mushaf_layout.dart';
import '../data/ayah_ref.dart';
import '../data/quran_models.dart';
import '../data/quran_repository.dart';
import 'reading_position_store.dart';

enum QuranLoadState { idle, loading, ready, error }

/// Owns mushaf load lifecycle and semantic reading position.
///
/// Fast path: absorb a small window into [_ayahs] and show the reader using
/// stable [MushafLayout] indices. Background: parse the full JSON and absorb
/// it into the same map — list indices do not change, so there is no swap jerk.
class QuranReaderController extends ChangeNotifier {
  QuranReaderController({
    QuranDataRepository? repository,
    required ReadingPositionStore positionStore,
  }) : _repository = repository ?? QuranDataRepository(),
       _positionStore = positionStore;

  final QuranDataRepository _repository;
  final ReadingPositionStore _positionStore;

  static const int ayahsPerScreen = 10;
  static const int screenRadius = 5;
  static const Duration _positionSaveDebounce = Duration(milliseconds: 400);

  static const AyahWindow firstLaunchWindow = AyahWindow(
    start: AyahRef.first,
    end: AyahRef(2, 50),
  );

  static int get windowRadiusAyahs => ayahsPerScreen * screenRadius;

  QuranLoadState _state = QuranLoadState.idle;
  Object? _error;
  AyahRef _initialOpenAt = AyahRef.first;
  bool _openAtSurahHeader = true;
  bool _fullyLoaded = false;
  bool _fullLoadStarted = false;

  /// True while the mushaf list is scrolling / flinging.
  bool _scrollActive = false;

  /// Background content landed during a fling — notify after scroll ends.
  bool _pendingContentNotify = false;

  Timer? _positionSaveTimer;
  ({int surah, int ayah})? _pendingPositionSave;

  /// Parsed ayahs keyed by `"surah:ayah"`. Grows as windows / full load arrive.
  final Map<String, QuranAyahChunk> _ayahs = {};

  final ValueNotifier<({int surah, int ayah})> positionListenable =
      ValueNotifier((surah: 1, ayah: 1));

  QuranLoadState get state => _state;
  Object? get error => _error;
  int get currentSurah => positionListenable.value.surah;
  int get currentAyah => positionListenable.value.ayah;
  AyahRef get initialOpenAt => _initialOpenAt;
  bool get isFullyLoaded => _fullyLoaded;
  int get itemCount => MushafLayout.itemCount;
  QuranAyahChunk? get bismillah => _repository.bismillah;

  /// List index for the first frame (header on cold start, ayah on resume).
  int get initialScrollIndex {
    if (_openAtSurahHeader) {
      return itemIndexForSurah(_initialOpenAt.surah);
    }
    return itemIndexForAyah(_initialOpenAt.surah, _initialOpenAt.ayah);
  }

  ({int surah, int ayah}) get readingPosition => positionListenable.value;

  QuranAyahChunk? ayahAt(int surah, int ayah) => _ayahs['$surah:$ayah'];

  bool hasAyah(int surah, int ayah) => _ayahs.containsKey('$surah:$ayah');

  Future<void> initialize() async {
    if (_state == QuranLoadState.loading) return;
    if (_state == QuranLoadState.ready && _ayahs.isNotEmpty) return;

    _state = QuranLoadState.loading;
    _error = null;
    notifyListeners();

    try {
      final saved = await _positionStore.load();
      final AyahWindow window;
      if (saved == null) {
        // Cold start: show Surah Fatiha header (with bismillah), not ayah 1.
        _initialOpenAt = AyahRef.first;
        _openAtSurahHeader = true;
        window = firstLaunchWindow;
        positionListenable.value = (surah: 1, ayah: 1);
      } else {
        final center = AyahRef(saved.surah, saved.ayah).clampToSurah();
        _initialOpenAt = center;
        _openAtSurahHeader = false;
        final (start, end) = AyahRef.windowAround(
          center,
          radius: windowRadiusAyahs,
        );
        window = AyahWindow(start: start, end: end);
        positionListenable.value = (surah: center.surah, ayah: center.ayah);
      }

      // Window-only parse for first paint; full mushaf continues in background.
      _absorb(await _repository.loadWindow(window));
      if (_repository.isFullyCached) {
        _absorb(await _repository.loadFull());
        _fullyLoaded = true;
        _fullLoadStarted = true;
      } else {
        _fullyLoaded = false;
        _startFullLoadInBackground();
      }
      _state = QuranLoadState.ready;
      notifyListeners();
    } catch (e, st) {
      _error = e;
      _state = QuranLoadState.error;
      assert(() {
        debugPrint('Quran load failed: $e\n$st');
        return true;
      }());
      notifyListeners();
    }
  }

  void _startFullLoadInBackground() {
    if (_fullLoadStarted || _fullyLoaded) return;
    _fullLoadStarted = true;

    _repository
        .loadFull()
        .then((full) {
          if (_fullyLoaded) return;
          _absorb(full);
          _fullyLoaded = true;
          // Same list indices — only fill missing rows. No jump / no remount.
          // Defer the list rebuild until the fling ends so scroll stays smooth.
          _notifyContentChanged();
        })
        .catchError((Object e, StackTrace st) {
          _fullLoadStarted = false;
          assert(() {
            debugPrint('Background full Quran load failed: $e\n$st');
            return true;
          }());
        });
  }

  void _absorb(ProcessedQuran quran) {
    for (final item in quran.items) {
      if (item is AyahItem) {
        final chunk = item.chunk;
        _ayahs['${chunk.surah}:${chunk.ayah}'] = chunk;
      }
    }
  }

  /// Marks mushaf scroll activity so heavy [notifyListeners] can wait for idle.
  void setScrollActive(bool active) {
    if (_scrollActive == active) return;
    _scrollActive = active;
    if (!active && _pendingContentNotify) {
      _pendingContentNotify = false;
      notifyListeners();
    }
  }

  void _notifyContentChanged() {
    if (_scrollActive) {
      _pendingContentNotify = true;
      return;
    }
    notifyListeners();
  }

  void updateVisibleAyah(int surah, int ayah) {
    final current = positionListenable.value;
    if (surah == current.surah && ayah == current.ayah) return;
    positionListenable.value = (surah: surah, ayah: ayah);
    if (_scrollActive) {
      _pendingPositionSave = (surah: surah, ayah: ayah);
      return;
    }
    _schedulePositionSave(surah, ayah);
  }

  void _schedulePositionSave(int surah, int ayah) {
    _pendingPositionSave = (surah: surah, ayah: ayah);
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(_positionSaveDebounce, flushPositionSave);
  }

  /// Writes any pending autosave now (scroll end / dispose).
  void flushPositionSave() {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    final pending = _pendingPositionSave;
    _pendingPositionSave = null;
    if (pending == null) return;
    _positionStore.save(surah: pending.surah, ayah: pending.ayah);
  }

  /// Reloads the bound profile's saved position after a profile switch.
  /// Does not reparse Quran data; call [ensureAyahAvailable] as needed.
  Future<({int surah, int ayah, bool openAtSurahHeader})> reloadSavedPosition() async {
    final saved = await _positionStore.load();
    if (saved == null) {
      _initialOpenAt = AyahRef.first;
      _openAtSurahHeader = true;
      positionListenable.value = (surah: 1, ayah: 1);
      notifyListeners();
      return (surah: 1, ayah: 1, openAtSurahHeader: true);
    }

    final center = AyahRef(saved.surah, saved.ayah).clampToSurah();
    _initialOpenAt = center;
    _openAtSurahHeader = false;
    positionListenable.value = (surah: center.surah, ayah: center.ayah);
    await ensureAyahAvailable(center.surah, center.ayah);
    notifyListeners();
    return (
      surah: center.surah,
      ayah: center.ayah,
      openAtSurahHeader: false,
    );
  }

  /// Before the full mushaf is ready, absorb a window around [surah] for jumps.
  Future<void> ensureSurahAvailable(int surah) async {
    if (_fullyLoaded) return;
    if (hasAyah(surah, 1)) return;

    final (start, end) = AyahRef.windowAround(
      AyahRef(surah, 1),
      radius: windowRadiusAyahs,
    );
    final data = await _repository.loadWindow(
      AyahWindow(start: start, end: end),
    );
    if (_fullyLoaded) return;
    _absorb(data);
    notifyListeners();
  }

  /// Before the full mushaf is ready, absorb a window around [surah]:[ayah].
  Future<void> ensureAyahAvailable(int surah, int ayah) async {
    if (_fullyLoaded) return;
    if (hasAyah(surah, ayah)) return;

    final center = AyahRef(surah, ayah).clampToSurah();
    final (start, end) = AyahRef.windowAround(
      center,
      radius: windowRadiusAyahs,
    );
    final data = await _repository.loadWindow(
      AyahWindow(start: start, end: end),
    );
    if (_fullyLoaded) return;
    _absorb(data);
    notifyListeners();
  }

  int itemIndexForSurah(int surah) => MushafLayout.indexOfSurahHeader(surah);

  int itemIndexForAyah(int surah, int ayah) =>
      MushafLayout.indexOfAyah(surah, ayah);

  @override
  void dispose() {
    flushPositionSave();
    positionListenable.dispose();
    super.dispose();
  }
}
