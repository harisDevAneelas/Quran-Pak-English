import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// One shared preview player for picker lists (reciter / spoken / azaan).
class OptionPreviewPlayer extends ChangeNotifier {
  OptionPreviewPlayer() {
    _sub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && _playingKey != null) {
        _playingKey = null;
        if (!_disposed) notifyListeners();
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<ProcessingState>? _sub;
  String? _playingKey;
  bool _disposed = false;

  String? get playingKey => _playingKey;

  bool isPlaying(String key) => _playingKey == key;

  Future<void> toggleUrl(String key, String url) async {
    await _toggle(key, () => _player.setUrl(url));
  }

  Future<void> toggleAsset(String key, String assetPath) async {
    await _toggle(key, () => _player.setAsset(assetPath));
  }

  Future<void> _toggle(String key, Future<Duration?> Function() load) async {
    if (_disposed) return;
    if (_playingKey == key) {
      await stop();
      return;
    }
    try {
      await _player.stop();
      _playingKey = key;
      notifyListeners();
      await load();
      await _player.play();
    } catch (e, st) {
      debugPrint('Preview failed: $e\n$st');
      _playingKey = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    _playingKey = null;
    try {
      await _player.stop();
    } catch (_) {}
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _player.dispose();
    super.dispose();
  }
}
