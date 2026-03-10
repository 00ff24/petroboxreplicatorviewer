import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:replicatorviewer/app/config/theme.dart';

import 'package:replicatorviewer/main.dart'; // Tu import original

import 'package:shared_preferences/shared_preferences.dart'; // Tu import original

import 'dart:math'; // Añadido para generar números de paquetes

import 'dart:async';

import 'dart:convert';

import 'package:http/http.dart' as http;

// ==========================================

// MODELOS DE DATOS SIMULADOS

// ==========================================

class LogData {
  final String time;

  final String type;

  final String msg;

  LogData(this.time, this.type, this.msg);

  Map<String, dynamic> toJson() => {'time': time, 'type': type, 'msg': msg};

  factory LogData.fromJson(Map<String, dynamic> json) {
    return LogData(json['time'] ?? '', json['type'] ?? '', json['msg'] ?? '');
  }
}

class ServiceData {
  final String name;

  final String status;

  ServiceData(this.name, this.status);

  Map<String, dynamic> toJson() => {'name': name, 'status': status};

  factory ServiceData.fromJson(Map<String, dynamic> json) {
    return ServiceData(json['name'] ?? '', json['status'] ?? '');
  }
}

class ServerData {
  final String id;

  final String name;

  final String apiUrl;

  final String status; // 'healthy', 'warning', 'error'

  final String ip;

  final String cpuUsage;

  final String ramUsage;

  final String uptime;

  final int activeNodes;

  final int inactiveNodes;

  final String os;

  final List<ServiceData> services;

  final List<LogData> logs;

  // Datos crudos para las barras de progreso

  final double rawCpu;

  final double rawRamPercent;

  ServerData({
    required this.id,

    required this.name,

    required this.apiUrl,

    required this.status,

    required this.ip,

    required this.cpuUsage,

    required this.ramUsage,

    required this.uptime,

    required this.activeNodes,

    required this.inactiveNodes,

    required this.os,

    required this.services,

    required this.logs,

    required this.rawCpu,

    required this.rawRamPercent,
  });

  Map<String, dynamic> toJson() => {
    'id': id,

    'name': name,

    'apiUrl': apiUrl,

    'status': status,

    'ip': ip,

    'cpuUsage': cpuUsage,

    'ramUsage': ramUsage,

    'uptime': uptime,

    'activeNodes': activeNodes,

    'inactiveNodes': inactiveNodes,

    'os': os,

    'services': services.map((x) => x.toJson()).toList(),

    'logs': logs.map((x) => x.toJson()).toList(),

    'rawCpu': rawCpu,

    'rawRamPercent': rawRamPercent,
  };

  factory ServerData.fromJson(Map<String, dynamic> json) {
    return ServerData(
      id: json['id'] ?? '',

      name: json['name'] ?? '',

      apiUrl: json['apiUrl'] ?? '',

      status: json['status'] ?? 'healthy',

      ip: json['ip'] ?? '',

      cpuUsage: json['cpuUsage'] ?? '',

      ramUsage: json['ramUsage'] ?? '',

      uptime: json['uptime'] ?? '',

      activeNodes: json['activeNodes'] ?? 0,

      inactiveNodes: json['inactiveNodes'] ?? 0,

      os: json['os'] ?? '',

      services:
          (json['services'] as List?)
              ?.map((x) => ServiceData.fromJson(x))
              .toList() ??
          [],

      logs:
          (json['logs'] as List?)?.map((x) => LogData.fromJson(x)).toList() ??
          [],

      rawCpu: (json['rawCpu'] as num?)?.toDouble() ?? 0.0,

      rawRamPercent: (json['rawRamPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ServerManager {
  static const String _cacheKey = 'cached_servers_data';

  static const List<String> apiEndpoints = [
    'http://bilbo.petroboxinc.com:5001/usuarios',

    'http://aragorn.petroboxinc.com:5001/usuarios',

    'http://frodo.petroboxinc.com:5001/usuarios',

    'http://192.168.125.204:5001/usuarios',
  ];

  static Future<bool> hasCache() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.containsKey(_cacheKey);
  }

  static Future<List<ServerData>> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String? jsonString = prefs.getString(_cacheKey);

      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);

        return jsonList.map((e) => ServerData.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading cache: $e');
    }

    return [];
  }

  static Future<void> saveToCache(List<ServerData> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String jsonString = json.encode(
        servers.map((e) => e.toJson()).toList(),
      );

      await prefs.setString(_cacheKey, jsonString);
    } catch (e) {
      debugPrint('Error saving cache: $e');
    }
  }

  static Stream<ServerData> streamServers() {
    final controller = StreamController<ServerData>();

    int pending = apiEndpoints.length;

    for (String endpoint in apiEndpoints) {
      _fetchSingleServer(endpoint)
          .then((server) {
            if (!controller.isClosed) {
              controller.add(server);
            }
          })
          .whenComplete(() {
            pending--;

            if (pending == 0 && !controller.isClosed) {
              controller.close();
            }
          });
    }

    return controller.stream;
  }

