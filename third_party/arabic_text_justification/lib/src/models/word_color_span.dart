import 'package:flutter/painting.dart';

class WordColorSpan {
  final int wordIndex;
  final int start;
  final int end;
  final Color color;

  const WordColorSpan({
    required this.wordIndex,
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  bool operator ==(Object other) =>
      other is WordColorSpan &&
      wordIndex == other.wordIndex &&
      start == other.start &&
      end == other.end &&
      color == other.color;

  @override
  int get hashCode => Object.hash(wordIndex, start, end, color);
}
