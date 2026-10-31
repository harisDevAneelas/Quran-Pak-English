import 'dart:typed_data' show Uint8List;

import 'package:flutter/services.dart' show rootBundle;

enum JustificationFont {
  madinah('madina.otf'),
  digitalKhatt('digitalkhatt.otf');

  static const JustificationFont defaultFont = madinah;

  const JustificationFont(this.fileName);

  final String fileName;

  String get assetKey => 'packages/arabic_text_justification/assets/$fileName';

  Future<Uint8List> loadBytes() async {
    final data = await rootBundle.load(assetKey);
    return data.buffer.asUint8List();
  }
}
