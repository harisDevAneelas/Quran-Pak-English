import 'package:arabic_text_justification/arabic_text_justification.dart';
import 'package:flutter/material.dart';

import '../../core/mushaf_script.dart';
import '../../core/quran_font.dart';
import 'kfgqpc_font_path.dart';

/// Provides the active mushaf HarfBuzz path + Flutter font family.
///
/// Both faces are resolved and warmed once; changing [script] only switches
/// which cached path is inherited (no asset reload).
class KfgqpcFontScope extends StatefulWidget {
  const KfgqpcFontScope({
    super.key,
    required this.script,
    required this.child,
  });

  final MushafScript script;
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

  /// Always the KFGQPC / Nastaleeq shaper path (for circled ayah digits).
  static String nastaleeqPathOf(BuildContext context) {
    final path = context
        .dependOnInheritedWidgetOfExactType<_KfgqpcFontInherited>()
        ?.nastaleeqFontPath;
    assert(path != null, 'KfgqpcFontScope not found');
    return path!;
  }

  static MushafScript scriptOf(BuildContext context) {
    final script = context
        .dependOnInheritedWidgetOfExactType<_KfgqpcFontInherited>()
        ?.script;
    assert(script != null, 'KfgqpcFontScope not found');
    return script!;
  }

  static String familyOf(BuildContext context) {
    final family = maybeFamilyOf(context);
    assert(family != null, 'KfgqpcFontScope not found');
    return family!;
  }

  static String? maybeFamilyOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_KfgqpcFontInherited>()
        ?.fontFamily;
  }

  @override
  State<KfgqpcFontScope> createState() => _KfgqpcFontScopeState();
}

class _KfgqpcFontScopeState extends State<KfgqpcFontScope> {
  late final Future<Map<MushafScript, String>> _future = _resolveAndWarmAll();

  static Future<Map<MushafScript, String>> _resolveAndWarmAll() async {
    final paths = await KfgqpcFontPath.resolveAll();
    for (final path in paths.values) {
      warmJustificationShaper(path).then(
        (_) {},
        onError: (Object e, StackTrace st) {
          assert(() {
            debugPrint('Shaper warm failed (will retry on first line): $e\n$st');
            return true;
          }());
        },
      );
    }
    return paths;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<MushafScript, String>>(
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
        final paths = snap.data!;
        return _KfgqpcFontInherited(
          script: widget.script,
          fontPath: paths[widget.script]!,
          nastaleeqFontPath: paths[MushafScript.indopak]!,
          fontFamily: QuranFont.familyFor(widget.script),
          child: widget.child,
        );
      },
    );
  }
}

class _KfgqpcFontInherited extends InheritedWidget {
  const _KfgqpcFontInherited({
    required this.script,
    required this.fontPath,
    required this.nastaleeqFontPath,
    required this.fontFamily,
    required super.child,
  });

  final MushafScript script;
  final String fontPath;
  final String nastaleeqFontPath;
  final String fontFamily;

  @override
  bool updateShouldNotify(_KfgqpcFontInherited oldWidget) =>
      script != oldWidget.script ||
      fontPath != oldWidget.fontPath ||
      nastaleeqFontPath != oldWidget.nastaleeqFontPath ||
      fontFamily != oldWidget.fontFamily;
}
