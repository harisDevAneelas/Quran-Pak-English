import 'package:arabic_text_justification/arabic_text_justification.dart';
import 'package:flutter/material.dart';

import 'kfgqpc_font_path.dart';

/// Provides the filesystem / asset key for KFGQPC Nastaleeq used by HB widgets.
///
/// Resolves the font path and warms the HarfBuzz shaper once before the reader
/// appears, so scroll builds do not pay a cold-load empty frame.
class KfgqpcFontScope extends StatefulWidget {
  const KfgqpcFontScope({super.key, required this.child});

  final Widget child;

  static String? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_KfgqpcFontInherited>()
        ?.fontPath;
  }

  static String of(BuildContext context) {
    final path = maybeOf(context);
    assert(path != null, 'KfgqpcFontScope not found');
    return path!;
  }

  @override
  State<KfgqpcFontScope> createState() => _KfgqpcFontScopeState();
}

class _KfgqpcFontScopeState extends State<KfgqpcFontScope> {
  late final Future<String> _future = _resolveAndWarm();

  static Future<String> _resolveAndWarm() async {
    final path = await KfgqpcFontPath.resolve();
    // Warm in the background — do not block the reader behind FFI load.
    // peekJustificationShaper will pick it up once ready.
    warmJustificationShaper(path).then(
      (_) {},
      onError: (Object e, StackTrace st) {
        assert(() {
          debugPrint('Shaper warm failed (will retry on first line): $e\n$st');
          return true;
        }());
      },
    );
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Material(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load Quran font:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Material(
            color: Colors.white,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Preparing Quran…'),
                  ],
                ),
              ),
            ),
          );
        }
        return _KfgqpcFontInherited(fontPath: snap.data!, child: widget.child);
      },
    );
  }
}

class _KfgqpcFontInherited extends InheritedWidget {
  const _KfgqpcFontInherited({required this.fontPath, required super.child});

  final String fontPath;

  @override
  bool updateShouldNotify(_KfgqpcFontInherited oldWidget) =>
      fontPath != oldWidget.fontPath;
}
