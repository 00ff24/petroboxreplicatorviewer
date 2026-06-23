import 'package:flutter/material.dart';

import 'package:replicatorviewer/app/config/theme.dart';
import 'package:replicatorviewer/app/features/genex_services/services/genex_api.dart';

/// Detalle de un servicio sobre los 18 genex: estado por host + acciones
/// individuales y acción masiva.
class GenexServiceDetailScreen extends StatefulWidget {
  final String servicio;

  const GenexServiceDetailScreen({super.key, required this.servicio});

  @override
  State<GenexServiceDetailScreen> createState() =>
      _GenexServiceDetailScreenState();
}

class _GenexServiceDetailScreenState extends State<GenexServiceDetailScreen> {
  List<GenexHostEstado> _hosts = [];
  bool _loading = true;
  String? _error;
  final Set<String> _trabajando = {}; // hosts con acción en curso

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hosts = await GenexApi.fetchDetalle(widget.servicio);
      if (!mounted) return;
      setState(() {
        _hosts = hosts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _ejecutarAccion(GenexHostEstado host, GenexAccion accion) async {
    setState(() => _trabajando.add(host.host));
    try {
      final res = await GenexApi.accion(
        host: host.host,
        servicio: widget.servicio,
        accion: accion.id,
      );
      if (!mounted) return;
      _snack(
        '${res.nombre}: ${res.ok ? accion.label + ' ✓' : res.mensaje}',
        res.ok ? AppTheme.successGreen : AppTheme.errorRed,
      );
    } catch (e) {
      if (mounted) _snack('Error: $e', AppTheme.errorRed);
    } finally {
      if (mounted) setState(() => _trabajando.remove(host.host));
      await _cargar();
    }
  }

  Future<void> _accionMasiva(GenexAccion accion) async {
    final confirmar = await _confirmarMasiva(accion);
    if (confirmar != true) return;

    setState(() => _loading = true);
    try {
      final res = await GenexApi.accionMasiva(
        servicio: widget.servicio,
        accion: accion.id,
      );
      if (!mounted) return;
      _snack(
        'Acción masiva "${accion.label}": ${res.exitosos} OK, ${res.fallidos} con error',
        res.fallidos == 0 ? AppTheme.successGreen : AppTheme.warningAmber,
      );
    } catch (e) {
      if (mounted) _snack('Error: $e', AppTheme.errorRed);
    } finally {
      await _cargar();
    }
  }

  Future<bool?> _confirmarMasiva(GenexAccion accion) {
    final esDestructiva =
        accion.id == 'stop' || accion.id == 'disable' || accion.id == 'restart';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Row(
          children: [
            Icon(
              esDestructiva
                  ? Icons.warning_amber_rounded
                  : Icons.dns_rounded,
              color: esDestructiva ? AppTheme.errorRed : AppTheme.primaryBlue,
              size: 26,
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Acción masiva')),
          ],
        ),
        content: Text(
          '¿Aplicar "${accion.label}" al servicio '
          '${GenexServiceMeta.label(widget.servicio)} en los ${_hosts.length} genex?',
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  esDestructiva ? AppTheme.errorRed : AppTheme.primaryBlue,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(accion.label,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activos = _hosts.where((h) => h.running).length;
    final instalados = _hosts.where((h) => h.instalado).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              GenexServiceMeta.label(widget.servicio),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
            ),
            Text(
              widget.servicio,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.darkTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _cargar,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildResumenBar(activos, instalados),
                    _buildMassActionBar(),
                    const Divider(height: 1),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _hosts.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) => _buildHostRow(_hosts[i]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppTheme.errorRed, size: 48),
            const SizedBox(height: 16),
            Text(_error ?? 'Error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenBar(int activos, int instalados) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Text(
            '$activos',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.successGreen,
            ),
          ),
          Text(
            ' / ${_hosts.length} activos',
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const Spacer(),
          if (instalados < _hosts.length)
            Text(
              '${_hosts.length - instalados} no instalado',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.darkTextMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildMassActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.layers_rounded,
              size: 18, color: AppTheme.darkTextMuted),
          const SizedBox(width: 8),
          Text(
            'Acción masiva:',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: GenexServiceMeta.acciones
                  .map((a) => OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                          minimumSize: const Size(0, 36),
                        ),
                        onPressed: () => _accionMasiva(a),
                        child: Text(a.label),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostRow(GenexHostEstado host) {
    final ocupado = _trabajando.contains(host.host);
    return ListTile(
      dense: false,
      leading: _statusDot(host),
      title: Text(
        host.nombre,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _subtituloHost(host),
        style: const TextStyle(
            fontSize: 12, color: AppTheme.darkTextMuted),
      ),
      trailing: ocupado
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<GenexAccion>(
              enabled: host.ok,
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Acciones',
              onSelected: (a) => _ejecutarAccion(host, a),
              itemBuilder: (context) => GenexServiceMeta.acciones
                  .map((a) => PopupMenuItem<GenexAccion>(
                        value: a,
                        child: Row(
                          children: [
                            Icon(_accionIcon(a.id),
                                size: 18, color: _accionColor(a.id)),
                            const SizedBox(width: 10),
                            Text(a.label),
                          ],
                        ),
                      ))
                  .toList(),
            ),
    );
  }

  String _subtituloHost(GenexHostEstado host) {
    if (!host.ok) return 'Sin respuesta${host.error != null ? ' · ${host.error}' : ''}';
    if (!host.instalado) return 'No instalado';
    return '${host.status} · ${host.startType}';
  }

  Widget _statusDot(GenexHostEstado host) {
    Color c;
    IconData icon;
    if (!host.ok) {
      c = AppTheme.darkTextMuted;
      icon = Icons.help_outline_rounded;
    } else if (!host.instalado) {
      c = AppTheme.darkTextMuted;
      icon = Icons.remove_circle_outline_rounded;
    } else if (host.running) {
      c = AppTheme.successGreen;
      icon = Icons.check_circle_rounded;
    } else if (host.startType == 'Disabled') {
      c = AppTheme.warningAmber;
      icon = Icons.block_rounded;
    } else {
      c = AppTheme.errorRed;
      icon = Icons.stop_circle_rounded;
    }
    return Icon(icon, color: c, size: 26);
  }

  IconData _accionIcon(String id) {
    switch (id) {
      case 'start':
        return Icons.play_arrow_rounded;
      case 'stop':
        return Icons.stop_rounded;
      case 'restart':
        return Icons.restart_alt_rounded;
      case 'disable':
        return Icons.block_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  Color _accionColor(String id) {
    switch (id) {
      case 'start':
        return AppTheme.successGreen;
      case 'stop':
      case 'disable':
        return AppTheme.errorRed;
      case 'restart':
        return AppTheme.warningAmber;
      default:
        return AppTheme.primaryBlue;
    }
  }
}
