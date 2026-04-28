import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:replicatorviewer/app/common/widgets/app_logo.dart';
import 'package:replicatorviewer/app/config/theme.dart';
import 'package:replicatorviewer/app/features/auth/screens/login_screen.dart';
import 'package:replicatorviewer/app/features/home/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuración específica para escritorio
  try {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(
          1300,
          768,
        ), // Tamaño inicial al abrir la ventana (4 tarjetas * 300 + espacios)
        minimumSize: Size(1300, 768), // Tamaño mínimo (límite para achicar)
        center: true,
        title: 'Replicator Viewer',
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setMinimumSize(const Size(1300, 768));
      });
    }
  } catch (e) {
    debugPrint('Error inicializando windowManager (ignorable en móvil): $e');
  }

  runApp(const LoginApp());
}

class LoginApp extends StatefulWidget {
  const LoginApp({super.key});

  @override
  State<LoginApp> createState() => _LoginAppState();
}

class _LoginAppState extends State<LoginApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _toggleFullScreen() async {
    bool isFullScreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullScreen);
  }

  Future<void> _initialize() async {
    // 1. Precargar datos de servidores (Splash logic)
    // Si hay caché, entramos directo. Si no, esperamos al primer servidor.
    final bool hasCache = await ServerManager.hasCache();

    if (!hasCache) {
      final completer = Completer<void>();
      final stream = ServerManager.streamServers();
      StreamSubscription? subscription;

      subscription = stream.listen(
        (server) async {
          if (!completer.isCompleted) {
            // Guardamos el primero para que HomeScreen tenga algo que mostrar
            await ServerManager.saveToCache([server]);
            completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future;
      await subscription.cancel();
    } else {
      // Si hay caché, dejamos que HomeScreen se encargue de refrescar en background
    }

    // 2. Cargar estado de login
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
        _isLoading = false;
      });
    }
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullScreen,
      },
      child: MaterialApp(
        title: 'Replicator Login',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        // Si está logueado mostramos Home, si no, Login
        home:
            _isLoading
                ? const SplashScreen()
                : (_isLoggedIn
                    ? HomeScreen(
                      onThemeToggle: _toggleTheme,
                      isDarkMode: _themeMode == ThemeMode.dark,
                    )
                    : LoginScreen(
                      onThemeToggle: _toggleTheme,
                      isDarkMode: _themeMode == ThemeMode.dark,
                    )),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppLogo(height: 120, isDarkMode: isDark),
                const SizedBox(height: 48),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primaryBlue,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Cargando sistema...",
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
