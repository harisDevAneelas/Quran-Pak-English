import 'notification_route.dart';

/// Named [RouteSettings] for mains and settings pickers above the mushaf.
abstract final class ReaderRoutes {
  static const hub = NotificationRoute.hubPayload;
  static const todaysRecitation = NotificationRoute.todaysRecitationPayload;
  static const profile = 'profile';

  static const reciter = 'settings_reciter';
  static const spokenTranslation = 'settings_spoken_translation';
  static const onScreenTranslation = 'settings_on_screen_translation';
  static const azaan = 'settings_azaan';
  static const mushafScript = 'settings_mushaf_script';

  static bool isMainName(String? name) {
    return name == hub || name == todaysRecitation || name == profile;
  }

  static bool isSettingsPickerName(String? name) {
    return name == reciter ||
        name == spokenTranslation ||
        name == onScreenTranslation ||
        name == azaan ||
        name == mushafScript;
  }
}
