import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cliente para el panel de servicios de los 18 genex.
///
/// Estos endpoints viven en el backend de frodo (app_con_agenetes.py, :5001)
/// y son globales (no atados a un usuario): operan sobre la allowlist de genex
/// leída del ~/.ssh/config de frodo.
class GenexApi {
  /// Base del backend que expone los endpoints /genex/... (frodo).
  static const String baseUrl = 'http://frodo.petroboxinc.com:5001';

  static const Duration _timeout = Duration(seconds: 20);

  /// Resumen por servicio sobre los 18 genex (lee la caché del backend).
  static Future<GenexResumen> fetchResumen() async {
    final uri = Uri.parse('$baseUrl/genex/servicios/resumen');
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw GenexApiException('Error ${resp.statusCode} al obtener el resumen');
    }
    return GenexResumen.fromJson(json.decode(resp.body));
  }

  /// Fuerza un sondeo inmediato de los 18 y devuelve el resumen actualizado.
  static Future<GenexResumen> refrescar() async {
    final uri = Uri.parse('$baseUrl/genex/servicios/refrescar');
    final resp = await http
        .post(uri)
        .timeout(const Duration(seconds: 45));
    if (resp.statusCode != 200) {
      throw GenexApiException('Error ${resp.statusCode} al refrescar');
    }
    return GenexResumen.fromJson(json.decode(resp.body));
  }

  /// Estado de un servicio concreto en cada uno de los genex.
  static Future<List<GenexHostEstado>> fetchDetalle(String servicio) async {
    final uri = Uri.parse('$baseUrl/genex/servicios/$servicio');
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw GenexApiException('Error ${resp.statusCode} al obtener el detalle');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final lista = (data['detalle'] as List? ?? []);
    return lista
        .map((e) => GenexHostEstado.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Acción sobre un servicio en UN genex.
  /// accion ∈ {start, stop, restart, enable_automatic, enable_manual, disable}
  static Future<GenexAccionResultado> accion({
    required String host,
    required String servicio,
    required String accion,
  }) async {
    final uri = Uri.parse('$baseUrl/genex/$host/servicios/accion');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'servicio': servicio, 'accion': accion}),
        )
        .timeout(const Duration(seconds: 45));
    final body = _safeJson(resp.body);
    final ok = resp.statusCode == 200 && body['status'] == 'ok';
    return GenexAccionResultado(
      host: host,
      nombre: body['nombre']?.toString() ?? host,
      ok: ok,
      mensaje: body['mensaje']?.toString() ??
          body['error']?.toString() ??
          'Error desconocido',
    );
  }

  /// Aplica la misma acción al servicio en TODOS los genex.
  static Future<GenexAccionMasiva> accionMasiva({
    required String servicio,
    required String accion,
  }) async {
    final uri = Uri.parse('$baseUrl/genex/servicios/$servicio/accion-masiva');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'accion': accion}),
        )
        .timeout(const Duration(seconds: 90));
    if (resp.statusCode != 200) {
      throw GenexApiException('Error ${resp.statusCode} en la acción masiva');
    }
    return GenexAccionMasiva.fromJson(json.decode(resp.body));
  }

  static Map<String, dynamic> _safeJson(String body) {
    try {
      final d = json.decode(body);
      if (d is Map<String, dynamic>) return d;
    } catch (e) {
      debugPrint('GenexApi: respuesta no-JSON: $e');
    }
    return {};
  }
}

class GenexApiException implements Exception {
  final String message;
  GenexApiException(this.message);
  @override
  String toString() => message;
}

/// Metadatos y display de los servicios gestionados.
class GenexServiceMeta {
  /// Etiqueta legible para un nombre de servicio Windows.
  static String label(String servicio) {
    switch (servicio) {
      case 'PetroBoxReplicatorNodeSvc':
        return 'Replicator Node';
      case 'PetroBoxService':
        return 'PetroBox Service';
      case 'PetroBoxService_Port_8091':
        return 'PetroBox Service (8091)';
      case 'petroboxmonitor':
        return 'Monitor';
      case 'petroboxguardian':
        return 'Guardian';
      case 'proxy_bolivia':
        return 'Proxy Bolivia';
      default:
        return servicio;
    }
  }

