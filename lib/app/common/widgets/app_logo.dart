import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double height;
  final bool isDarkMode;
  const AppLogo({super.key, required this.height, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    // Según tu solicitud: logo azul para modo oscuro, logo blanco para modo claro.
    final String logoPath =
        isDarkMode
            ? 'assets/images/logo_blue.png'
            : 'assets/images/logo_white.png';
    return Center(
      child: Container(
        height: height,
        width:
            height, // Hacemos que sea cuadrado para que el redondeado se vea bien
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24), // Redondeado de las esquinas
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).primaryColor.withOpacity(0.3), // Color difuminado
              blurRadius: 20, // Qué tan borroso es el difuminado
              spreadRadius: 5, // Qué tanto se expande
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            24,
          ), // Recorta la imagen al mismo radio
          child: Image.asset(
            logoPath,
            fit:
                BoxFit
                    .contain, // O BoxFit.cover si quieres que llene todo el cuadrado
            errorBuilder: (context, error, stackTrace) {
              // Fallback widget if the image fails to load
              return Icon(
                Icons.rocket_launch,
                size: height * 0.7,
                color: Theme.of(context).primaryColor,
              );
            },
          ),
        ),
      ),
    );
  }
}
