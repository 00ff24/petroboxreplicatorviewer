import 'package:flutter/material.dart';
import 'package:replicatorviewer/app/features/home/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginForm extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDarkMode;

  const LoginForm({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _loginButtonFocusNode = FocusNode();

  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _loginButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // unfocus all fields
    _emailFocusNode.unfocus();
    _passwordFocusNode.unfocus();
    _loginButtonFocusNode.unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email == 'petrobox' && password == 'petrobox') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            onThemeToggle: widget.onThemeToggle,
            isDarkMode: widget.isDarkMode,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Credenciales incorrectas',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onError,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 32,
          ),
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- CAMPO EMAIL ---
        TextFormField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          style: textTheme.bodyLarge,
          decoration: const InputDecoration(
            labelText: 'Correo Electrónico',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onFieldSubmitted: (_) {
            _passwordFocusNode.requestFocus();
          },
        ),
        const SizedBox(height: 20),
        // --- CAMPO PASSWORD ---
        TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          obscureText: !_isPasswordVisible,
          style: textTheme.bodyLarge,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() {
                  _isPasswordVisible = !_isPasswordVisible;
                });
              },
            ),
          ),
          onFieldSubmitted: (_) => _login(),
          onEditingComplete: () {
            // This is called when the user presses the "next" button on the keyboard
            // or tabs away from the field. We want to move focus to the login button.
            _loginButtonFocusNode.requestFocus();
          },
        ),
        const SizedBox(height: 10),
        // --- OLVIDÉ CONTRASEÑA ---
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              // TODO: Implement forgot password logic
            },
            child: const Text('¿Olvidaste tu contraseña?'),
          ),
        ),
        const SizedBox(height: 20),
        // --- BOTÓN LOGIN ---
        ElevatedButton(
          focusNode: _loginButtonFocusNode,
          onPressed: _login,
          child: const Text('Iniciar Sesión'),
        ),
      ],
    );
  }
}
