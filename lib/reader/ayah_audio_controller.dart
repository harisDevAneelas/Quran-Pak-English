import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/audio_language_catalog.dart';
import '../data/ayah_audio_advance.dart';
import '../data/ayah_audio_cache.dart';
import '../data/ayah_repeat_mode.dart';
import '../data/reciter_catalog.dart';
import '../data/tilawat_order.dart';

/// Plays one ayah MP3, then continues through the rest of the mushaf.
///
/// Each ayah gets its own [AudioPlayer]. On web, one shared player keeps the
/// first file it loaded and restarts that verse for every later ayah.
/// Same-ayah repeat seeks and replays without reloading when seek works.
class AyahAudioController extends ChangeNotifier {
  AyahAudioController() {
    _listen();
  }

  static const _prefetchAhead = 5;

  AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;

  int _ticket = 0;
  final AyahAudioAdvance _advanceGate = AyahAudioAdvance();

  String? reciterId;
  String audioLanguageId = AudioLanguageCatalog.noneId;
  TilawatOrder tilawatOrder = TilawatOrder.defaultOrder;
  AyahRepeatMode ayahRepeatMode = AyahRepeatMode.defaultMode;
  int? surah;
  int? ayah;
  bool playing = false;
  bool loading = false;
  bool failed = false;

  /// Bumps each time the same ayah starts again for a repeat play.
  int _repeatPulse = 0;

  bool get isActive => surah != null && ayah != null;

  int get repeatPulse => _repeatPulse;

  String? get url => isActive
      ? ReciterCatalog.audioUrl(
          reciterId: reciterId ?? ReciterCatalog.defaultId,
          surah: surah!,
          ayah: ayah!,
        )
      : null;

