import 'package:flutter/material.dart';
import 'package:replicatorviewer/app/common/widgets/app_logo.dart';
import 'package:replicatorviewer/app/features/auth/widgets/login_form.dart';

class LoginScreen extends StatelessWidget {
  final VoidCallback onThemeToggle;
  final bool isDarkMode;

  const LoginScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: onThemeToggle,
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            color: theme.textTheme.titleLarge?.color,
            tooltip: 'Cambiar tema',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppLogo(height: 150, isDarkMode: isDarkMode),
                const SizedBox(height: 40),
                Text(
                  'Bienvenido',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineLarge?.color,
                  ),
                ),
                const SizedBox(height: 30),
                LoginForm(onThemeToggle: onThemeToggle, isDarkMode: isDarkMode),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
