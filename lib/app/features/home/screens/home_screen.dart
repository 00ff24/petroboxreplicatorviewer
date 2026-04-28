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

  final String diskUsage;

  // Datos crudos para las barras de progreso

  final double rawCpu;

  final double rawRamPercent;

  final double rawDiskPercent;

  ServerData({
    required this.id,

    required this.name,

    required this.apiUrl,

    required this.status,

    required this.ip,

    required this.cpuUsage,

    required this.ramUsage,

    required this.diskUsage,

    required this.uptime,

    required this.activeNodes,

    required this.inactiveNodes,

    required this.os,

    required this.services,

    required this.logs,

    required this.rawCpu,

    required this.rawRamPercent,

    required this.rawDiskPercent,
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

    'diskUsage': diskUsage,

    'rawCpu': rawCpu,

    'rawRamPercent': rawRamPercent,

    'rawDiskPercent': rawDiskPercent,
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

      diskUsage: json['diskUsage'] ?? 'N/A',

      rawCpu: (json['rawCpu'] as num?)?.toDouble() ?? 0.0,

      rawRamPercent: (json['rawRamPercent'] as num?)?.toDouble() ?? 0.0,

      rawDiskPercent: (json['rawDiskPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ServerManager {
  static const String _cacheKey = 'cached_servers_data';

  static const List<String> apiEndpoints = [
    'http://bilbo.petroboxinc.com:5001/sistema/status',

    'http://aragorn.petroboxinc.com:5001/sistema/status',

    'http://frodo.petroboxinc.com:5001/sistema/status',

    'http://gandalf.petroboxinc.com:5001/sistema/status',
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

      diskUsage: 'N/A',

      uptime: 'Offline',

      activeNodes: 0,

      inactiveNodes: 0,

      os: 'Unknown',

      services: [],

      logs: [],

      rawCpu: 0.0,

      rawRamPercent: 0.0,

      rawDiskPercent: 0.0,
    );
  }

  static Future<bool> restartMachine(ServerData server) async {
    try {
      // La URL actual es "...:5001/usuarios", necesitamos "...:5001/sistema/reiniciar"

      final baseUrl = server.apiUrl.split('/sistema/status').first;

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

    // 4. Disco (Usado / Total)

    final discoData = sistema['disco'];

    String diskUsage = 'N/A';

    double diskPercent = 0.0;

    if (discoData != null && discoData is Map) {
      final double total = (discoData['total_gb'] as num).toDouble();

      final double libre = (discoData['libre_gb'] as num).toDouble();

      final double usado = total - libre;

      diskPercent = (total > 0) ? (usado / total) * 100 : 0.0;

      diskUsage = '${usado.toStringAsFixed(0)}/${total.toStringAsFixed(0)} GB';
    }

    // 5. Uptime

    final String uptime = sistema['uptime'] ?? 'N/A';

    // 4. Lógica de Estado (Semáforo)

    String status = 'healthy';

    if (cpuLoad >= 90) {
      status = 'error';
    } else if (cpuLoad >= 40) {
      status = 'warning';
    }

    // 5. Nodos Activos/Inactivos (Usamos el contador del nuevo endpoint si existe)

    final int activeNodes =
        data['usuarios_count'] ?? (data['usuarios'] as List?)?.length ?? 0;

    final int inactiveNodes = 0;

    return ServerData(
      id: (data['servidor'] ?? 'unknown').toString().toLowerCase(),

      name: (data['servidor'] ?? 'Unknown').toString().toUpperCase(),

      apiUrl: endpoint,

      status: status,

      ip: ipList.isNotEmpty ? ipList : 'No IP',

      cpuUsage: '${cpuLoad.toStringAsFixed(1)}%',

      ramUsage: ramUsage,

      diskUsage: diskUsage,

      uptime: uptime,

      activeNodes: activeNodes,

      inactiveNodes: inactiveNodes,

      os: sistema['os_version']?.toString() ?? 'Linux',

      services: [],

      logs: [],

      rawCpu: cpuLoad,

      rawRamPercent: ramPercent,

      rawDiskPercent: diskPercent,
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

class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({required this.color, this.size = 8});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.4 * _controller.value),
                blurRadius: 6 * _controller.value,
                spreadRadius: 2 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
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

    final validEndpoints = ServerManager.apiEndpoints.toSet();

    final Map<String, ServerData> currentMap = {
      for (var s in servers)
        if (validEndpoints.contains(s.apiUrl)) s.apiUrl: s,
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

          diskUsage: cached.diskUsage,

          uptime: cached.uptime,

          activeNodes: cached.activeNodes,

          inactiveNodes: cached.inactiveNodes,

          os: cached.os,

          services: cached.services,

          logs: cached.logs,

          rawCpu: cached.rawCpu,

          rawRamPercent: cached.rawRamPercent,

          rawDiskPercent: cached.rawDiskPercent,
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

  void _showOfflineSnackbar(String serverName) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$serverName esta offline',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF475569),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
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
                    child: RefreshIndicator(
                      onRefresh: _refreshServers,
                      color: AppTheme.primaryBlue,
                      child: SingleChildScrollView(
                        physics:
                            const AlwaysScrollableScrollPhysics(), // Obligatorio para que funcione el pull-to-refresh
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryBlue,
                    AppTheme.primaryBlue.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'P',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
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
                    const _PulsingDot(color: AppTheme.successGreen, size: 8),
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

    final bool isOffline = server.status == 'offline';

    return Opacity(
      opacity: isOffline ? 0.55 : 1.0,
      child: Container(
      padding: const EdgeInsets.all(20),

      decoration: AppTheme.cardDecoration(context),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,

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
                if (isOffline) {
                  _showOfflineSnackbar(server.name);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServerDetailScreen(server: server),
                    ),
                  );
                }
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
                  if (isOffline) {
                    _showOfflineSnackbar(server.name);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServerDetailScreen(server: server),
                      ),
                    );
                  }
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
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          // CPU
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.memory_rounded,
                                          size: 12,
                                          color: Theme.of(context).textTheme.bodyMedium?.color,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'CPU',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${server.rawCpu.toStringAsFixed(0)}%',
                                      style: AppTheme.monoStyle.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: server.rawCpu > 80
                                            ? AppTheme.errorRed
                                            : server.rawCpu > 50
                                            ? AppTheme.warningAmber
                                            : Theme.of(context).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (server.rawCpu / 100).clamp(0.0, 1.0),
                                    minHeight: 5,
                                    backgroundColor: Theme.of(context).dividerColor.withOpacity(0.1),
                                    color: server.rawCpu > 80
                                        ? AppTheme.errorRed
                                        : server.rawCpu > 50
                                        ? AppTheme.warningAmber
                                        : AppTheme.successGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          // RAM
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.sd_storage_rounded,
                                          size: 12,
                                          color: Theme.of(context).textTheme.bodyMedium?.color,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'RAM',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      server.ramUsage,
                                      style: AppTheme.monoStyle.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (server.rawRamPercent / 100).clamp(0.0, 1.0),
                                    minHeight: 5,
                                    backgroundColor: Theme.of(context).dividerColor.withOpacity(0.1),
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Disco
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.storage_rounded,
                                    size: 12,
                                    color: Theme.of(context).textTheme.bodyMedium?.color,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'DISCO',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                server.diskUsage,
                                style: AppTheme.monoStyle.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: server.rawDiskPercent > 90
                                      ? AppTheme.errorRed
                                      : server.rawDiskPercent > 75
                                      ? AppTheme.warningAmber
                                      : Theme.of(context).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (server.rawDiskPercent / 100).clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: Theme.of(context).dividerColor.withOpacity(0.1),
                              color: server.rawDiskPercent > 90
                                  ? AppTheme.errorRed
                                  : server.rawDiskPercent > 75
                                  ? AppTheme.warningAmber
                                  : AppTheme.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),

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
  List<Map<String, dynamic>> randomUsers = []; // 5 usuarios aleatorios para preview

  Map<String, dynamic>? selectedUser; // Usuario seleccionado en el buscador
  Map<String, dynamic>? _detailedUser; // Usuario "fijado" para mostrar detalles
  bool _isUserDetailExpanded = false; // Controla si el panel está expandido

  bool isLoading = true;

  // Controlador para poder limpiar el texto desde el icono X si fuera necesario
  TextEditingController? _searchController;

  // Key para controlar el widget hijo UserDetailContent desde aquí (el padre)
  final GlobalKey<UserDetailContentState> _userDetailKey = GlobalKey();

  // Getter para obtener la base de usuarios reemplazando la ruta de status
  String get usersBaseUrl =>
      widget.server.apiUrl.replaceAll('/sistema/status', '/usuarios');

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
      final response = await http.get(Uri.parse(usersBaseUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (mounted) {
          setState(() {
            users = data['usuarios'] ?? [];

            // Seleccionar hasta 5 usuarios aleatorios para preview
            if (users.length > 5) {
              final shuffled = List<dynamic>.from(users)..shuffle(Random());
              randomUsers = shuffled.take(5).cast<Map<String, dynamic>>().toList();
            } else {
              randomUsers = users.cast<Map<String, dynamic>>().toList();
            }

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
      } else {
        selectedUser!['archivos'] = {
          'status': 'cargando',
          'input': 0,
          'output': {},
        };
      }
    });

    try {
      final url = '$usersBaseUrl/$username/actualizar-archivos';
      debugPrint('[refreshUserFiles] POST $url');

      final response = await http.post(Uri.parse(url));
      debugPrint('[refreshUserFiles] Status: ${response.statusCode}');
      debugPrint('[refreshUserFiles] Body: ${response.body}');

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
      debugPrint('[refreshUserFiles] Error: $e');

      if (mounted &&
          selectedUser != null &&
          selectedUser!['usuario'] == username) {
        setState(() {
          if (selectedUser!['archivos'] is Map) {
            selectedUser!['archivos']['status'] = 'error';
          } else {
            selectedUser!['archivos'] = {
              'status': 'error',
              'input': 0,
              'output': {},
            };
          }
        });
      }
    }
  }

  // Lógica unificada: Seleccionar + Cargar + Mostrar
  void _onUserSelected(Map<String, dynamic> selection) {
    // Asegurar que archivos tenga una estructura válida antes de mostrar detalles
    if (selection['archivos'] is! Map) {
      selection['archivos'] = {
        'status': 'cargando',
        'input': 0,
        'output': {},
      };
    }

    setState(() {
      selectedUser = selection;
      _detailedUser = selection; // Mostrar detalles inmediatamente
      _isUserDetailExpanded = true; // Expandir panel automáticamente
      FocusScope.of(context).unfocus(); // Ocultar teclado
    });

    // Actualizar texto del buscador si tenemos el controlador
    if (_searchController != null &&
        _searchController!.text != selection['usuario']) {
      _searchController!.text = selection['usuario'];
    }

    refreshUserFiles(selection['usuario']);
  }

  Future<void> handleRestartService(Map<String, dynamic> user) async {
    final String type = user['tipo_instalacion'] ?? 'server';
    final String username = user['usuario'];
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
        final url = '$usersBaseUrl/$username/reiniciar-servicios';
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

  Widget _buildUserPreviewCard(Map<String, dynamic> user) {
    return GestureDetector(
      onTap: () => _onUserSelected(user),
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).cardColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['usuario'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.dns_rounded,
                        size: 12,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Alojado en ${widget.server.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () => handleRestartService(user),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.errorRed.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.restart_alt_rounded,
                            size: 12,
                            color: AppTheme.errorRed,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'REINICIAR',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.errorRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (user['tipo_instalacion'] == 'server_node' ||
                          user['tipo_instalacion'] == 'server')
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withOpacity(0.3),
                              ),
                            ),
                            child: const Text(
                              'SERVER',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                          ),
                        ),
                      if (user['tipo_instalacion'] == 'server_node')
                        const SizedBox(width: 4),
                      if (user['tipo_instalacion'] == 'server_node' ||
                          user['tipo_instalacion'] == 'node')
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.successGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.successGreen.withOpacity(0.3),
                              ),
                            ),
                            child: const Text(
                              'NODE',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.successGreen,
                              ),
                            ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          padding: EdgeInsets.zero,
                          tooltip: 'Volver',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Autocomplete<Map<String, dynamic>>(
                              optionsBuilder: (
                                TextEditingValue textEditingValue,
                              ) {
                                if (textEditingValue.text == '') {
                                  return const Iterable<
                                    Map<String, dynamic>
                                  >.empty();
                                }
                                return users.where((dynamic option) {
                                  return option['usuario']
                                      .toString()
                                      .toLowerCase()
                                      .contains(
                                        textEditingValue.text.toLowerCase(),
                                      );
                                }).cast<Map<String, dynamic>>();
                              },
                              displayStringForOption:
                                  (Map<String, dynamic> option) =>
                                      option['usuario'],
                              onSelected: _onUserSelected,
                              fieldViewBuilder: (
                                context,
                                textEditingController,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                _searchController = textEditingController;
                                return TextField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  autofocus: true,
                                  style: TextStyle(
                                    color:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                    fontSize: 14,
                                  ),
                                  decoration: InputDecoration(
                                    hintText:
                                        isLoading
                                            ? 'Cargando usuarios...'
                                            : 'Buscar en ${widget.server.name}...',
                                    hintStyle: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                      fontSize: 14,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      size: 20,
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                    ),
                                    suffixIcon:
                                        textEditingController.text.isNotEmpty
                                            ? IconButton(
                                              icon: Icon(
                                                Icons.close,
                                                size: 18,
                                                color:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.color,
                                              ),
                                              onPressed: () {
                                                textEditingController.clear();
                                                setState(() {
                                                  selectedUser = null;
                                                  _detailedUser = null;
                                                });
                                              },
                                            )
                                            : null,
                                    filled: true,
                                    fillColor: Theme.of(context).cardColor,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 16,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.primaryBlue,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (String value) {
                                    if (value.isEmpty) return;
                                    final normalizedValue = value.toLowerCase();
                                    final matches =
                                        users.where((user) {
                                          return user['usuario']
                                              .toString()
                                              .toLowerCase()
                                              .contains(normalizedValue);
                                        }).toList();
                                    if (matches.isNotEmpty) {
                                      _onUserSelected(matches.first);
                                    }
                                  },
                                );
                              },
                              optionsViewBuilder: (
                                context,
                                onSelected,
                                options,
                              ) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 8.0,
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(12),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: 300,
                                        maxWidth: constraints.maxWidth,
                                      ),
                                      child: ListView.separated(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        separatorBuilder:
                                            (context, index) => Divider(
                                              height: 1,
                                              color: Theme.of(
                                                context,
                                              ).dividerColor.withOpacity(0.1),
                                            ),
                                        itemBuilder: (
                                          BuildContext context,
                                          int index,
                                        ) {
                                          final option = options.elementAt(
                                            index,
                                          );
                                          return ListTile(
                                            dense: true,
                                            leading: const Icon(
                                              Icons.person_outline_rounded,
                                              size: 18,
                                            ),
                                            title: Text(
                                              option['usuario'],
                                              style: TextStyle(
                                                color:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.color,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            onTap: () => onSelected(option),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (selectedUser != null)
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          margin: const EdgeInsets.only(bottom: 16),
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
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).shadowColor.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedUser!['usuario'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
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
                                          size: 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Alojado en ${widget.server.name}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium?.color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              IntrinsicWidth(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    InkWell(
                                      onTap:
                                          () => handleRestartService(
                                            selectedUser!,
                                          ),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.errorRed.withOpacity(
                                            0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: AppTheme.errorRed
                                                .withOpacity(0.3),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.restart_alt_rounded,
                                              size: 14,
                                              color: AppTheme.errorRed,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'REINICIAR',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.errorRed,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (selectedUser!['tipo_instalacion'] ==
                                                'server_node' ||
                                            selectedUser!['tipo_instalacion'] ==
                                                'server')
                                          Expanded(
                                            child: Container(
                                              alignment: Alignment.center,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryBlue
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: AppTheme.primaryBlue
                                                      .withOpacity(0.3),
                                                ),
                                              ),
                                              child: const Text(
                                                'SERVER',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.primaryBlue,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (selectedUser!['tipo_instalacion'] ==
                                            'server_node')
                                          const SizedBox(width: 6),
                                        if (selectedUser!['tipo_instalacion'] ==
                                                'server_node' ||
                                            selectedUser!['tipo_instalacion'] ==
                                                'node')
                                          Expanded(
                                            child: Container(
                                              alignment: Alignment.center,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.successGreen
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: AppTheme.successGreen
                                                      .withOpacity(0.3),
                                                ),
                                              ),
                                              child: const Text(
                                                'NODE',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.successGreen,
                                                ),
                                              ),
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
                        Container(
                          decoration: AppTheme.cardDecoration(context),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              InkWell(
                                onTap:
                                    _detailedUser != null
                                        ? () => setState(
                                          () =>
                                              _isUserDetailExpanded =
                                                  !_isUserDetailExpanded,
                                        )
                                        : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  color: Theme.of(
                                    context,
                                  ).scaffoldBackgroundColor.withOpacity(0.5),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).dividerColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          _detailedUser != null
                                              ? Icons.analytics_rounded
                                              : Icons.arrow_upward_rounded,
                                          color: AppTheme.primaryBlue,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        _detailedUser != null
                                            ? 'Monitorización y Logs'
                                            : 'Cola de salida',
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (_detailedUser != null)
                                        InkWell(
                                          onTap: () {
                                            _userDetailKey.currentState
                                                ?.refreshData();
                                          },
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                              horizontal: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).dividerColor,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.refresh_rounded,
                                                  size: 14,
                                                  color:
                                                      Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.color,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'RECARGAR',
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.color,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.fastOutSlowIn,
                                child: Visibility(
                                  visible:
                                      _isUserDetailExpanded &&
                                      _detailedUser != null,
                                  maintainState: true,
                                  child:
                                      _detailedUser != null
                                          ? UserDetailContent(
                                            key: _userDetailKey,
                                            username: _detailedUser!['usuario'],
                                            serverName: widget.server.name,
                                            apiUrl: usersBaseUrl,
                                            userData: _detailedUser!,
                                          )
                                          : const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else if (randomUsers.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Usuarios',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...randomUsers.map((user) => _buildUserPreviewCard(user)),
                      ],
                    )
                  else if (isLoading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Text(
                          'No se encontraron usuarios',
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================

// PANTALLA DETALLES DEL USUARIO
// (Ahora un Widget embebible)
// ==========================================

class UserDetailContent extends StatefulWidget {
  final String username;

  final String serverName;

  final String apiUrl;

  final Map<String, dynamic> userData;

  const UserDetailContent({
    super.key,

    required this.username,

    required this.serverName,

    required this.apiUrl,

    required this.userData,
  });

  @override
  State<UserDetailContent> createState() => UserDetailContentState();
}

class UserDetailContentState extends State<UserDetailContent> {
  late Map<String, dynamic> currentUserData;

  Timer? pollingTimer;

  // Estado para los logs
  List<String> userLogs = [];

  bool loadingLogs = true;

  bool _isOutputExpanded = false;

  // Si está en null, muestra logs del usuario. Si tiene un valor, muestra logs de ese nodo.
  String? activeNodeForLogs;

  @override
  void initState() {
    super.initState();
    currentUserData = Map<String, dynamic>.from(widget.userData);
    _checkAndStartPolling();
    // Cargar los logs al iniciar la pantalla
    fetchUserLogs();
  }

  @override
  void didUpdateWidget(UserDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Si el usuario cambia, reiniciamos el estado (necesario por usar GlobalKey)
    if (widget.username != oldWidget.username) {
      setState(() {
        currentUserData = Map<String, dynamic>.from(widget.userData);
        userLogs = [];
        loadingLogs = true;
      });
      fetchUserLogs();
      _checkAndStartPolling();
      return;
    }

    // Si recibimos nuevos datos del padre (ej: post-carga inicial), actualizamos la copia local y verificamos si hay que sondear
    if (widget.userData['archivos'] != currentUserData['archivos']) {
      setState(() {
        currentUserData = Map<String, dynamic>.from(widget.userData);
      });
      _checkAndStartPolling();
    }
  }

  void _checkAndStartPolling() {
    bool hasPending = false;
    if (currentUserData['archivos'] is Map &&
        currentUserData['archivos']['output'] is Map) {
      final outputs = currentUserData['archivos']['output'] as Map;
      hasPending = outputs.values.any((val) => val.toString() == '-1');
    }

    if ((currentUserData['archivos'] is Map &&
            currentUserData['archivos']['status'] == 'calculating') ||
        hasPending) {
      if (pollingTimer == null || !pollingTimer!.isActive) {
        startPolling();
      }
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
    fetchUserLogs(); // También recargamos los logs
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

  Future<void> fetchUserLogs() async {
    if (!mounted) return;
    setState(() {
      loadingLogs = true;
      userLogs = [];
      activeNodeForLogs = null;
    });

    try {
      final url = '${widget.apiUrl}/${widget.username}/logs';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('logs')) {
          if (mounted) {
            setState(() => userLogs = List<String>.from(data['logs']));
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching user logs: $e');
      if (mounted) {
        setState(() => userLogs = ['Error al obtener logs: $e']);
      }
    } finally {
      if (mounted) setState(() => loadingLogs = false);
    }
  }

  Future<void> fetchNodeLogs(String nodo) async {
    if (!mounted) return;
    setState(() {
      loadingLogs = true;
      userLogs = [];
      activeNodeForLogs = nodo;
    });

    final url = '${widget.apiUrl}/${widget.username}/nodos/$nodo/logs';
    debugPrint('[FETCH-NODE-LOGS] GET $url');

    try {
      final response = await http.get(Uri.parse(url));
      debugPrint('[FETCH-NODE-LOGS] Status: ${response.statusCode}');
      debugPrint('[FETCH-NODE-LOGS] Body: ${response.body}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('logs')) {
          if (mounted) {
            setState(() => userLogs = List<String>.from(data['logs']));
          }
        }
      } else {
        if (mounted) {
          setState(() => userLogs = ['Error al obtener logs del nodo: ${response.statusCode}', response.body]);
        }
      }
    } catch (e) {
      debugPrint('[FETCH-NODE-LOGS] Exception: $e');
      if (mounted) {
        setState(() => userLogs = ['Error al obtener logs del nodo: $e']);
      }
    } finally {
      if (mounted) setState(() => loadingLogs = false);
    }
  }

  Future<void> restartNodeService(String nodo) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => NodeServicesDialog(
        apiUrl: widget.apiUrl,
        username: widget.username,
        nodo: nodo,
      ),
    );
  }

  void copyLogsToClipboard() {
    if (userLogs.isEmpty) return;
    Clipboard.setData(ClipboardData(text: userLogs.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Logs copiados al portapapeles',
          textAlign: TextAlign.center,
        ),
        behavior: SnackBarBehavior.floating,
        width: 260,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        duration: const Duration(seconds: 2),
      ),
    );
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

    // Calcular suma total de paquetes de salida
    int totalOutputPackages = 0;
    for (var val in outputs.values) {
      // Convertir a int, ignorando -1 (calculando) o errores
      int v = int.tryParse(val.toString()) ?? 0;
      if (v > 0) totalOutputPackages += v;
    }

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [
          // TARJETAS DE PAQUETES
          // 1. INPUT (Paquetes Recibidos)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: AppTheme.cardDecoration(context),
            child: Row(
              children: [
                const Icon(
                  Icons.arrow_downward_rounded,
                  size: 20,
                  color: AppTheme.successGreen,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Paquetes Recibidos',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Text(
                  '$inQueue paquetes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color:
                        inQueue > 0
                            ? AppTheme.successGreen
                            : Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. OUTPUT (Paquetes Salida - Expandible)
          InkWell(
            onTap: () => setState(() => _isOutputExpanded = !_isOutputExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: AppTheme.cardDecoration(context),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: AppTheme.errorRed,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Paquetes Salida',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  Text(
                    '$totalOutputPackages paquetes',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color:
                          totalOutputPackages > 0
                              ? AppTheme.primaryBlue
                              : Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Lista detallada de outputs (Solo visible al expandir)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            child:
                _isOutputExpanded
                    ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          if (outputs.isNotEmpty)
                            ...sortedKeys.map((key) {
                              String displayName = key;
                              final value = outputs[key];
                              if (displayName.contains('/')) {
                                displayName = displayName.split('/').last;
                              }
                              final bool isActive = activeNodeForLogs == displayName;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => fetchNodeLogs(displayName),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? AppTheme.primaryBlue.withOpacity(0.08)
                                            : Theme.of(context)
                                                .scaffoldBackgroundColor
                                                .withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isActive
                                              ? AppTheme.primaryBlue.withOpacity(0.5)
                                              : Theme.of(context)
                                                  .dividerColor
                                                  .withOpacity(0.5),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.subdirectory_arrow_right_rounded,
                                            size: 16,
                                            color: isActive
                                                ? AppTheme.primaryBlue
                                                : Theme.of(context).dividerColor,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              displayName,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isActive
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                          ),
                                          if (value.toString() == '-1')
                                            const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          else
                                            Text(
                                              '$value',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: (int.tryParse(
                                                              value.toString(),
                                                            ) ??
                                                            0) >
                                                        0
                                                    ? AppTheme.primaryBlue
                                                    : Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.color,
                                              ),
                                            ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () => restartNodeService(displayName),
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.errorRed
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: AppTheme.errorRed
                                                      .withOpacity(0.3),
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.restart_alt_rounded,
                                                size: 14,
                                                color: AppTheme.errorRed,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            })
                          else
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                "No hay colas de salida configuradas.",
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                    : const SizedBox.shrink(),
          ),

          const SizedBox(height: 24),

          // 3. CONSOLA DE LOGS (Tap para copiar)
          GestureDetector(
            onTap: copyLogsToClipboard,
            child: Container(
              width: double.infinity,
              height: 280,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF21262D),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Terminal header bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF161B22),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(11),
                        topRight: Radius.circular(11),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF3FB950), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Icon(Icons.terminal_rounded, size: 13, color: Color(0xFF8B949E)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            activeNodeForLogs != null
                                ? 'Logs nodo: $activeNodeForLogs'
                                : 'Logs: ${widget.username}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E), fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (activeNodeForLogs != null) ...[
                          InkWell(
                            onTap: fetchUserLogs,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF21262D),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'volver',
                                style: TextStyle(fontSize: 10, color: Color(0xFF8B949E), fontFamily: 'monospace'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const Icon(Icons.content_copy_rounded, size: 13, color: Color(0xFF484F58)),
                      ],
                    ),
                  ),
                  // Log content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child:
                          loadingLogs
                              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)))
                              : userLogs.isEmpty
                              ? const Center(
                                child: Text(
                                  'No hay logs recientes.',
                                  style: TextStyle(color: Color(0xFF484F58), fontSize: 13),
                                ),
                              )
                              : Scrollbar(
                                thumbVisibility: true,
                                child: ListView.builder(
                                  itemCount: userLogs.length,
                                  itemBuilder: (context, index) {
                                    final line = userLogs[index];
                                    Color lineColor = const Color(0xFFC9D1D9);
                                    FontWeight fontWeight = FontWeight.normal;

                                    if (line.toLowerCase().contains('error')) {
                                      lineColor = const Color(0xFFF85149);
                                    } else if (line.toLowerCase().contains('incoming file')) {
                                      lineColor = const Color(0xFF3FB950);
                                    } else if (line.toLowerCase().contains('warn')) {
                                      lineColor = const Color(0xFFD29922);
                                    } else if (line.toLowerCase().startsWith('---')) {
                                      lineColor = const Color(0xFF58A6FF);
                                      fontWeight = FontWeight.bold;
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 3.0),
                                      child: Text(
                                        line,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: lineColor,
                                          fontWeight: fontWeight,
                                          fontFamily: 'monospace',
                                          height: 1.4,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              "Toca para copiar los logs",
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// PANEL DE GESTIÓN DE SERVICIOS DE UN NODO
// ==========================================

class NodeServicesDialog extends StatefulWidget {
  final String apiUrl;
  final String username;
  final String nodo;

  const NodeServicesDialog({
    super.key,
    required this.apiUrl,
    required this.username,
    required this.nodo,
  });

  @override
  State<NodeServicesDialog> createState() => _NodeServicesDialogState();
}

class _NodeServicesDialogState extends State<NodeServicesDialog> {
  static const List<String> _knownServices = [
    'petroboxguardian',
    'petroboxmonitor',
    'PetroBoxReplicatorNodeSvc',
    'PetroBoxService',
    'PetroBoxService_Port_8091',
    'proxy_bolivia',
  ];

  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _services = [];
  final Set<String> _selectedForRestart = {};
  final Set<String> _busyServices = {};

  @override
  void initState() {
    super.initState();
    _fetchStates();
  }

  Future<void> _fetchStates() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final url = '${widget.apiUrl}/${widget.username}/nodos/${widget.nodo}/servicios/estado';
    debugPrint('[SERVICES-STATE] GET $url');

    try {
      final response = await http.get(Uri.parse(url));
      debugPrint('[SERVICES-STATE] Status: ${response.statusCode}');
      debugPrint('[SERVICES-STATE] Body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['servicios'] as List?) ?? [];
        final mapped = list.map<Map<String, dynamic>>((s) {
          final m = Map<String, dynamic>.from(s as Map);
          return {
            'name': m['Name']?.toString() ?? '',
            'status': m['Status']?.toString() ?? 'Unknown',
            'startType': m['StartType']?.toString() ?? 'Unknown',
          };
        }).toList();

        // Asegurar todos los conocidos aparezcan, aunque el nodo no los tenga
        for (final svc in _knownServices) {
          if (!mapped.any((m) => m['name'] == svc)) {
            mapped.add({'name': svc, 'status': 'NotInstalled', 'startType': '-'});
          }
        }
        mapped.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

        setState(() {
          _services = mapped;
          _loading = false;
        });
      } else {
        String msg = 'Error ${response.statusCode}';
        try {
          final data = json.decode(response.body);
          msg = data['error']?.toString() ?? msg;
        } catch (_) {}
        setState(() {
          _loading = false;
          _loadError = msg;
        });
      }
    } catch (e) {
      debugPrint('[SERVICES-STATE] Exception: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Error de conexión: $e';
        });
      }
    }
  }

  Future<void> _executeAction(String servicio, String accion) async {
    if (_busyServices.contains(servicio)) return;
    setState(() => _busyServices.add(servicio));

    final url = '${widget.apiUrl}/${widget.username}/nodos/${widget.nodo}/servicios/accion';
    debugPrint('[SVC-ACTION] POST $url accion=$accion servicio=$servicio');

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'accion': accion, 'servicio': servicio}),
      );
      debugPrint('[SVC-ACTION] Status: ${response.statusCode} Body: ${response.body}');

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("'$accion' OK en $servicio"),
            backgroundColor: AppTheme.successGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        String msg = 'Error en acción';
        try {
          final data = json.decode(response.body);
          msg = data['mensaje']?.toString() ?? data['error']?.toString() ?? msg;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.errorRed),
        );
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
    } finally {
      if (mounted) {
        setState(() => _busyServices.remove(servicio));
        // Pequeña pausa y refrescar
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _fetchStates();
      }
    }
  }

  Future<void> _restartSelected() async {
    if (_selectedForRestart.isEmpty) return;
    final lista = _selectedForRestart.toList();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reiniciando ${lista.length} servicio(s)...'),
        backgroundColor: AppTheme.primaryBlue,
      ),
    );

    final url = '${widget.apiUrl}/${widget.username}/nodos/${widget.nodo}/reiniciar-servicio';
    debugPrint('[MULTI-RESTART] POST $url servicios=$lista');

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'servicios': lista}),
      );
      debugPrint('[MULTI-RESTART] Status: ${response.statusCode} Body: ${response.body}');

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Servicios reiniciados'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        setState(() => _selectedForRestart.clear());
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _fetchStates();
      } else {
        String msg = 'Error al reiniciar';
        try {
          final data = json.decode(response.body);
          msg = data['mensaje']?.toString() ?? data['error']?.toString() ?? msg;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.errorRed),
        );
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

  Color _statusColor(String status) {
    switch (status) {
      case 'Running':
        return AppTheme.successGreen;
      case 'Stopped':
        return AppTheme.errorRed;
      case 'Paused':
        return AppTheme.warningAmber;
      case 'NotInstalled':
        return Colors.grey;
      default:
        return AppTheme.warningAmber;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).cardColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_rounded, color: AppTheme.primaryBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Servicios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refrescar',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: _loading ? null : _fetchStates,
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                'Nodo: ${widget.nodo}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody()),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final btnRestart = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedForRestart.isEmpty
                          ? Theme.of(context).disabledColor
                          : AppTheme.errorRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: Text(
                      _selectedForRestart.isEmpty
                          ? 'Reiniciar'
                          : 'Reiniciar (${_selectedForRestart.length})',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _selectedForRestart.isEmpty ? null : _restartSelected,
                  );
                  final btnCerrar = TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  );
                  // Si el ancho es muy chico, apilar verticalmente
                  if (constraints.maxWidth < 360) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        btnRestart,
                        const SizedBox(height: 6),
                        btnCerrar,
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [btnCerrar, const SizedBox(width: 8), btnRestart],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue));
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 36, color: AppTheme.errorRed),
            const SizedBox(height: 8),
            Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _services.length,
      separatorBuilder: (_, __) => Divider(
        height: 12,
        color: Theme.of(context).dividerColor.withOpacity(0.3),
      ),
      itemBuilder: (context, index) => _buildServiceRow(_services[index]),
    );
  }

  Widget _buildServiceRow(Map<String, dynamic> svc) {
    final name = svc['name'] as String;
    final status = svc['status'] as String;
    final startType = svc['startType'] as String;
    final bool installed = status != 'NotInstalled';
    final bool running = status == 'Running';
    final bool stopped = status == 'Stopped';
    final bool disabled = startType == 'Disabled';
    final bool busy = _busyServices.contains(name);
    final bool selected = _selectedForRestart.contains(name);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkWell(
          onTap: !installed
              ? null
              : () {
                  setState(() {
                    if (selected) {
                      _selectedForRestart.remove(name);
                    } else {
                      _selectedForRestart.add(name);
                    }
                  });
                },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 18,
              color: !installed
                  ? Colors.grey.withOpacity(0.4)
                  : (selected ? AppTheme.errorRed : Theme.of(context).textTheme.bodyMedium?.color),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    installed ? '$status · $startType' : 'No instalado',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (installed) ...[
          if (stopped)
            _actionBtn(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Iniciar',
              color: AppTheme.successGreen,
              onTap: () => _executeAction(name, 'start'),
            ),
          if (running)
            _actionBtn(
              icon: Icons.stop_rounded,
              tooltip: 'Detener',
              color: AppTheme.warningAmber,
              onTap: () => _executeAction(name, 'stop'),
            ),
          if (running || stopped)
            _actionBtn(
              icon: Icons.restart_alt_rounded,
              tooltip: 'Reiniciar',
              color: AppTheme.primaryBlue,
              onTap: () => _executeAction(name, 'restart'),
            ),
          if (disabled)
            _actionBtn(
              icon: Icons.power_settings_new_rounded,
              tooltip: 'Habilitar (Automatic)',
              color: AppTheme.warningAmber,
              onTap: () => _executeAction(name, 'enable_automatic'),
            ),
        ],
      ],
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}
