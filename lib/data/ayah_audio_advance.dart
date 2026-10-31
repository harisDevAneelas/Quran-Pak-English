import 'ayah_repeat_mode.dart';

/// One ayah load may produce at most one advance (replay or next ayah).
///
/// just_audio often emits `completed` twice (playing:true then playing:false).
/// A second event must not skip a verse.
class AyahAudioAdvance {
  int _loadId = 0;
  int? _consumedLoadId;
  bool heardPlayback = false;
  int playsCompleted = 0;

  int get loadId => _loadId;

  /// Start a new ayah file (or a same-ayah replay after seek).
  void beginLoad({required bool resetPlays}) {
    _loadId++;
    _consumedLoadId = null;
    heardPlayback = false;
    if (resetPlays) playsCompleted = 0;
  }

  /// Actual playback started — not a `completed` event that still has playing:true.
  void onPlayerState({
    required bool playing,
    required bool completed,
    bool ready = false,
  }) {
    if (ready || (playing && !completed)) heardPlayback = true;
  }

  /// True once for this load, when the ayah's last file has really finished.
  bool takeCompletion({required bool lastPlaylistItem}) {
    if (!heardPlayback || !lastPlaylistItem) return false;
    if (_consumedLoadId == _loadId) return false;
    _consumedLoadId = _loadId;
    return true;
  }

  /// After [takeCompletion], whether to replay this ayah instead of moving on.
  bool shouldReplay(AyahRepeatMode mode) {
    playsCompleted++;
    final target = mode.playCount;
    return target == null || playsCompleted < target;
  }

  void reset() {
    _loadId++;
    _consumedLoadId = _loadId;
    heardPlayback = false;
    playsCompleted = 0;
  }
}
