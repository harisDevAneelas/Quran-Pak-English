import '../core/surah_ayah_counts.dart';
import 'db_ayah.dart';

/// One reciter whose audio is served by qurancompany.com.
///
/// [id] is the CDN folder name. Portrait lives at [imageAsset]
/// (`assets/reciters/{id}.jpg`, or [dummyImageAsset] when missing).
class ReciterOption {
  const ReciterOption({required this.id, required this.name});

  final String id;
  final String name;

  /// Bundled portrait for this reciter.
  String get imageAsset => ReciterCatalog.imageAssetFor(id);
}

/// Reciters whose `001002.mp3` (and the rest of the mushaf) actually plays.
///
/// Folder names that 404 on the CDN are omitted.
abstract final class ReciterCatalog {
  static const defaultId = 'afasy';

  static const _base = 'https://qurancompany.com/quran/reciters';

  static const imageAssetDir = 'assets/reciters';
  static const dummyImageAsset = '$imageAssetDir/dummy.jpg';

  /// Portrait path for [id] (`assets/reciters/{id}.jpg`).
  static String imageAssetFor(String id) =>
      '$imageAssetDir/${resolveId(id)}.jpg';

  /// All folders from https://qurancompany.com/quran/reciters/ whose
  /// `001002.mp3` returns HTTP 200. Omitted: farhat, itani, sowaid, temp.
  static const all = <ReciterOption>[
    ReciterOption(id: 'afasy', name: 'Mishary Rashid Alafasy'),
    ReciterOption(id: 'sudais', name: 'Abdul Rahman Al-Sudais'),
    ReciterOption(id: 'shuraim', name: 'Saud Al-Shuraim'),
    ReciterOption(id: 'muaiqly', name: 'Maher Al-Muaiqly'),
    ReciterOption(id: 'ghamadi', name: 'Saad Al-Ghamdi'),
    ReciterOption(id: 'yasser', name: 'Yasser Al-Dosari'),
    ReciterOption(id: 'ajamy', name: 'Ahmed bin Ali Al-Ajamy'),
    ReciterOption(id: 'hudhaify', name: 'Ali Al-Hudhaify'),
    ReciterOption(id: 'ayyub', name: 'Muhammad Ayyub'),
    ReciterOption(id: 'basfar', name: 'Abdullah Basfar'),
    ReciterOption(id: 'matrood', name: 'Abdullah Al-Matrood'),
    ReciterOption(id: 'juhany', name: 'Abdullah Al-Juhany'),
    ReciterOption(id: 'shateri', name: 'Abu Bakr Al-Shatri'),
    ReciterOption(id: 'qahtani', name: 'Khalid Al-Qahtani'),
    ReciterOption(id: 'alqasim', name: 'Abdul Mohsin Al-Qasim'),
    ReciterOption(id: 'jibreel', name: 'Muhammad Jibreel'),
    ReciterOption(id: 'jaber', name: 'Ali Jaber'),
    ReciterOption(id: 'bukhatir', name: 'Salah Bukhatir'),
    ReciterOption(id: 'fares', name: 'Fares Abbad'),
    ReciterOption(id: 'hani', name: 'Hani Al-Rifai'),
    ReciterOption(id: 'qatami', name: 'Nasser Al-Qatami'),
    ReciterOption(id: 'budair', name: 'Abdullah Al-Budair'),
    ReciterOption(id: 'tunaiji', name: 'Khalid Al-Tunaiji'),
    ReciterOption(id: 'abdulkareem', name: 'Abdul Karim'),
    ReciterOption(id: 'akhdar', name: 'Ibrahim Al-Akhdar'),
    ReciterOption(id: 'akram', name: 'Akram Al-Alaqmi'),
    ReciterOption(id: 'alili', name: 'Ali Al-Ali'),
    ReciterOption(id: 'banna', name: 'Mahmoud Ali Al-Banna'),
    ReciterOption(id: 'neana', name: "Mahmoud Al-Na'na'"),
    ReciterOption(id: 'tablawi', name: 'Muhammad Mahmoud Al-Tablawi'),
    ReciterOption(id: 'suesy', name: 'Abdul Rashid Sufi'),
    ReciterOption(id: 'yassin', name: 'Yassin Al-Jazairi'),
    ReciterOption(id: 'abdulbasit', name: 'Abdul Basit Abdus Samad'),
    ReciterOption(
      id: 'abdulbasit-mjwd',
      name: 'Abdul Basit Abdus Samad (Mujawwad)',
    ),
    ReciterOption(id: 'husary', name: 'Mahmoud Khalil Al-Husary'),
    ReciterOption(
      id: 'husary-mjwd',
      name: 'Mahmoud Khalil Al-Husary (Mujawwad)',
    ),
    ReciterOption(id: 'minshawi', name: 'Muhammad Siddiq Al-Minshawi'),
    ReciterOption(
      id: 'minshawi-mjwd',
      name: 'Muhammad Siddiq Al-Minshawi (Mujawwad)',
    ),
    ReciterOption(id: 'parhizgar', name: 'Shahriar Parhizgar'),
  ];

