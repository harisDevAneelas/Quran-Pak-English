import 'ayah_ref.dart';
import 'quran_models.dart';

class VerseGroup {
  const VerseGroup({
    required this.number,
    required this.ayahs,
    this.verses = const [],
  });

  final int number;
  final List<AyahRef> ayahs;
  final List<List<QuranWord>> verses;
}

class VerseCollection {
  const VerseCollection({
    required this.id,
    required this.title,
    required this.groups,
  });

  final String id;
  final String title;
  final List<VerseGroup> groups;
}

abstract final class VerseCollectionIds {
  static const shifa = 'shifa';
  static const rabbana = 'rabbana';
  static const manzil = 'manzil';
  static const ruqyah = 'ruqyah';

  static const titles = <String, String>{
    shifa: 'Ayaat-e-shifa',
    rabbana: 'Forty Rabbana',
    manzil: 'Manzil',
    ruqyah: 'Ruqyah Shariah',
  };

  static String? titleOf(String listId) => titles[listId];
}
