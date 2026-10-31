import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../data/quran_metadata.dart';
import '../data/reciter_catalog.dart';
import 'ayah_audio_controller.dart';

/// Media-session bridge for [AyahAudioController] (Android / iOS only).
class AyahAudioHandler extends BaseAudioHandler {
  AyahAudioController? _controller;
  bool _backgroundEnabled = false;

  void attach(AyahAudioController controller) {
    if (identical(_controller, controller)) return;
    _controller?.removeListener(_syncFromController);
    _controller = controller;
    controller.addListener(_syncFromController);
    _syncFromController();
  }

  void detach() {
    _controller?.removeListener(_syncFromController);
    _controller = null;
    unawaited(_clearSession());
  }

  void setBackgroundEnabled(bool enabled) {
    if (_backgroundEnabled == enabled) return;
    _backgroundEnabled = enabled;
    if (!enabled) {
      unawaited(_clearSession());
    } else {
      _syncFromController();
    }
  }

  Future<void> _clearSession() async {
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  void _syncFromController() {
    if (!_backgroundEnabled || kIsWeb) {
      unawaited(_clearSession());
      return;
    }
    final c = _controller;
    if (c == null || !c.isActive) {
      unawaited(_clearSession());
      return;
    }

    final surah = c.surah!;
    final ayah = c.ayah!;
    final name = QuranMetadata.nameArOrEmpty(surah);
    final title = name.isEmpty ? 'Surah $surah' : name;
    mediaItem.add(
      MediaItem(
        id: '$surah:$ayah',
        title: title,
        album: 'Recitation',
        artist: ReciterCatalog.labelFor(c.reciterId ?? ReciterCatalog.defaultId),
        displayTitle: title,
        displaySubtitle: 'Ayah $ayah',
      ),
    );

    final processing = c.failed
        ? AudioProcessingState.error
        : c.loading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (c.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: c.playing,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        queueIndex: 0,
      ),
    );
  }

  @override
  Future<void> play() async {
    final c = _controller;
    if (c == null) return;
    if (c.failed || !c.isActive) {
      if (c.isActive && c.reciterId != null) {
        await c.play(
          reciterId: c.reciterId!,
          audioLanguageId: c.audioLanguageId,
          tilawatOrder: c.tilawatOrder,
          ayahRepeatMode: c.ayahRepeatMode,
          surah: c.surah!,
          ayah: c.ayah!,
        );
      }
      return;
    }
    await c.resumePlayback();
  }

  @override
  Future<void> pause() async {
    await _controller?.pausePlayback();
  }

  @override
  Future<void> stop() async {
    await _controller?.stop();
    await _clearSession();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    await _controller?.skipNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _controller?.skipPrevious();
  }
}

/// Lazily starts [AudioService] on mobile; no-op on web.
abstract final class AyahAudioServiceHost {
  static AyahAudioHandler? _handler;
  static Future<AyahAudioHandler?>? _initFuture;

  static AyahAudioHandler? get handler => _handler;

  static bool get _supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<AyahAudioHandler?> ensureInitialized() {
    if (!_supported) return Future<AyahAudioHandler?>.value(null);
    return _initFuture ??= _init();
  }

  static Future<AyahAudioHandler?> _init() async {
    try {
      _handler = await AudioService.init(
        builder: AyahAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.quran_app.tilawat',
          androidNotificationChannelName: 'Recitation',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
        ),
      );
      return _handler;
    } catch (e, st) {
      debugPrint('AudioService.init failed: $e\n$st');
      _initFuture = null;
      return null;
    }
  }
}
