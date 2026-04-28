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
  String? _successfulAuthUrl; // Guardamos el servidor que envió el OTP

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

    bool success = false;
    String lastErrorMessage = 'No se pudo conectar con ningún servidor.';

    // Iterar por todos los servidores disponibles hasta que uno responda
    for (final endpoint in ServerManager.apiEndpoints) {
      try {
        final uri = Uri.parse(endpoint);
        final authServerUrl = '${uri.scheme}://${uri.host}:${uri.port}';
        final url = Uri.parse('$authServerUrl/auth/request-otp');

        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'username': _usernameController.text.trim()}),
            )
            .timeout(
              const Duration(seconds: 5),
            ); // Timeout corto para probar el siguiente rápido

        if (response.statusCode == 200) {
          // ÉXITO: Guardamos este servidor para usarlo en el login
          _successfulAuthUrl = authServerUrl;
          success = true;

          setState(() => _codeSent = true);
          _otpFocusNode.requestFocus();
          break; // Dejamos de buscar
        } else {
          final responseBody = json.decode(response.body);
          lastErrorMessage = responseBody['error'] ?? 'Error del servidor';
        }
      } catch (e) {
        // Si falla este servidor, el bucle continúa con el siguiente
        debugPrint('Fallo conexión auth con $endpoint: $e');
      }
    }

    if (!success) {
      _showErrorSnackBar('Error: $lastErrorMessage');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _login() async {
    if (_otpController.text.trim().isEmpty) {
      _showErrorSnackBar('Por favor, introduce el código de acceso.');
      return;
    }

    if (_successfulAuthUrl == null) {
      _showErrorSnackBar('Error de sesión: Servidor no identificado.');
      return;
    }

    setState(() => _isLoading = true);
    _otpFocusNode.unfocus();

    try {
      // Usamos EL MISMO servidor que envió el código (Sticky Session)
      final url = Uri.parse('$_successfulAuthUrl/auth/login');

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
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Estilo base para inputs tipo "Underline"
    final underlineBorder = UnderlineInputBorder(
      borderSide: BorderSide(
        color: isDark ? Colors.white24 : Colors.black12,
        width: 1.5,
      ),
    );

    final underlineFocusedBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: primaryColor, width: 2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- CAMPO USUARIO ---
        TextFormField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          keyboardType: TextInputType.text,
          // Estilo de texto un poco más grande
          style: textTheme.bodyLarge?.copyWith(fontSize: 16),
          // Bloquear si ya se envió el código (Paso 2)
          enabled: !_codeSent,
          decoration: InputDecoration(
            labelText: 'USUARIO',
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: primaryColor,
            ),
            hintText: 'ej. nombre.apellido',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),

            // Override de bordes para usar línea inferior
            border: underlineBorder,
            enabledBorder: underlineBorder,
            focusedBorder: underlineFocusedBorder,
            filled: false, // Sin fondo gris

            prefixIcon: const Icon(Icons.person_outline),

            // Check verde animado
            suffixIcon:
                _codeSent
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
          ),
          onFieldSubmitted: (_) {
            if (!_codeSent) {
              _sendCode();
            }
          },
        ),

        // --- CAMPO OTP (Animado) ---
        AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack, // Rebote suave al final
          child: Container(
            height: _codeSent ? null : 0, // Altura 0 si no se ha enviado
            margin: EdgeInsets.only(top: _codeSent ? 24 : 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _codeSent ? 1.0 : 0.0,
              child: TextFormField(
                controller: _otpController,
                focusNode: _otpFocusNode,
                keyboardType: TextInputType.number,
                style: textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  letterSpacing: 4,
                ), // Espaciado para código
                decoration: InputDecoration(
                  labelText: 'CÓDIGO DE ACCESO',
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: primaryColor,
                  ),
                  hintText: '******',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),

                  border: underlineBorder,
                  enabledBorder: underlineBorder,
                  focusedBorder: underlineFocusedBorder,
                  filled: false,

                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                ),
                onFieldSubmitted: (_) => _login(),
              ),
            ),
          ),
        ),

        const SizedBox(height: 40),

        // --- BOTON LOGIN ---
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: _isLoading
                ? null
                : LinearGradient(
                    colors: [
                      primaryColor,
                      primaryColor.withOpacity(0.8),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            boxShadow: _isLoading
                ? []
                : [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: ElevatedButton(
            onPressed: _isLoading ? null : (_codeSent ? _login : _sendCode),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isLoading ? null : Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
            ),
            child:
                _isLoading
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                        strokeCap: StrokeCap.round,
                      ),
                    )
                    : Text(
                      _codeSent ? 'Iniciar Sesion' : 'Enviar Codigo',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
          ),
        ),
      ],
    );
  }
}
