import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/mushaf_script.dart';
import 'ayah_ref.dart';
import 'quran_metadata.dart';
import 'quran_models.dart';
import 'tajweed_parser.dart';

/// Loads the mushaf from a colored JSON asset (shared full parse + window).
class QuranDataRepository {
  QuranDataRepository({
    this.fullAssetPath = 'assets/data/quran.colored.json',
    this.script = MushafScript.indopak,
  });

  factory QuranDataRepository.forScript(MushafScript script) {
    return QuranDataRepository(
      fullAssetPath: script.coloredAssetPath,
      script: script,
    );
  }

  final String fullAssetPath;

  final MushafScript script;

  static final Map<String, ProcessedQuran> _sharedFull = {};
  static final Map<String, Future<ProcessedQuran>> _sharedInFlight = {};
  static final Map<String, QuranAyahChunk> _sharedBismillah = {};
  static final Map<String, String> _sharedJsonString = {};
  static final Map<String, Future<String>> _sharedJsonInFlight = {};

  /// Shared bismillah for Surah headers (no Tajweed).
  QuranAyahChunk? get bismillah => _sharedBismillah[fullAssetPath];

  /// True after [loadFull] has finished and is cached.
  bool get isFullyCached => _sharedFull.containsKey(fullAssetPath);

  /// Small slice for a fast first paint.
  ///
  /// Uses the full cache when ready. If a full parse is already running, waits
  /// for it. Otherwise parses only [window] from the colored JSON so the
  /// reader can open before the whole mushaf is built.
  Future<ProcessedQuran> loadWindow(AyahWindow window) async {
    final cached = _sharedFull[fullAssetPath];
    if (cached != null) return _filterWindow(cached, window);

    final inFlight = _sharedInFlight[fullAssetPath];
    if (inFlight != null) {
      return _filterWindow(await inFlight, window);
    }

    await _ensureBismillah();
    final jsonString = await _loadJsonString();
    return _parseJson(jsonString, window: window);
  }

  /// Full mushaf from the colored JSON (one parse per asset path).
  Future<ProcessedQuran> loadFull() {
    final cached = _sharedFull[fullAssetPath];
    if (cached != null) return SynchronousFuture(cached);

    final inFlight = _sharedInFlight[fullAssetPath];
    if (inFlight != null) return inFlight;

    final future = _loadAndParseFull().then((value) {
      _sharedFull[fullAssetPath] = value;
      return value;
    }).whenComplete(() {
      _sharedInFlight.remove(fullAssetPath);
    });
    _sharedInFlight[fullAssetPath] = future;
    return future;
  }

  Future<ProcessedQuran> _loadAndParseFull() async {
    await _ensureBismillah();
    final jsonString = await _loadJsonString();
    return _parseJson(jsonString);
  }

  Future<String> _loadJsonString() {
    final cached = _sharedJsonString[fullAssetPath];
    if (cached != null) return SynchronousFuture(cached);

    final inFlight = _sharedJsonInFlight[fullAssetPath];
    if (inFlight != null) return inFlight;

    final future = rootBundle.loadString(fullAssetPath).then((value) {
      _sharedJsonString[fullAssetPath] = value;
      return value;
    }).whenComplete(() {
      _sharedJsonInFlight.remove(fullAssetPath);
    });
    _sharedJsonInFlight[fullAssetPath] = future;
    return future;
  }

  Future<ProcessedQuran> _parseJson(
    String jsonString, {
    AyahWindow? window,
  }) async {
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
      return TajweedParser.parseJsonString(jsonString, window: window);
    }

    final startSurah = window?.start.surah;
    final startAyah = window?.start.ayah;
    final endSurah = window?.end.surah;
    final endAyah = window?.end.ayah;
    return Isolate.run(() {
      final AyahWindow? isolateWindow;
      if (startSurah == null ||
          startAyah == null ||
          endSurah == null ||
          endAyah == null) {
        isolateWindow = null;
      } else {
        isolateWindow = AyahWindow(
          start: AyahRef(startSurah, startAyah),
          end: AyahRef(endSurah, endAyah),
        );
      }
      return TajweedParser.parseJsonString(
        jsonString,
        window: isolateWindow,
      );
    });
  }

  static ProcessedQuran _filterWindow(
    ProcessedQuran full,
    AyahWindow window,
  ) {
    final items = <QuranReaderItem>[];
    final surahToItemIndex = <int, int>{};
    final ayahToItemIndex = <String, int>{};
    var ayahCount = 0;
    var wordCount = 0;

    for (final item in full.items) {
      if (item is! AyahItem) continue;
      final chunk = item.chunk;
      if (!window.contains(chunk.surah, chunk.ayah)) continue;
      ayahToItemIndex['${chunk.surah}:${chunk.ayah}'] = items.length;
      surahToItemIndex.putIfAbsent(chunk.surah, () => items.length);
      items.add(item);
      ayahCount++;
      wordCount += chunk.wordCount;
    }

    return ProcessedQuran(
      items: List<QuranReaderItem>.unmodifiable(items),
      surahToItemIndex: Map<int, int>.unmodifiable(surahToItemIndex),
      ayahToItemIndex: Map<String, int>.unmodifiable(ayahToItemIndex),
      surahCount: surahToItemIndex.length,
      ayahCount: ayahCount,
      wordCount: wordCount,
    );
  }

  /// Loads plain bismillah words (no Tajweed).
  Future<void> _ensureBismillah() async {
    if (_sharedBismillah.containsKey(fullAssetPath)) return;
    final texts = await _loadBismillahTexts();
    if (texts.isEmpty) {
      throw StateError('Missing bismillah words for $fullAssetPath');
    }
    _sharedBismillah[fullAssetPath] = QuranAyahChunk(
      surah: 0,
      ayah: 0,
      words: List<QuranWord>.unmodifiable([
        for (final text in texts) QuranWord(text: text),
      ]),
    );
  }

  Future<List<String>> _loadBismillahTexts() async {
    final meta = await QuranMetadata.load();
    return meta.bismillahWordsFor(script);
  }
}
