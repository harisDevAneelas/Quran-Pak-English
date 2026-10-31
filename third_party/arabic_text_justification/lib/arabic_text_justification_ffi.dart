/// Mobile/desktop (dart:ffi) entrypoint: the native HarfBuzz-backed shaper.
///
/// Import this on Android/iOS/desktop. Do NOT import it on web (it pulls in
/// dart:ffi); use the web shaper there instead.
library;

export 'src/ffi/ffi_shaper.dart' show FfiShaper;
