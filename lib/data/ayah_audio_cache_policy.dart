/// Limits for on-disk ayah MP3 cache (IO only; web has no disk cache).
abstract final class AyahAudioCachePolicy {
  /// Files older than this are deleted.
  static const maxAge = Duration(days: 60);

  /// Soft cap: oldest files are removed until total size is under this.
  static const maxBytes = 300 * 1024 * 1024; // 300 MB
}

/// One cached file for eviction decisions.
class AyahAudioCacheEntry {
  const AyahAudioCacheEntry({
    required this.path,
    required this.modified,
    required this.size,
  });

  final String path;
  final DateTime modified;
  final int size;
}

/// Returns paths to delete: expired first, then oldest until under [maxBytes].
///
/// [now] and the limits are injectable for tests.
List<String> ayahAudioCachePathsToDelete({
  required List<AyahAudioCacheEntry> entries,
  required DateTime now,
  Duration maxAge = AyahAudioCachePolicy.maxAge,
  int maxBytes = AyahAudioCachePolicy.maxBytes,
}) {
  if (entries.isEmpty) return const [];

  final expireBefore = now.subtract(maxAge);
  final toDelete = <String>{};
  var remaining = <AyahAudioCacheEntry>[];

  for (final e in entries) {
    if (!e.modified.isAfter(expireBefore)) {
      toDelete.add(e.path);
    } else {
      remaining.add(e);
    }
  }

  var total = 0;
  for (final e in remaining) {
    total += e.size;
  }
  if (total <= maxBytes) {
    return toDelete.toList(growable: false);
  }

  remaining.sort((a, b) => a.modified.compareTo(b.modified));
  for (final e in remaining) {
    if (total <= maxBytes) break;
    toDelete.add(e.path);
    total -= e.size;
  }
  return toDelete.toList(growable: false);
}