  /// Acciones disponibles, en orden de presentación.
  static const List<GenexAccion> acciones = [
    GenexAccion('start', 'Iniciar'),
    GenexAccion('stop', 'Detener'),
    GenexAccion('restart', 'Reiniciar'),
    GenexAccion('enable_manual', 'Habilitar (Manual)'),
    GenexAccion('enable_automatic', 'Habilitar (Auto)'),
    GenexAccion('disable', 'Deshabilitar'),
  ];
}

class GenexAccion {
  final String id;
  final String label;
  const GenexAccion(this.id, this.label);
}

// ============================ MODELOS ============================

class GenexResumen {
  final List<GenexServicioResumen> servicios;
  final int totalGenex;
  final double timestamp;
  final double? edadSegundos;

  GenexResumen({
    required this.servicios,
    required this.totalGenex,
    required this.timestamp,
    required this.edadSegundos,
  });

  factory GenexResumen.fromJson(Map<String, dynamic> json) {
    final lista = (json['resumen'] as List? ?? []);
    return GenexResumen(
      servicios: lista
          .map((e) => GenexServicioResumen.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalGenex: (json['total_genex'] as num?)?.toInt() ?? lista.length,
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
      edadSegundos: (json['edad_segundos'] as num?)?.toDouble(),
    );
  }
}

class GenexServicioResumen {
  final String servicio;
  final int activos;
  final int detenidos;
  final int deshabilitados;
  final int noInstalado;
  final int sinRespuesta;
  final int total;

  GenexServicioResumen({
    required this.servicio,
    required this.activos,
    required this.detenidos,
    required this.deshabilitados,
    required this.noInstalado,
    required this.sinRespuesta,
    required this.total,
  });

  /// Cuántos genex tienen el servicio instalado.
  int get instalados => total - noInstalado;

  factory GenexServicioResumen.fromJson(Map<String, dynamic> json) {
    return GenexServicioResumen(
      servicio: json['servicio']?.toString() ?? '',
      activos: (json['activos'] as num?)?.toInt() ?? 0,
      detenidos: (json['detenidos'] as num?)?.toInt() ?? 0,
      deshabilitados: (json['deshabilitados'] as num?)?.toInt() ?? 0,
      noInstalado: (json['no_instalado'] as num?)?.toInt() ?? 0,
      sinRespuesta: (json['sin_respuesta'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class GenexHostEstado {
  final String host;
  final String nombre;
  final bool ok;
  final String? error;
  final bool instalado;
  final String? status; // Running / Stopped / ...
  final String? startType; // Automatic / Manual / Disabled

  GenexHostEstado({
    required this.host,
    required this.nombre,
    required this.ok,
    required this.error,
    required this.instalado,
    required this.status,
    required this.startType,
  });

  bool get running => status == 'Running';

  factory GenexHostEstado.fromJson(Map<String, dynamic> json) {
    return GenexHostEstado(
      host: json['host']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      ok: json['ok'] == true,
      error: json['error']?.toString(),
      instalado: json['instalado'] == true,
      status: json['status']?.toString(),
      startType: json['starttype']?.toString(),
    );
  }
}

class GenexAccionResultado {
  final String host;
  final String nombre;
  final bool ok;
  final String mensaje;
  GenexAccionResultado({
    required this.host,
    required this.nombre,
    required this.ok,
    required this.mensaje,
  });
}

class GenexAccionMasiva {
  final String servicio;
  final String accion;
  final int exitosos;
  final int fallidos;
  final List<GenexAccionResultado> resultados;

  GenexAccionMasiva({
    required this.servicio,
    required this.accion,
    required this.exitosos,
    required this.fallidos,
    required this.resultados,
  });

  factory GenexAccionMasiva.fromJson(Map<String, dynamic> json) {
    final lista = (json['resultados'] as List? ?? []);
    return GenexAccionMasiva(
      servicio: json['servicio']?.toString() ?? '',
      accion: json['accion']?.toString() ?? '',
      exitosos: (json['exitosos'] as num?)?.toInt() ?? 0,
      fallidos: (json['fallidos'] as num?)?.toInt() ?? 0,
      resultados: lista.map((e) {
        final m = e as Map<String, dynamic>;
        return GenexAccionResultado(
          host: m['host']?.toString() ?? '',
          nombre: m['nombre']?.toString() ?? '',
          ok: m['status'] == 'ok',
          mensaje: m['mensaje']?.toString() ?? '',
        );
      }).toList(),
    );
  }
}