  void _listen() {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  /// Drops the current player so the next URL cannot reuse its audio element.
  Future<void> _replacePlayer() async {
    final previousSub = _stateSub;
    final previous = _player;
    _stateSub = null;
    await previousSub?.cancel();
    _player = AudioPlayer();
    _listen();
    unawaited(previous.dispose());
  }

  List<String> _urlsForAyah({
    required String reciterId,
    required String languageId,
    required TilawatOrder order,
    required int surah,
    required int ayah,
  }) {
    final arabic = ReciterCatalog.audioUrls(
      reciterId: reciterId,
      surah: surah,
      ayah: ayah,
    );
    final translation = AudioLanguageCatalog.audioUrls(
      languageId: languageId,
      surah: surah,
      ayah: ayah,
    );
    if (translation.isEmpty) return arabic;
    return switch (order) {
      TilawatOrder.recitationOnly => arabic,
      TilawatOrder.translationOnly => translation,
      TilawatOrder.recitationThenTranslation => [...arabic, ...translation],
      TilawatOrder.translationThenRecitation => [...translation, ...arabic],
    };
  }

  Future<List<String>> _resolvePlayable(List<String> urls) async {
    final resolved = <String>[];
    for (final url in urls) {
      resolved.add(await AyahAudioCache.playable(url));
    }
    return resolved;
  }

  /// Next five ayahs after [surah]:[ayah], in mushaf order, for the current voice.
  void _prefetchAheadFrom({
    required String reciterId,
    required String languageId,
    required TilawatOrder order,
    required int surah,
    required int ayah,
  }) {
    final urls = <String>[];
    var cursor = (surah: surah, ayah: ayah);
    for (var i = 0; i < _prefetchAhead; i++) {
      final next = ReciterCatalog.nextAyah(cursor.surah, cursor.ayah);
      if (next == null) break;
      urls.addAll(
        _urlsForAyah(
          reciterId: reciterId,
          languageId: languageId,
          order: order,
          surah: next.surah,
          ayah: next.ayah,
        ),
      );
      cursor = next;
    }
    if (urls.isEmpty) {
      debugPrint('Ayah audio prefetch: no next ayahs from $surah:$ayah');
      return;
    }
    debugPrint(
      'Ayah audio prefetch from $surah:$ayah → ${urls.length} files',
    );
    AyahAudioCache.prefetch(urls);
  }

  bool get _isLastPlaylistItem {
    final seq = _player.sequence;
    if (seq.isEmpty) return true;
    final index = _player.currentIndex ?? 0;
    return index >= seq.length - 1;
  }

  Future<void> play({
    required String reciterId,
    String? audioLanguageId,
    TilawatOrder? tilawatOrder,
    AyahRepeatMode? ayahRepeatMode,
    required int surah,
    required int ayah,
    bool keepRepeatCount = false,
  }) async {
    final ticket = ++_ticket;
    this.reciterId = ReciterCatalog.resolveId(reciterId);
    this.tilawatOrder = tilawatOrder ?? TilawatOrder.defaultOrder;
    this.ayahRepeatMode = ayahRepeatMode ?? this.ayahRepeatMode;
    this.audioLanguageId = AudioLanguageCatalog.resolveId(audioLanguageId);
    this.surah = surah;
    this.ayah = ayah;
    _advanceGate.beginLoad(resetPlays: !keepRepeatCount);
    playing = false;
    loading = true;
    failed = false;
    notifyListeners();

    final urls = _urlsForAyah(
      reciterId: this.reciterId!,
      languageId: this.audioLanguageId,
      order: this.tilawatOrder,
      surah: surah,
      ayah: ayah,
    );
    if (urls.isEmpty) {
      playing = false;
      loading = false;
      failed = true;
      notifyListeners();
      return;
    }

    _prefetchAheadFrom(
      reciterId: this.reciterId!,
      languageId: this.audioLanguageId,
      order: this.tilawatOrder,
      surah: surah,
      ayah: ayah,
    );

    try {
      final playable = await _resolvePlayable(urls);
      if (ticket != _ticket) return;

      await _replacePlayer();
      if (ticket != _ticket) return;
      if (playable.length == 1) {
        await _player.setUrl(playable.single);
      } else {
        await _player.setAudioSources([
          for (final u in playable) AudioSource.uri(Uri.parse(u)),
        ]);
      }
      if (ticket != _ticket) return;

      unawaited(_startPlayback(ticket));
    } catch (e, st) {
      if (ticket != _ticket) return;
      debugPrint('Ayah audio failed: $urls ($e)\n$st');
      playing = false;
      loading = false;
      failed = true;
      notifyListeners();
    }
  }

  Future<void> _startPlayback(int ticket) async {
    try {
      await _player.play();
      if (ticket != _ticket) return;
      if (_player.processingState == ProcessingState.completed) {
        _requestAdvance();
      }
    } catch (e, st) {
      if (ticket != _ticket) return;
      debugPrint('Ayah audio play failed: $e\n$st');
      playing = false;
      loading = false;
      failed = true;
      notifyListeners();
    }
  }

  /// Replays the already-loaded ayah without re-downloading when seek works.
  Future<void> _replayCurrent() async {
    final currentSurah = surah;
    final currentAyah = ayah;
    final currentReciter = reciterId;
    if (currentSurah == null ||
        currentAyah == null ||
        currentReciter == null) {
      return;
    }

    final ticket = ++_ticket;
    _advanceGate.beginLoad(resetPlays: false);
    playing = false;
    loading = true;
    failed = false;
    _repeatPulse++;
    notifyListeners();

    try {
      final sequenceLen = _player.sequence.length;
      if (sequenceLen > 1) {
        await _player.seek(Duration.zero, index: 0);
      } else {
        await _player.seek(Duration.zero);
      }
      if (ticket != _ticket) return;

      if (_player.processingState == ProcessingState.completed) {
        await play(
          reciterId: currentReciter,
          audioLanguageId: audioLanguageId,
          tilawatOrder: tilawatOrder,
          ayahRepeatMode: ayahRepeatMode,
          surah: currentSurah,
          ayah: currentAyah,
          keepRepeatCount: true,
        );
        return;
      }

      loading = false;
      notifyListeners();
      unawaited(_startPlayback(ticket));
    } catch (e, st) {
      if (ticket != _ticket) return;
      debugPrint('Ayah audio seek replay failed: $e\n$st');
      await play(
        reciterId: currentReciter,
        audioLanguageId: audioLanguageId,
        tilawatOrder: tilawatOrder,
        ayahRepeatMode: ayahRepeatMode,
        surah: currentSurah,
        ayah: currentAyah,
        keepRepeatCount: true,
      );
    }
  }

  Future<void> toggle() async {
    if (!isActive) return;
    if (failed) {
      await play(
        reciterId: reciterId!,
        audioLanguageId: audioLanguageId,
        tilawatOrder: tilawatOrder,
        ayahRepeatMode: ayahRepeatMode,
        surah: surah!,
        ayah: ayah!,
      );
      return;
    }
    if (_player.playing) {
      await pausePlayback();
    } else {
      await resumePlayback();
    }
  }

  Future<void> pausePlayback() async {
    if (!isActive) return;
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<void> resumePlayback() async {
    if (!isActive) return;
    try {
      await _player.play();
    } catch (e, st) {
      debugPrint('Ayah audio resume failed: $e\n$st');
    }
  }

  Future<void> skipNext() async {
    if (!isActive || reciterId == null) return;
    final next = ReciterCatalog.nextAyah(surah!, ayah!);
    if (next == null) {
      await stop();
      return;
    }
    await play(
      reciterId: reciterId!,
      audioLanguageId: audioLanguageId,
      tilawatOrder: tilawatOrder,
      ayahRepeatMode: ayahRepeatMode,
      surah: next.surah,
      ayah: next.ayah,
    );
  }

  Future<void> skipPrevious() async {
    if (!isActive || reciterId == null) return;
    final previous = ReciterCatalog.previousAyah(surah!, ayah!);
    if (previous == null) {
      await play(
        reciterId: reciterId!,
        audioLanguageId: audioLanguageId,
        tilawatOrder: tilawatOrder,
        ayahRepeatMode: ayahRepeatMode,
        surah: surah!,
        ayah: ayah!,
      );
      return;
    }
    await play(
      reciterId: reciterId!,
      audioLanguageId: audioLanguageId,
      tilawatOrder: tilawatOrder,
      ayahRepeatMode: ayahRepeatMode,
      surah: previous.surah,
      ayah: previous.ayah,
    );
  }

  Future<void> stop() async {
    _ticket++;
    _advanceGate.reset();
    reciterId = null;
    audioLanguageId = AudioLanguageCatalog.noneId;
    surah = null;
    ayah = null;
    playing = false;
    loading = false;
    failed = false;
    notifyListeners();
    try {
      await _player.stop();
    } catch (_) {}
  }

  void _onPlayerState(PlayerState state) {
    if (!isActive) return;
    final completed = state.processingState == ProcessingState.completed;
    _advanceGate.onPlayerState(
      playing: state.playing,
      completed: completed,
      ready: state.processingState == ProcessingState.ready,
    );

    if (completed) {
      _requestAdvance();
      return;
    }

    final nextPlaying = state.playing;
    final nextLoading = state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering;
    if (nextPlaying == playing && nextLoading == loading) return;
    playing = nextPlaying;
    loading = nextLoading;
    notifyListeners();
  }

  void _requestAdvance() {
    if (!isActive) return;
    if (!_advanceGate.takeCompletion(lastPlaylistItem: _isLastPlaylistItem)) {
      return;
    }
    unawaited(_advance());
  }

  Future<void> _advance() async {
    final currentSurah = surah;
    final currentAyah = ayah;
    final currentReciter = reciterId;
    final currentLanguage = audioLanguageId;
    final currentOrder = tilawatOrder;
    final currentRepeat = ayahRepeatMode;
    if (currentSurah == null ||
        currentAyah == null ||
        currentReciter == null) {
      return;
    }

    if (_advanceGate.shouldReplay(currentRepeat)) {
      await _replayCurrent();
      return;
    }

    final next = ReciterCatalog.nextAyah(currentSurah, currentAyah);
    if (next == null) {
      await stop();
      return;
    }
    await play(
      reciterId: currentReciter,
      audioLanguageId: currentLanguage,
      tilawatOrder: currentOrder,
      ayahRepeatMode: currentRepeat,
      surah: next.surah,
      ayah: next.ayah,
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }
}