  /// Display names saved before the English labels.
  static const _legacyNames = <String, String>{
    'مشاری راشد العفاسی': 'afasy',
    'عبدالرحمن السدیس': 'sudais',
    'سعود الشریم': 'shuraim',
    'ماهر المعیقلی': 'muaiqly',
    'سعد الغامدی': 'ghamadi',
    'ياسر الدوسري': 'yasser',
    'أحمد بن علي العجمي': 'ajamy',
    'علي الحذيفي': 'hudhaify',
    'محمد أيوب': 'ayyub',
    'عبدالله بصفر': 'basfar',
    'عبدالله المطرود': 'matrood',
    'عبدالله الجهني': 'juhany',
    'أبو بكر الشاطري': 'shateri',
    'خالد القحطاني': 'qahtani',
    'عبدالمحسن القاسم': 'alqasim',
    'محمد جبريل': 'jibreel',
    'علي جابر': 'jaber',
    'صلاح بوخاطر': 'bukhatir',
    'فارس عباد': 'fares',
    'هاني الرفاعي': 'hani',
    'ناصر القطامي': 'qatami',
    'عبدالله البُدير': 'budair',
    'خالد الطنيجي': 'tunaiji',
    'عبد الكريم': 'abdulkareem',
    'إبراهيم الأخضر': 'akhdar',
    'أكرم العلاقمي': 'akram',
    'علي العلي': 'alili',
    'محمود علي البنا': 'banna',
    'محمود نعناع': 'neana',
    'محمد محمود الطبلاوي': 'tablawi',
    'عبدالرشيد صوفي': 'suesy',
    'ياسين الجزائري': 'yassin',
    'عبدالباسط عبدالصمد': 'abdulbasit',
    'عبدالباسط عبدالصمد (مجوّد)': 'abdulbasit-mjwd',
    'محمود خليل الحصری': 'husary',
    'محمود خليل الحصری (مجوّد)': 'husary-mjwd',
    'محمد صديق المنشاوي': 'minshawi',
    'محمد صديق المنشاوي (مجوّد)': 'minshawi-mjwd',
    'شهريار برهيزكار': 'parhizgar',
  };

  static List<String> get labels => [for (final r in all) r.name];

  static ReciterOption byId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return all.first;
  }

  static String labelFor(String id) => byId(resolveId(id)).name;

  /// Accepts a folder id or a previously saved display name.
  static String resolveId(String? raw) {
    if (raw == null || raw.isEmpty) return defaultId;
    final legacy = _legacyNames[raw];
    if (legacy != null) return legacy;
    for (final r in all) {
      if (r.id == raw || r.name == raw) return r.id;
    }
    return defaultId;
  }

  /// CDN file ayah for an app ayah (same Fatiha offset as [DbAyah.of]).
  static int fileAyah(int surah, int ayah) => DbAyah.of(surah, ayah);

  static String _url(String reciterId, int surah, int fileAyahNo) {
    final s = surah.clamp(1, 114).toString().padLeft(3, '0');
    final a = fileAyahNo.clamp(1, 999).toString().padLeft(3, '0');
    return '$_base/$reciterId/$s$a.mp3';
  }

  /// Fatiha 2nd verse only (`001002` / الحمد) for list preview.
  static String previewUrl(String reciterId) =>
      _url(resolveId(reciterId), 1, 2);

  /// One or more MP3 URLs for the given app ayah.
  ///
  /// Surah 1 ayah 1 merges bismillah (`001001`) with الحمد (`001002`).
  static List<String> audioUrls({
    required String reciterId,
    required int surah,
    required int ayah,
  }) {
    final id = resolveId(reciterId);
    if (surah == 1 && ayah == 1) {
      return [_url(id, 1, 1), _url(id, 1, 2)];
    }
    return [_url(id, surah, fileAyah(surah, ayah))];
  }

  static String audioUrl({
    required String reciterId,
    required int surah,
    required int ayah,
  }) =>
      audioUrls(reciterId: reciterId, surah: surah, ayah: ayah).last;

  /// Next ayah in the mushaf, crossing into the next surah when needed.
  static ({int surah, int ayah})? nextAyah(int surah, int ayah) {
    if (ayah < SurahAyahCounts.of(surah)) {
      return (surah: surah, ayah: ayah + 1);
    }
    if (surah < 114) return (surah: surah + 1, ayah: 1);
    return null;
  }

  /// Previous ayah in the mushaf, crossing into the previous surah when needed.
  static ({int surah, int ayah})? previousAyah(int surah, int ayah) {
    if (ayah > 1) return (surah: surah, ayah: ayah - 1);
    if (surah > 1) {
      return (surah: surah - 1, ayah: SurahAyahCounts.of(surah - 1));
    }
    return null;
  }

  static bool hasNextAyah(int surah, int ayah) =>
      nextAyah(surah, ayah) != null;

  static bool hasPreviousAyah(int surah, int ayah) =>
      previousAyah(surah, ayah) != null;
}
