import 'ayah_audio_cache_io.dart'
    if (dart.library.html) 'ayah_audio_cache_web.dart' as impl;

/// Downloads ayah MP3s once and reuses local files on later plays.
///
/// On web there is no disk cache: helpers return the CDN URL unchanged.
abstract final class AyahAudioCache {
  /// Local `file://` URI when already on disk; otherwise the original CDN URL.
  /// Does not wait for a download — use [ensure] / [prefetch] to fill the cache.
  static Future<String> resolve(String url) => impl.resolve(url);

  /// Cached file, or waits if this URL is already being prefetched.
  /// Otherwise returns the CDN URL so the current ayah can start immediately.
  static Future<String> playable(String url) => impl.playable(url);

  /// Downloads [url] to disk if missing; returns a playable URI string.
  static Future<String> ensure(String url) => impl.ensure(url);

  /// Background-download URLs in order (next ayah first).
  static void prefetch(Iterable<String> urls) => impl.prefetch(urls);
}
