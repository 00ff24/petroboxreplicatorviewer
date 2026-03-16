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
            // Usamos reverse: true para que al abrir el teclado, el scroll se ajuste desde abajo
            reverse: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // --- ZONA SUPERIOR (Logo y Título) ---
                  Padding(
                    padding: const EdgeInsets.only(top: 60, bottom: 40),
                    child: Column(
                      children: [
                        AppLogo(height: 80, isDarkMode: isDarkMode),
                        const SizedBox(height: 24),
                        Text(
                          '¡Hola,\nBienvenido!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 36,
                            height: 1.2,
                            fontWeight: FontWeight.w300, // Light font
                            color: theme.textTheme.headlineLarge?.color,
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
                    ), // Límite para tablets/PC
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(40),
                        topRight: Radius.circular(40),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
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
