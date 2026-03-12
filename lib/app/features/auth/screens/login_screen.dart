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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            const SizedBox(height: 60),
                            Text(
                              'PetroBox',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: theme.textTheme.headlineLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 30),
                            AppLogo(height: 100, isDarkMode: isDarkMode),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 500),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Card(
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: LoginForm(
                              onThemeToggle: onThemeToggle,
                              isDarkMode: isDarkMode,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