  static Future<ServerData> _fetchSingleServer(String endpoint) async {
    try {
      final response = await http
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic>) {
          return _parseServerData(data, endpoint);
        } else {
          debugPrint(
            'Formato inválido en $endpoint: Se esperaba un objeto JSON',
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching data from $endpoint: $e');
    }

    return _createOfflineServer(endpoint);
  }

  static ServerData _createOfflineServer(String endpoint) {
    final uri = Uri.parse(endpoint);

    // Intentamos deducir un nombre amigable del subdominio (ej: bilbo)

    // Si parece una IP (empieza con número), la dejamos completa. Si es dominio, cortamos.
    String host = uri.host;
    String name = host;

    if (!RegExp(r'^\d').hasMatch(host)) {
      name = host.split('.').first;
    }

    return ServerData(
      id: name.toLowerCase(),

      name: name.toUpperCase().isEmpty ? 'UNKNOWN' : name.toUpperCase(),

      apiUrl: endpoint,

      status: 'offline',

      ip: 'N/A',

      cpuUsage: '0%',

      ramUsage: 'N/A',

      uptime: 'Offline',

      activeNodes: 0,

      inactiveNodes: 0,

      os: 'Unknown',

      services: [],

      logs: [],

      rawCpu: 0.0,

      rawRamPercent: 0.0,
    );
  }

  static Future<bool> restartMachine(ServerData server) async {
    try {
      // La URL actual es "...:5001/usuarios", necesitamos "...:5001/sistema/reiniciar"

      final baseUrl = server.apiUrl.replaceAll('/usuarios', '');

      final url = '$baseUrl/sistema/reiniciar';

      final response = await http
          .post(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error restarting server ${server.name}: $e');

      return false;
    }
  }

  static Future<List<ServerData>> fetchAndCache() async {
    final List<ServerData> list = [];

    await for (final server in streamServers()) {
      list.add(server);
    }

    list.sort((a, b) => a.name.compareTo(b.name));

    if (list.isNotEmpty) await saveToCache(list);

    return list;
  }

  static ServerData _parseServerData(
    Map<String, dynamic> data,

    String endpoint,
  ) {
    // Protección: Si 'sistema' es null o no es un mapa, usamos un mapa vacío
    final sistema = (data['sistema'] is Map) ? data['sistema'] : {};

    // 1. Interfaces e IPs (Todas las interfaces)

    final Map<String, dynamic> red =
        (sistema['red'] is Map) ? sistema['red'] : {};

    final String ipList = red.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    // 2. CPU

    final cpuData = sistema['cpu'];

    double cpuLoad = 0.0;

    if (cpuData != null && cpuData['carga_percent'] != null) {
      cpuLoad = (cpuData['carga_percent'] as num).toDouble();
    }

    // 3. RAM (Usado / Total)

    final ramData = sistema['ram'];

    String ramUsage = 'N/A';

    double ramPercent = 0.0;

    if (ramData != null) {
      final double total = (ramData['total_gb'] as num).toDouble();

      final double libre = (ramData['libre_gb'] as num).toDouble();

      final double usado = total - libre;

      ramPercent = (total > 0) ? (usado / total) * 100 : 0.0;

      ramUsage = '${usado.toStringAsFixed(1)}/${total.toStringAsFixed(1)} GB';
    }

    // 4. Uptime

    final String uptime = sistema['uptime'] ?? 'N/A';

    // 4. Lógica de Estado (Semáforo)

    String status = 'healthy';

    if (cpuLoad >= 90) {
      status = 'error';
    } else if (cpuLoad >= 40) {
      status = 'warning';
    }

    // 5. Nodos Activos/Inactivos

    final List usuarios = data['usuarios'] ?? [];

    final int activeNodes = usuarios.length;

    final int inactiveNodes = 0;

    return ServerData(
      id: (data['servidor'] ?? 'unknown').toString().toLowerCase(),

      name: (data['servidor'] ?? 'Unknown').toString().toUpperCase(),

      apiUrl: endpoint,

      status: status,

      ip: ipList.isNotEmpty ? ipList : 'No IP',

      cpuUsage: '${cpuLoad.toStringAsFixed(1)}%',

      ramUsage: ramUsage,

      uptime: uptime,

      activeNodes: activeNodes,

      inactiveNodes: inactiveNodes,

      os: sistema['os_version']?.toString() ?? 'Linux',

      services: [],

      logs: [],

      rawCpu: cpuLoad,

      rawRamPercent: ramPercent,
    );
  }
}

// ==========================================

// PANTALLA PRINCIPAL

// ==========================================

class HomeScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;

  final bool isDarkMode;

  const HomeScreen({
    super.key,

    required this.onThemeToggle,

    required this.isDarkMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<ServerData> servers = [];

  Set<String> _expandedCardIds = {};

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initData();

    // Actualizar cada 60 segundos

    _timer = Timer.periodic(
      const Duration(seconds: 60),

      (_) => _refreshServers(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _timer?.cancel();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshServers();
    }
  }

  Future<void> _initData() async {
    // 1. Cargar caché inmediatamente para mostrar info

    final cached = await ServerManager.loadFromCache();

    if (mounted && cached.isNotEmpty) {
      setState(() {
        servers = cached;
      });
    }

    // 2. Actualizar desde la red

    _refreshServers();
  }

  Future<void> _refreshServers() async {
    // Usamos apiUrl como clave para asegurar que coincida el endpoint con la caché

    final Map<String, ServerData> currentMap = {
      for (var s in servers) s.apiUrl: s,
    };

    final stream = ServerManager.streamServers();

    await for (final server in stream) {
      if (server.status == 'offline' && currentMap.containsKey(server.apiUrl)) {
        final cached = currentMap[server.apiUrl]!;

        // FUSIONAR: Mantener datos de caché pero marcar como offline

        currentMap[server.apiUrl] = ServerData(
          id: cached.id,

          name: cached.name,

          apiUrl: server.apiUrl,

          status: 'offline',

          ip: cached.ip,

          cpuUsage: cached.cpuUsage,

          ramUsage: cached.ramUsage,

          uptime: cached.uptime,

          activeNodes: cached.activeNodes,

          inactiveNodes: cached.inactiveNodes,

          os: cached.os,

          services: cached.services,

          logs: cached.logs,

          rawCpu: cached.rawCpu,

          rawRamPercent: cached.rawRamPercent,
        );
      } else {
        currentMap[server.apiUrl] = server;
      }

      final List<ServerData> newList = currentMap.values.toList();

      newList.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() => servers = newList);
      }
    }

    if (servers.isNotEmpty) {
      await ServerManager.saveToCache(servers);
    }
  }

  Future<void> _handleServerRestart(ServerData server) async {
    final bool? confirm = await showDialog<bool>(
      context: context,

      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).cardColor,

            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,

                  color: AppTheme.errorRed,

                  size: 28,
                ),

                const SizedBox(width: 12),

                const Text('Reiniciar Servidor'),
              ],
            ),

            content: Text(
              '¿Estás seguro de que deseas reiniciar TODO el servidor "${server.name}"?\n\n'
              'Esto apagará el sistema operativo y detendrá todos los servicios temporalmente.',

              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),

            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),

                child: const Text('Cancelar'),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorRed,

                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,

                    vertical: 12,
                  ),
                ),

                onPressed: () => Navigator.pop(context, true),

                child: const Text(
                  'Reiniciar Sistema', // No necesita estilo aquí
                  style: TextStyle(
                    // Usa un TextStyle normal aquí
                    color: Colors.white,
                  ),
                  // Ya no es const
                ),
              ),
            ],
          ),
    );

    if (confirm == true && mounted) {
      final success = await ServerManager.restartMachine(server);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Orden de reinicio enviada a ${server.name}'
                  : 'Error al enviar orden de reinicio',
            ),

            backgroundColor:
                success ? AppTheme.successGreen : AppTheme.errorRed,
          ),
        );
      }
    }
  }

  void _toggleGlobalExpansion() {
    setState(() {
      // Si todas están expandidas, las colapsamos todas.
      // Si no (hay alguna cerrada o todas cerradas), las expandimos todas.
      if (_expandedCardIds.length == servers.length) {
        _expandedCardIds.clear();
      } else {
        _expandedCardIds = servers.map((s) => s.id).toSet();
      }
    });
  }

  double _estimateCardHeight(ServerData server) {
    // Altura base estimada (Header + Resources + Footer + Paddings)
    // Ajustado para cubrir el contenido estático de la tarjeta
    double height = 230;

    // Altura dinámica por líneas de IP (lo que hace a Gandalf más alto)
    final ipLines =
        server.ip.split('\n').where((l) => l.trim().isNotEmpty).length;
    height += ipLines * 28; // ~28px por línea de IP (ajustado para Linux)
    return height;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Detectar si es móvil (ancho < 600px)

            final bool isMobile = constraints.maxWidth < 600;

            // 1. Más padding en los bordes para móvil (32 vs 20)

            final double horizontalPadding = isMobile ? 32.0 : 20.0;

            // 2. Tarjetas más anchas en móvil (hasta 340px o ancho disponible)

            // En desktop se mantiene fijo en 300px para acomodar mejor la info

            double cardWidth = 300.0;

            if (isMobile) {
              final double availableWidth =
                  constraints.maxWidth - (horizontalPadding * 2);

              cardWidth = max(0.0, availableWidth > 340 ? 340 : availableWidth);
            }

            // Calcular la altura máxima basada en la tarjeta más grande
            double maxCardHeight = 0;
            int maxIpLines = 0;
            if (servers.isNotEmpty) {
              maxCardHeight = servers.map(_estimateCardHeight).reduce(max);
              maxIpLines = servers
                  .map(
                    (s) =>
                        s.ip
                            .split('\n')
                            .where((l) => l.trim().isNotEmpty)
                            .length,
                  )
                  .reduce(max);
            }

            if (maxCardHeight < 280) {
              maxCardHeight = 280; // Altura mínima de seguridad
            }

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,

                vertical: 16.0,
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  // HEADER
                  buildHeader(context, isMobile),

                  const SizedBox(height: 32),

                  // GRID DE SERVIDORES
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 20),

                      child: SizedBox(
                        width: double.infinity,

                        child: Wrap(
                          alignment: WrapAlignment.center, // 3. Centrado

                          spacing: 16, // 4. Padding entre tarjetas igual

                          runSpacing: 16,

                          children:
                              servers.map((server) {
                                final bool isExpanded =
                                    isMobile &&
                                    _expandedCardIds.contains(server.id);
                                return SizedBox(
                                  width: cardWidth,
                                  height: isMobile ? null : maxCardHeight,
                                  child: buildServerCard(
                                    context,
                                    server,
                                    maxIpLines,
                                    isMobile,
                                    isExpanded,
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ==========================================

  // WIDGETS CONSTRUCTORES (HOME)

  // ==========================================

  Widget buildHeader(BuildContext context, bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,

      children: [
        // Logo y Título
        Row(
          children: [
            // Avatar del Perfil (Movido al principio)
            Container(
              width: 32,

              height: 32,

              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor.withOpacity(0.1),

                borderRadius: BorderRadius.circular(16),

                border: Border.all(color: Theme.of(context).dividerColor),
              ),

              child: const Center(
                child: Text(
                  'P',

                  style: TextStyle(
                    color: AppTheme.primaryBlue,

                    fontWeight: FontWeight.bold,

                    fontSize: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  'Panel de Servidores',

                  style: TextStyle(
                    fontSize: 18.0,

                    fontWeight: FontWeight.bold,

                    color: Theme.of(context).textTheme.titleLarge?.color,

                    letterSpacing: 0.5,
                  ),
                ),

                Row(
                  children: [
                    // Indicador de pulso
                    SizedBox(
                      width: 8,

                      height: 8,

                      child: Stack(
                        alignment: Alignment.center,

                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.successGreen.withOpacity(0.5),

                              shape: BoxShape.circle,
                            ),
                          ),

                          Container(
                            width: 4,

                            height: 4,

                            decoration: const BoxDecoration(
                              color: AppTheme.successGreen,

                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 6),

                    const Text(
                      'Monitoreo activo',

                      style: TextStyle(
                        fontSize: 12,

                        color: AppTheme.successGreen,

                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // Controles derechos
        Row(
          children: [
            // Botón Global Expandir/Colapsar (Solo visible en móvil)
            if (isMobile)
              IconButton(
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: _toggleGlobalExpansion,
                icon: Icon(
                  _expandedCardIds.length == servers.length
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                ),
                iconSize: 22,
                tooltip:
                    _expandedCardIds.length == servers.length
                        ? 'Colapsar todo'
                        : 'Expandir todo',
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),

            IconButton(
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: widget.onThemeToggle,

              icon: const Icon(Icons.light_mode_rounded),
              iconSize: 22,
              tooltip: 'Cambiar tema',

              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),

            IconButton(
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.logout_rounded),
              iconSize: 22,
              color: AppTheme.errorRed,

              tooltip: 'Cerrar Sesión',

              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();

                await prefs.clear();

                if (!context.mounted) return;

                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginApp()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget buildServerCard(
    BuildContext context,
    ServerData server,
    int maxIpLines,
    bool isMobile,
    bool isExpanded,
  ) {
    final String osName = server.os.split(' ').first;
    server.os.replaceFirst(osName, '').trim();

    Color statusColor;

    IconData statusIcon;

    Color statusBg;

    switch (server.status) {
      case 'healthy':
        statusColor = AppTheme.successGreen;

        statusIcon = Icons.check_circle_rounded;

        statusBg = AppTheme.successGreen.withOpacity(0.1);

        break;

      case 'warning':
        statusColor = AppTheme.warningAmber;

        statusIcon = Icons.warning_amber_rounded;

        statusBg = AppTheme.warningAmber.withOpacity(0.1);

        break;

      case 'error':
        statusColor = AppTheme.errorRed;

        statusIcon = Icons.error_outline_rounded;

        statusBg = AppTheme.errorRed.withOpacity(0.1);

        break;

      case 'offline':
        statusColor =
            Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey;

        statusIcon = Icons.cloud_off_rounded;

        statusBg = Colors.grey.withOpacity(0.1);

        break;

      default:
        statusColor =
            Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey;

        statusIcon = Icons.info_outline_rounded;

        statusBg = (Theme.of(context).textTheme.bodyMedium?.color ??
                Colors.grey)
            .withOpacity(0.1);
    }

    return Container(
      padding: const EdgeInsets.all(20),

      decoration: AppTheme.cardDecoration(context),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Para que AnimatedSize funcione bien

        children: [
          // Cabecera del Servidor (Tap -> Toggle en móvil / Navigate en Desktop)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (isMobile) {
                setState(() {
                  if (isExpanded) {
                    _expandedCardIds.remove(server.id);
                  } else {
                    _expandedCardIds.add(server.id);
                  }
                });
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServerDetailScreen(server: server),
                  ),
                );
              }
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,

              children: [
                Container(
                  padding: const EdgeInsets.all(10),

                  decoration: BoxDecoration(
                    color: statusBg,

                    borderRadius: BorderRadius.circular(12),
                  ),

                  child: Icon(Icons.dns_rounded, color: statusColor, size: 22),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // ICONO SISTEMA OPERATIVO
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              server.os.toLowerCase().contains('ubuntu')
                                  ? const Color(0xFFE95420).withOpacity(0.1)
                                  : Theme.of(
                                    context,
                                  ).dividerColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              server.os.toLowerCase().contains('ubuntu')
                                  ? Icons.terminal_rounded
                                  : Icons.computer_rounded,
                              size: 10,
                              color:
                                  server.os.toLowerCase().contains('ubuntu')
                                      ? const Color(0xFFE95420)
                                      : Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              server.os,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color:
                                    server.os.toLowerCase().contains('ubuntu')
                                        ? const Color(0xFFE95420)
                                        : Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 4),

                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 12,
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color,
                          ),

                          const SizedBox(width: 4),

                          Text(
                            'Up: ${server.uptime}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Botón de Reinicio de Servidor
                IconButton(
                  icon: const Icon(Icons.power_settings_new_rounded),

                  color: AppTheme.errorRed,

                  tooltip: 'Reiniciar Servidor Físico',

                  onPressed: () {
                    _handleServerRestart(server);
                  },
                ),

                Icon(statusIcon, color: statusColor, size: 24),
              ],
            ),
          ),

          // Contenido expandible (Tap -> Navegar a detalle)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            child: Visibility(
              visible: !isMobile || isExpanded,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServerDetailScreen(server: server),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),

                    // IPs
                    SizedBox(
                      height: isMobile ? null : maxIpLines * 28.0,
                      child: Column(
                        children:
                            server.ip.split('\n').map((line) {
                              if (line.trim().isEmpty) {
                                return const SizedBox.shrink();
                              }

                              IconData icon = Icons.wifi;

                              String label = "ip";

                              if (line.toLowerCase().contains('eth0')) {
                                icon = Icons.public;

                                label = "eth0";
                              } else if (line.toLowerCase().contains('ham')) {
                                icon = Icons.security;

                                label = "ham0";
                              }

                              // Limpiar la cadena para mostrar solo la IP si es posible

                              String ipValue = line.replaceAll(
                                RegExp(r'.*:\s*'),
                                '',
                              );

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      icon,
                                      size: 14,
                                      color: AppTheme.textMuted,
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        '$label:',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        ipValue,
                                        style: AppTheme.monoStyle.copyWith(
                                          fontSize: 13,
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                      ),
                    ),

                    // Recursos (CPU / RAM) con Barras
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).scaffoldBackgroundColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          // CPU
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.memory_rounded,
                                          size: 12,
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'CPU',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      server.rawCpu.toStringAsFixed(1),
                                      style: AppTheme.monoStyle.copyWith(
                                        fontSize: 11,
                                        color:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Barra de Progreso CPU
                                Row(
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          Container(
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                          FractionallySizedBox(
                                            widthFactor: (server.rawCpu / 100)
                                                .clamp(0.0, 1.0),
                                            child: Container(
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color:
                                                    server.rawCpu > 80
                                                        ? AppTheme.errorRed
                                                        : server.rawCpu > 50
                                                        ? AppTheme.warningAmber
                                                        : AppTheme.successGreen,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${server.rawCpu.toStringAsFixed(0)}%',
                                      style: AppTheme.monoStyle.copyWith(
                                        fontSize: 10,
                                        color:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 16),

                          // RAM
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.sd_storage_rounded,
                                          size: 12,
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'RAM',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      server.ramUsage,
                                      style: AppTheme.monoStyle.copyWith(
                                        fontSize: 11,
                                        color:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Barra de Progreso RAM
                                Row(
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          Container(
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                          FractionallySizedBox(
                                            widthFactor: (server.rawRamPercent /
                                                    100)
                                                .clamp(0.0, 1.0),
                                            child: Container(
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryBlue,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${server.rawRamPercent.toStringAsFixed(0)}%',
                                      style: AppTheme.monoStyle.copyWith(
                                        fontSize: 10,
                                        color:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    //const Spacer(),
                    const SizedBox(height: 20),

                    // Resumen de Nodos
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.successGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                ),
                                children: [
                                  TextSpan(text: 'Activos: '),
                                  TextSpan(
                                    text: '${server.activeNodes}',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ), // Gris para inactivos
                            ),
                            const SizedBox(width: 6),
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                ),
                                children: [
                                  TextSpan(text: 'Inactivos: '),
                                  TextSpan(
                                    text: '${server.inactiveNodes}',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================

// PANTALLA DETALLES DEL SERVIDOR

// ==========================================

class ServerDetailScreen extends StatefulWidget {
  final ServerData server;

  const ServerDetailScreen({super.key, required this.server});

  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen> {
  List<dynamic> users = [];

  Map<String, dynamic>? selectedUser;

  bool isLoading = true;

  List<String> userLogs = [];

  bool loadingLogs = false;

  @override
  void initState() {
    super.initState();

    fetchUsers();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> fetchUsers() async {
    try {
      final response = await http.get(Uri.parse(widget.server.apiUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (mounted) {
          setState(() {
            users = data['usuarios'] ?? [];

            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');

      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> refreshUserFiles(String username) async {
    if (selectedUser == null) return;

    setState(() {
      if (selectedUser!['archivos'] is Map) {
        selectedUser!['archivos']['status'] = 'cargando';
      }
    });

    try {
      final url = '${widget.server.apiUrl}/$username/actualizar-archivos';

      final response = await http.post(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (mounted) {
          setState(() {
            if (selectedUser != null && selectedUser!['usuario'] == username) {
              final newFiles = Map<String, dynamic>.from(data);

              selectedUser!['archivos'] = newFiles;

              final index = users.indexWhere((u) => u['usuario'] == username);

              if (index != -1) {
                users[index]['archivos'] = newFiles;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error refreshing user files: $e');

      if (mounted &&
          selectedUser != null &&
          selectedUser!['usuario'] == username) {
        setState(() => selectedUser!['archivos']['status'] = 'error');
      }
    }
  }

  Future<void> fetchUserLogs(String username) async {
    setState(() {
      loadingLogs = true;

      userLogs = [];
    });

    try {
      final url = '${widget.server.apiUrl}/$username/logs';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is Map && data.containsKey('logs')) {
          setState(() => userLogs = List<String>.from(data['logs']));
        }
      }
    } catch (e) {
      debugPrint('Error fetching user logs: $e');

      setState(() => userLogs = ['Error al obtener logs: $e']);
    } finally {
      if (mounted) setState(() => loadingLogs = false);
    }
  }

  void navigateToUserDetail() {
    if (selectedUser != null) {
      Navigator.push(
        context,

        MaterialPageRoute(
          builder:
              (_) => UserDetailScreen(
                username: selectedUser!['usuario'],

                serverName: widget.server.name,

                apiUrl: widget.server.apiUrl,

                userData: selectedUser!,
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: Colors.transparent,

        elevation: 0,

        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),

        title: Text(
          widget.server.name,

          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color, // Dynamic

            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),

          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                // BUSCADOR DE USUARIO
                Container(
                  padding: const EdgeInsets.all(20),

                  decoration: AppTheme.cardDecoration(context),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,

                            color: AppTheme.primaryBlue,
                          ),

                          const SizedBox(width: 8),

                          Text(
                            'Buscar Usuario',

                            style: TextStyle(
                              fontSize: 18.0,

                              fontWeight: FontWeight.bold,

                              color:
                                  Theme.of(context).textTheme.titleLarge?.color,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Encuentra un usuario para ver sus colas de paquetes.',

                        style: TextStyle(
                          fontSize: 14,

                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),

                      const SizedBox(height: 16),

                      Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text == '') {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }

                          return users.where((dynamic option) {
                            return option['usuario']
                                .toString()
                                .toLowerCase()
                                .contains(textEditingValue.text.toLowerCase());
                          }).cast<Map<String, dynamic>>();
                        },

                        displayStringForOption:
                            (Map<String, dynamic> option) => option['usuario'],

                        onSelected: (Map<String, dynamic> selection) {
                          setState(() {
                            selectedUser = selection;

                            FocusScope.of(context).unfocus(); // Ocultar teclado
                          });

                          refreshUserFiles(selection['usuario']);

                          fetchUserLogs(selection['usuario']);
                        },

                        fieldViewBuilder: (
                          context,

                          textEditingController,

                          focusNode,

                          onFieldSubmitted,
                        ) {
                          return TextField(
                            controller: textEditingController,

                            focusNode:
                                focusNode, // Usar el nodo del Autocomplete para que funcione la lista

                            onTap: () {
                              textEditingController.clear();

                              setState(() {
                                selectedUser = null;

                                userLogs = [];
                              });
                            },

                            onChanged: (value) {
                              if (value.isEmpty) {
                                setState(() => selectedUser = null);

                                setState(() => userLogs = []);
                              }
                            },

                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodyLarge?.color,
                            ),

                            decoration: InputDecoration(
                              hintText:
                                  isLoading
                                      ? 'Cargando usuarios...'
                                      : 'Nombre de usuario...',

                              hintStyle: TextStyle(
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                              ),

                              prefixIcon: Icon(
                                Icons.person_rounded,

                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                              ),

                              filled: true,

                              fillColor:
                                  Theme.of(context).scaffoldBackgroundColor,

                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),

                                borderSide: BorderSide.none,
                              ),

                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),

                                borderSide: const BorderSide(
                                  color: AppTheme.primaryBlue,

                                  width: 1,
                                ),
                              ),
                            ),

                            onSubmitted: (String value) {
                              if (value.isEmpty) return;

                              final normalizedValue = value.toLowerCase();

                              // Buscar coincidencias en la lista de usuarios

                              final matches =
                                  users.where((user) {
                                    return user['usuario']
                                        .toString()
                                        .toLowerCase()
                                        .contains(normalizedValue);
                                  }).toList();

                              if (matches.isNotEmpty) {
                                // Seleccionar el primer resultado (predicción)

                                final selection = matches.first;

                                setState(() {
                                  selectedUser = selection;
                                });

                                FocusScope.of(
                                  context,
                                ).unfocus(); // Ocultar teclado

                                textEditingController.text =
                                    selection['usuario'];

                                refreshUserFiles(selection['usuario']);

                                fetchUserLogs(selection['usuario']);

                                // Si el texto ya coincidía exactamente, navegar a detalles

                                if (selection['usuario']
                                        .toString()
                                        .toLowerCase() ==
                                    normalizedValue) {
                                  navigateToUserDetail();
                                }
                              }
                            },
                          );
                        },

                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,

                            child: Material(
                              elevation: 4.0,

                              color: Theme.of(context).cardColor,

                              borderRadius: BorderRadius.circular(12),

                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 200,

                                  maxWidth: 300,
                                ),

                                child: ListView.builder(
                                  padding: EdgeInsets.zero,

                                  shrinkWrap: true,

                                  itemCount: options.length,

                                  itemBuilder: (
                                    BuildContext context,

                                    int index,
                                  ) {
                                    final option = options.elementAt(index);

                                    return ListTile(
                                      title: Text(
                                        option['usuario'],

                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyLarge?.color,
                                        ),
                                      ),

                                      onTap: () {
                                        onSelected(option);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,

                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,

                            padding: const EdgeInsets.symmetric(vertical: 16),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                          onPressed:
                              (selectedUser != null &&
                                      (selectedUser!['archivos']['status'] ==
                                              'ok' ||
                                          selectedUser!['archivos']['status'] ==
                                              'calculating'))
                                  ? navigateToUserDetail
                                  : null,

                          child:
                              (selectedUser != null &&
                                      selectedUser!['archivos']['status'] ==
                                          'cargando')
                                  ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,

                                    children: [
                                      const SizedBox(
                                        width: 20,

                                        height: 20,

                                        child: CircularProgressIndicator(
                                          color: Colors.white,

                                          strokeWidth: 2,
                                        ),
                                      ),

                                      const SizedBox(width: 12),

                                      const Text(
                                        'Cargando Detalles...',

                                        style: TextStyle(
                                          color: Colors.white,

                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                  : const Text(
                                    'Ver Detalles de Usuario',

                                    style: TextStyle(
                                      color: Colors.white,

                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // SERVICIOS
                Text(
                  'Cantidad de Paquetes',

                  style: TextStyle(
                    fontSize: 14,

                    fontWeight: FontWeight.bold,

                    color: Theme.of(context).textTheme.bodyMedium?.color,

                    letterSpacing: 1.0,
                  ),
                ),

                const SizedBox(height: 12),

                if (selectedUser != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),

                    decoration: AppTheme.cardDecoration(context),

                    clipBehavior: Clip.antiAlias,

                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),

                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: AppTheme.borderColor),
                            ),
                          ),

                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,

                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),

                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).dividerColor.withOpacity(0.1),

                                      borderRadius: BorderRadius.circular(8),
                                    ),

                                    child: const Icon(
                                      Icons.arrow_downward_rounded,

                                      color: AppTheme.successGreen,

                                      size: 16,
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  Text(
                                    'Cola de Entrada Global',

                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,

                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),

                              Row(
                                children: [
                                  Text(
                                    '${selectedUser!['archivos']['input']} ',

                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleLarge?.color,

                                      fontWeight: FontWeight.bold,

                                      fontSize: 18,
                                    ),
                                  ),

                                  if (selectedUser!['archivos']['status'] ==
                                      'cargando')
                                    const SizedBox(
                                      width: 16,

                                      height: 16,

                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else if (selectedUser!['archivos']['status'] ==
                                          'ok' ||
                                      selectedUser!['archivos']['status'] ==
                                          'calculating')
                                    const Icon(
                                      Icons.check_circle_rounded,

                                      color: AppTheme.successGreen,

                                      size: 20,
                                    )
                                  else
                                    const Icon(
                                      Icons.error_outline_rounded,

                                      color: AppTheme.errorRed,

                                      size: 20,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        Container(
                          padding: const EdgeInsets.all(16),

                          color: Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withOpacity(0.5),

                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,

                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),

                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).dividerColor.withOpacity(0.1),

                                      borderRadius: BorderRadius.circular(8),
                                    ),

                                    child: const Icon(
                                      Icons.arrow_upward_rounded,

                                      color: AppTheme.primaryBlue,

                                      size: 16,
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  Text(
                                    'Colas de Salida Totales',

                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,

                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,

                                  vertical: 4,
                                ),

                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).dividerColor.withOpacity(0.1),

                                  borderRadius: BorderRadius.circular(20),

                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),

                                child: Text(
                                  '${(selectedUser!['archivos']['output'] as Map).length} destinos',

                                  style: TextStyle(
                                    color:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,

                                    fontWeight: FontWeight.bold,

                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'Seleccione un usuario para ver la información.',

                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),

                const SizedBox(height: 24),

                // CONSOLA DE LOGS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                  children: [
                    Text(
                      selectedUser != null
                          ? 'LOGS ${selectedUser!['usuario']}'
                          : 'CONSOLA / LOGS EN VIVO',

                      style: TextStyle(
                        fontSize: 14,

                        fontWeight: FontWeight.bold,

                        color: Theme.of(context).textTheme.bodyMedium?.color,

                        letterSpacing: 1.0,
                      ),
                    ),

                    TextButton.icon(
                      onPressed: () {
                        if (userLogs.isNotEmpty) {
                          Clipboard.setData(
                            ClipboardData(text: userLogs.join('\n')),
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Logs copiados al portapapeles'),

                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },

                      icon: const Icon(Icons.copy_all_rounded, size: 14),

                      label: const Text(
                        'Copiar',

                        style: TextStyle(fontSize: 12),
                      ),

                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Container(
                  width: double.infinity,

                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,

                    borderRadius: BorderRadius.circular(16),

                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children:
                        selectedUser != null
                            ? (loadingLogs
                                ? [
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ]
                                : userLogs.isEmpty
                                ? [
                                  Text(
                                    'No hay logs recientes.',

                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ]
                                : userLogs
                                    .map(
                                      (line) => Text(
                                        line,

                                        style: AppTheme.monoStyle.copyWith(
                                          fontSize: 12,

                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                        ),
                                      ),
                                    )
                                    .toList())
                            : widget.server.logs
                                .map(
                                  (log) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),

                                    child: RichText(
                                      text: TextSpan(
                                        style: AppTheme.monoStyle.copyWith(
                                          fontSize: 12,
                                        ),

                                        children: [
                                          TextSpan(
                                            text: '[${log.time}] ',

                                            style: TextStyle(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium?.color,
                                            ),
                                          ),

                                          TextSpan(
                                            text: '${log.type.toUpperCase()}: ',

                                            style: TextStyle(
                                              color:
                                                  log.type == 'error'
                                                      ? AppTheme.errorRed
                                                      : log.type == 'warn'
                                                      ? AppTheme.warningAmber
                                                      : AppTheme.successGreen,

                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),

                                          TextSpan(
                                            text: log.msg,

                                            style: TextStyle(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium?.color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
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

// ==========================================

// PANTALLA DETALLES DEL USUARIO

// ==========================================

class UserDetailScreen extends StatefulWidget {
  final String username;

  final String serverName;

  final String apiUrl;

  final Map<String, dynamic> userData;

  const UserDetailScreen({
    super.key,

    required this.username,

    required this.serverName,

    required this.apiUrl,

    required this.userData,
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late Map<String, dynamic> currentUserData;

  Timer? pollingTimer;

  @override
  void initState() {
    super.initState();

    currentUserData = widget.userData;

    // Verificar si hay elementos pendientes (-1) o si el estado es 'calculating'

    bool hasPending = false;

    if (currentUserData['archivos']['output'] is Map) {
      final outputs = currentUserData['archivos']['output'] as Map;

      hasPending = outputs.values.any((val) => val.toString() == '-1');
    }

    if (currentUserData['archivos']['status'] == 'calculating' || hasPending) {
      startPolling();
    }
  }

  @override
  void dispose() {
    pollingTimer?.cancel();

    super.dispose();
  }

  void startPolling() {
    pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();

        return;
      }

      try {
        // Consultamos el endpoint GET que devuelve el estado de la caché sin reiniciar el conteo

        final url = '${widget.apiUrl}/${widget.username}/archivos';

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (mounted) {
            setState(() => currentUserData['archivos'] = data);

            // Si el estado ya es 'ok' (terminó de contar) o 'error', detenemos el polling

            if (data['status'] == 'ok' || data['status'] == 'error') {
              timer.cancel();
            }
          }
        }
      } catch (e) {
        debugPrint('Error polling user files: $e');
      }
    });
  }

  // Método para refrescar manualmente dentro de la pantalla

  Future<void> refreshData() async {
    // Reinicia el conteo en el servidor (POST)

    try {
      setState(() {
        if (currentUserData['archivos'] is Map) {
          currentUserData['archivos']['status'] = 'calculating';
        }
      });

      final url = '${widget.apiUrl}/${widget.username}/actualizar-archivos';

      final response = await http.post(Uri.parse(url));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);

        // Actualizamos inmediatamente con la respuesta inicial (que tiene los -1)

        setState(() => currentUserData['archivos'] = data);
      }

      // Reiniciamos el polling para ver el progreso del nuevo conteo

      pollingTimer?.cancel();

      startPolling();
    } catch (e) {
      debugPrint('Error refreshing data manually: $e');
    }
  }

  Future<void> handleRestartService() async {
    final String type = widget.userData['tipo_instalacion'] ?? 'server';

    String title = 'Reiniciar Servicio';

    String content = '';

    if (type == 'server_node') {
      content =
          'Se reiniciarán los servicios:\n- petroboxreplicatorserver\n- petroboxreplicatornode\n\n¿Estás seguro?';
    } else if (type == 'node') {
      content =
          'Se reiniciará el servicio:\n- petroboxreplicatornode\n\n¿Estás seguro?';
    } else {
      content =
          'Se reiniciará el servicio:\n- petroboxreplicatorserver\n\n¿Estás seguro?';
    }

    final bool? confirm = await showDialog<bool>(
      context: context,

      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).cardColor,

            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,

                  color: AppTheme.warningAmber,
                ),

                const SizedBox(width: 10),

                Text(
                  title,

                  style: TextStyle(
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),

            content: Text(
              content,

              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),

            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),

                child: const Text('Cancelar'),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorRed,
                ),

                onPressed: () => Navigator.pop(context, true),

                child: const Text(
                  'Reiniciar',

                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enviando orden de reinicio...'),

          backgroundColor: AppTheme.primaryBlue,
        ),
      );

      try {
        final url = '${widget.apiUrl}/${widget.username}/reiniciar-servicios';

        final response = await http.post(Uri.parse(url));

        if (mounted) {
          if (response.statusCode == 200) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Servicios reiniciados correctamente.'),

                backgroundColor: AppTheme.successGreen,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al reiniciar: ${response.body}'),

                backgroundColor: AppTheme.errorRed,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error de conexión: $e'),

              backgroundColor: AppTheme.errorRed,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Datos reales

    final int inQueue = currentUserData['archivos']['input'] ?? 0;

    // Aseguramos que outputs sea un Map válido y lo ordenamos

    final Map<String, dynamic> outputs =
        currentUserData['archivos']['output'] != null
            ? Map<String, dynamic>.from(currentUserData['archivos']['output'])
            : {};

    final List<String> sortedKeys = outputs.keys.toList()..sort();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: Colors.transparent,

        elevation: 0,

        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),

        title: Text(
          'Perfil de Usuario',

          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color, // Dynamic

            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),

          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                // CABECERA USUARIO
                Container(
                  padding: const EdgeInsets.all(24),

                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).cardColor,
                        Theme.of(context).scaffoldBackgroundColor,
                      ],

                      begin: Alignment.topLeft,

                      end: Alignment.bottomRight,
                    ),

                    borderRadius: BorderRadius.circular(24),

                    border: Border.all(color: Theme.of(context).dividerColor),

                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withOpacity(0.1),

                        blurRadius: 10,

                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),

                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,

                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          borderRadius: BorderRadius.circular(16),

                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryBlue.withOpacity(0.3),

                              blurRadius: 10,

                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),

                        child: Center(
                          child: Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),

                      const SizedBox(width: 20),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              widget.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // Mantener blanco porque el fondo es oscuro (gradient)
                                fontSize: 18,

                                fontWeight: FontWeight.bold,

                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.titleLarge?.color,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Row(
                              children: [
                                Icon(
                                  Icons.dns_rounded,

                                  size: 16,

                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                ),

                                const SizedBox(width: 4),

                                Text(
                                  'Alojado en ${widget.serverName}',

                                  style: TextStyle(
                                    color:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.errorRed.withOpacity(0.1),

                          borderRadius: BorderRadius.circular(12),

                          border: Border.all(
                            color: AppTheme.errorRed.withOpacity(0.3),
                          ),
                        ),

                        child: IconButton(
                          icon: const Icon(Icons.restart_alt_rounded),

                          color: AppTheme.errorRed,

                          tooltip: 'Reiniciar Servicios Replicator',

                          onPressed: handleRestartService,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // TARJETAS DE PAQUETES

                // Input
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                  children: [
                    Text(
                      'COLA DE ENTRADA (INPUT)',

                      style: TextStyle(
                        fontSize: 14,

                        fontWeight: FontWeight.bold,

                        color: Theme.of(context).textTheme.bodyMedium?.color,

                        letterSpacing: 1.0,
                      ),
                    ),

                    IconButton(
                      onPressed: refreshData,

                      icon: Icon(
                        Icons.refresh_rounded,

                        color: Theme.of(context).textTheme.bodyMedium?.color,

                        size: 18,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                buildQueueCard(
                  context,

                  'Paquetes Recibidos',

                  inQueue.toString(),

                  AppTheme.successGreen,

                  Icons.arrow_downward_rounded,

                  isInput: true,
                ),

                const SizedBox(height: 24),

                Text(
                  'Colas de Salida (${outputs.length})',

                  style: TextStyle(
                    fontSize: 14,

                    fontWeight: FontWeight.bold,

                    color: Theme.of(context).textTheme.bodyMedium?.color,

                    letterSpacing: 1.0,
                  ),
                ),

                const SizedBox(height: 12),

                ...sortedKeys.map((key) {
                  // Limpiar nombre para mostrar (quitar GUID si es muy largo o dejarlo como referencia)

                  // Mostramos la clave completa o la última parte si tiene '/'

                  String displayName = key;

                  final value = outputs[key];

                  if (displayName.contains('/')) {
                    displayName = displayName.split('/').last;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),

                    child: buildQueueCard(
                      context,

                      displayName,

                      value.toString(),

                      AppTheme.primaryBlue,

                      Icons.arrow_upward_rounded,
                    ),
                  );
                }),

                if (outputs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),

                    child: Text(
                      "No hay colas de salida configuradas.",

                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildQueueCard(
    BuildContext context,

    String title,

    String count,

    Color color,

    IconData icon, {

    bool isInput = false,
  }) {
    final int countVal = int.tryParse(count) ?? 0;

    final bool isLoading = countVal == -1; // -1 indica cargando

    final bool hasTraffic = countVal > 0;

    final Color activeColor =
        hasTraffic
            ? (isInput ? AppTheme.successGreen : AppTheme.errorRed)
            : (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey);

    final Color bgIcon =
        (hasTraffic || isLoading)
            ? activeColor.withOpacity(0.1)
            : Theme.of(context).scaffoldBackgroundColor;

    return Container(
      padding: const EdgeInsets.all(20),

      decoration: AppTheme.cardDecoration(context),

      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(
              color: bgIcon,

              borderRadius: BorderRadius.circular(16),

              border: Border.all(
                color:
                    (hasTraffic || isLoading)
                        ? activeColor.withOpacity(0.2)
                        : Colors.transparent,
              ),
            ),

            child:
                isLoading
                    ? SizedBox(
                      width: 20,
                      height: 20,

                      child: CircularProgressIndicator(
                        strokeWidth: 2,

                        color: AppTheme.primaryBlue,
                      ),
                    )
                    : Icon(
                      icon,

                      color:
                          hasTraffic
                              ? activeColor
                              : (Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.color ??
                                  Colors.grey),

                      size: 20,
                    ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: AppTheme.monoStyle.copyWith(
                    fontSize: 11,

                    fontWeight: FontWeight.bold,

                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),

                const SizedBox(height: 4),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,

                  textBaseline: TextBaseline.alphabetic,

                  children: [
                    isLoading
                        ? Text(
                          "Cargando...",

                          style: TextStyle(
                            fontSize: 18,

                            color:
                                Theme.of(context).textTheme.bodyMedium?.color,

                            fontStyle: FontStyle.italic,
                          ),
                        )
                        : Text(
                          count,

                          style: TextStyle(
                            fontSize: 24,

                            fontWeight: FontWeight.w300,

                            color:
                                Theme.of(context).textTheme.displaySmall?.color,
                          ),
                        ),

                    const SizedBox(width: 6),

                    const Text(
                      'paquetes',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (isInput && countVal == 0)
            const Text(
              "Todo al día",

              style: TextStyle(
                color: AppTheme.successGreen,

                fontSize: 12,

                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}
