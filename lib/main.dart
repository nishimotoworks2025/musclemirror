import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

/// Mixin for accessing theme control methods
mixin ThemeController {
  int get currentThemeModeIndex;
  Future<void> setThemeMode(int index);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final themeModeIndex =
      prefs.getInt('themeMode') ?? 0; // 0: system, 1: light, 2: dark
  await AuthService().initialize();

  runApp(MuscleMirrorApp(initialThemeMode: themeModeIndex));
}

class MuscleMirrorApp extends StatefulWidget {
  final int initialThemeMode;

  const MuscleMirrorApp({super.key, required this.initialThemeMode});

  @override
  State<MuscleMirrorApp> createState() => _MuscleMirrorAppState();

  static ThemeController? of(BuildContext context) {
    return context.findAncestorStateOfType<_MuscleMirrorAppState>();
  }
}

class _MuscleMirrorAppState extends State<MuscleMirrorApp>
    with ThemeController {
  late int _themeModeIndex;

  @override
  void initState() {
    super.initState();
    _themeModeIndex = widget.initialThemeMode;
  }

  ThemeMode get _themeMode {
    switch (_themeModeIndex) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Future<void> setThemeMode(int index) async {
    setState(() {
      _themeModeIndex = index;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', index);
  }

  @override
  int get currentThemeModeIndex => _themeModeIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muscle Mirror',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: AuthService().isAuthenticated
          ? const HomeScreen()
          : const LoginScreen(),
    );
  }
}
