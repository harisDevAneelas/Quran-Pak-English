import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quran_app/data/db_ayah.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = p.normalize(
    p.join(Directory.current.path, 'assets/data/english_db.sqlite'),
  );
  print('opening $dbPath exists=${File(dbPath).existsSync()}');
  final db = await databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );

  final r1 = await db.rawQuery(
    'SELECT AyaNum, substr(SaheehInternational,1,60) AS t '
    'FROM Quran WHERE SuraNum=1 AND AyaNum=?',
    [DbAyah.of(1, 1)],
  );
  print('app 1:1 -> DB ${DbAyah.of(1, 1)}: ${r1.first['t']}');

  final r2 = await db.rawQuery(
    'SELECT words FROM Quran WHERE SuraNum=1 AND AyaNum=?',
    [DbAyah.of(1, 1)],
  );
  final wbw = r2.first['words'] as String;
  final re = RegExp(r'\[([^\]]+)\]');
  final pairs = re
      .allMatches(wbw)
      .map((m) {
        final inner = m.group(1)!;
        final c = inner.indexOf(':');
        return '${inner.substring(0, c).trim()} = '
            '${inner.substring(c + 1).trim()}';
      })
      .take(3)
      .toList();
  print('WBW pairs: $pairs');

  final rows = await db.rawQuery(
    'SELECT AyaNum FROM Quran WHERE SuraNum=1 ORDER BY AyaNum',
  );
  final appKeys = <String>[];
  for (final row in rows) {
    final app = DbAyah.toApp(1, (row['AyaNum'] as num).toInt());
    if (app != null) appKeys.add('1:$app');
  }
  print('surah1 app keys: $appKeys');

  final count = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM Quran '
    "WHERE SaheehInternational IS NOT NULL AND SaheehInternational != ''",
  );
  print('translation ayahs: ${count.first['c']}');

  await db.close();
}
