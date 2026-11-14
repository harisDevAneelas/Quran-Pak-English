import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/mushaf_layout.dart';
import '../core/mushaf_script.dart';
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
    MushafScript script = MushafScript.defaultScript,
    required ReadingPositionStore positionStore,
  }) : _script = script,
       _repository = repository ?? QuranDataRepository.forScript(script),
       _positionStore = positionStore;

  MushafScript _script;
  QuranDataRepository _repository;
  final ReadingPositionStore _positionStore;

  /// Bumps on each [setMushafScript] so a stale await cannot apply an older swap.
  int _scriptSwitchGen = 0;

  /// Bumps after a successful script apply so the mushaf list can remount.
  int _mushafListEpoch = 0;

  Future<void>? _scriptSwitchInFlight;
  MushafScript? _scriptSwitchTarget;

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
  MushafScript get mushafScript => _script;

  /// Changes when the active mushaf face/text pair is applied — use as a list key.
  int get mushafListEpoch => _mushafListEpoch;

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
      _preloadOtherScripts();
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

  /// Bind script before [initialize] (settings already loaded).
  void prepareScript(MushafScript script) {
    if (_state != QuranLoadState.idle) return;
    _script = script;
    _repository = QuranDataRepository.forScript(script);
  }

  /// Swap mushaf script using the already-cached colored JSON (no reparse).
  ///
  /// Loads the new script’s ayahs first, then flips [_script] + repository in
  /// one notify. Font scope follows [_script]; flipping early painted the old
  /// orthography with the new face (IndoPak letters → `?` under DigitalKhatt).
  /// Concurrent calls for the same [script] share one in-flight future.
  Future<void> setMushafScript(MushafScript script) async {
    if (script == _script) return;
    if (_state == QuranLoadState.idle || _state == QuranLoadState.loading) {
      prepareScript(script);
      return;
    }

    final inFlight = _scriptSwitchInFlight;
    if (inFlight != null && _scriptSwitchTarget == script) {
      await inFlight;
      return;
    }

    final run = _setMushafScriptBody(script);
    _scriptSwitchTarget = script;
    _scriptSwitchInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_scriptSwitchInFlight, run)) {
        _scriptSwitchInFlight = null;
        _scriptSwitchTarget = null;
      }
    }
  }

  Future<void> _setMushafScriptBody(MushafScript script) async {
    final gen = ++_scriptSwitchGen;
    final repo = QuranDataRepository.forScript(script);

    final center = AyahRef(
      positionListenable.value.surah,
      positionListenable.value.ayah,
    ).clampToSurah();
    final (start, end) = AyahRef.windowAround(
      center,
      radius: windowRadiusAyahs,
    );
    final window = AyahWindow(start: start, end: end);

    final ProcessedQuran loaded;
    final bool fullyCached = repo.isFullyCached;
    if (fullyCached) {
      loaded = await repo.loadFull();
    } else {
      loaded = await repo.loadWindow(window);
    }
    if (gen != _scriptSwitchGen) return;

    _script = script;
    _repository = repo;
    _ayahs.clear();
    _fullyLoaded = false;
    _fullLoadStarted = false;
    _absorb(loaded);
    if (fullyCached) {
      _fullyLoaded = true;
      _fullLoadStarted = true;
    } else {
      _startFullLoadInBackground();
    }
    _mushafListEpoch++;
    notifyListeners();
  }

  /// Parse the inactive script once in the background so switching is instant.
  void _preloadOtherScripts() {
    for (final script in MushafScript.values) {
      if (script == _script) continue;
      unawaited(
        QuranDataRepository.forScript(script).loadFull().then(
          (_) {},
          onError: (Object e, StackTrace st) {
            assert(() {
              debugPrint('Preload $script mushaf failed: $e\n$st');
              return true;
            }());
          },
        ),
      );
    }
  }

  void _startFullLoadInBackground() {
    if (_fullLoadStarted || _fullyLoaded) return;
    _fullLoadStarted = true;

    final gen = _scriptSwitchGen;
    final repo = _repository;
    final script = _script;

    repo
        .loadFull()
        .then((full) {
          if (gen != _scriptSwitchGen ||
              script != _script ||
              !identical(repo, _repository)) {
            return;
          }
          if (_fullyLoaded) return;
          _absorb(full);
          _fullyLoaded = true;
          _notifyContentChanged();
        })
        .catchError((Object e, StackTrace st) {
          if (gen != _scriptSwitchGen ||
              script != _script ||
              !identical(repo, _repository)) {
            return;
          }
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

    final gen = _scriptSwitchGen;
    final repo = _repository;
    final (start, end) = AyahRef.windowAround(
      AyahRef(surah, 1),
      radius: windowRadiusAyahs,
    );
    final data = await repo.loadWindow(
      AyahWindow(start: start, end: end),
    );
    if (gen != _scriptSwitchGen || !identical(repo, _repository)) return;
    if (_fullyLoaded) return;
    _absorb(data);
    notifyListeners();
  }

  /// Before the full mushaf is ready, absorb a window around [surah]:[ayah].
  Future<void> ensureAyahAvailable(int surah, int ayah) async {
    if (_fullyLoaded) return;
    if (hasAyah(surah, ayah)) return;

    final gen = _scriptSwitchGen;
    final repo = _repository;
    final center = AyahRef(surah, ayah).clampToSurah();
    final (start, end) = AyahRef.windowAround(
      center,
      radius: windowRadiusAyahs,
    );
    final data = await repo.loadWindow(
      AyahWindow(start: start, end: end),
    );
    if (gen != _scriptSwitchGen || !identical(repo, _repository)) return;
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
