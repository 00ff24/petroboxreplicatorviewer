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
            icon: Icon(isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            color: theme.textTheme.titleLarge?.color,
            tooltip: 'Cambiar tema',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            reverse: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // --- ZONA SUPERIOR (Logo y Titulo) ---
                  Padding(
                    padding: const EdgeInsets.only(top: 60, bottom: 40),
                    child: Column(
                      children: [
                        AppLogo(height: 80, isDarkMode: isDarkMode),
                        const SizedBox(height: 28),
                        Text(
                          'Bienvenido',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                            color: theme.textTheme.headlineLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Inicia sesion para continuar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- BOTTOM SHEET (Formulario) ---
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                    ),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 30,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
                    child: SafeArea(
                      top: false,
                      child: LoginForm(
                        onThemeToggle: onThemeToggle,
                        isDarkMode: isDarkMode,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
