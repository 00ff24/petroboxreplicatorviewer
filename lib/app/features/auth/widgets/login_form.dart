import 'package:flutter/material.dart';
import 'package:replicatorviewer/app/features/home/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  final _usernameController = TextEditingController();
  final _otpController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _otpFocusNode = FocusNode();

  bool _codeSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _otpController.dispose();
    _usernameFocusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.onError),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _sendCode() async {
    if (_usernameController.text.trim().isEmpty) {
      _showErrorSnackBar('Por favor, introduce tu nombre de usuario.');
      return;
    }

    setState(() => _isLoading = true);
    _usernameFocusNode.unfocus();

    try {
      // Asumimos que el primer servidor de la lista es el de autenticación.
      // En una app real, esta URL debería ser una constante de configuración.
      final authServerUrl = ServerManager.apiEndpoints.first.replaceAll(
        '/usuarios',
        '',
      );
      final url = Uri.parse('$authServerUrl/auth/request-otp');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': _usernameController.text.trim()}),
      );

      final responseBody = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() => _codeSent = true);
        _otpFocusNode.requestFocus();
      } else {
        _showErrorSnackBar(
          responseBody['error'] ?? 'Ocurrió un error desconocido.',
        );
      }
    } catch (e) {
      _showErrorSnackBar(
        'Error de conexión. No se pudo contactar al servidor de autenticación.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    if (_otpController.text.trim().isEmpty) {
      _showErrorSnackBar('Por favor, introduce el código de acceso.');
      return;
    }

    setState(() => _isLoading = true);
    _otpFocusNode.unfocus();

    try {
      final authServerUrl = ServerManager.apiEndpoints.first.replaceAll(
        '/usuarios',
        '',
      );
      final url = Uri.parse('$authServerUrl/auth/login');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': _usernameController.text.trim(),
          'otp': _otpController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) => HomeScreen(
                  onThemeToggle: widget.onThemeToggle,
                  isDarkMode: widget.isDarkMode,
                ),
          ),
        );
      } else {
        final responseBody = json.decode(response.body);
        _showErrorSnackBar(
          responseBody['error'] ?? 'Ocurrió un error desconocido.',
        );
      }
    } catch (e) {
      _showErrorSnackBar(
        'Error de conexión. No se pudo contactar al servidor de autenticación.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- CAMPO USUARIO ---
        TextFormField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          keyboardType: TextInputType.text,
          style: textTheme.bodyLarge,
          readOnly: _codeSent,
          decoration: const InputDecoration(
            labelText: 'Usuario',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onFieldSubmitted: (_) {
            if (!_codeSent) {
              _sendCode();
            } else {
              _otpFocusNode.requestFocus();
            }
          },
        ),
        const SizedBox(height: 20),
        // --- CAMPO OTP ---
        if (_codeSent)
          TextFormField(
            controller: _otpController,
            focusNode: _otpFocusNode,
            keyboardType: TextInputType.number,
            style: textTheme.bodyLarge,
            decoration: const InputDecoration(
              labelText: 'Código de Acceso',
              prefixIcon: Icon(Icons.password_rounded),
            ),
            onFieldSubmitted: (_) => _login(),
          ),
        if (_codeSent) const SizedBox(height: 20),
        const SizedBox(height: 20),
        // --- BOTÓN LOGIN ---
        ElevatedButton(
          onPressed: _isLoading ? null : (_codeSent ? _login : _sendCode),
          child:
              _isLoading
                  ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : Text(_codeSent ? 'Iniciar Sesión' : 'Enviar Código'),
        ),
      ],
    );
  }
}
