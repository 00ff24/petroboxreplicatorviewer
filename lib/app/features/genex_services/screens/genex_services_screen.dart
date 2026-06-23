import 'dart:async';
import 'package:flutter/material.dart';

import 'package:replicatorviewer/app/config/theme.dart';
import 'package:replicatorviewer/app/features/genex_services/services/genex_api.dart';
import 'package:replicatorviewer/app/features/genex_services/screens/genex_service_detail_screen.dart';

/// Dashboard de servicios de los 18 genex.
/// Muestra una tarjeta por servicio con "activos / total" y, al tocar,
/// abre el detalle por host con acciones.
class GenexServicesScreen extends StatefulWidget {
  const GenexServicesScreen({super.key});

  @override
  State<GenexServicesScreen> createState() => _GenexServicesScreenState();
}

class _GenexServicesScreenState extends State<GenexServicesScreen> {
  GenexResumen? _resumen;
  bool _loading = true;
  bool _refrescando = false;
  String? _error;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Refresco suave cada 30s leyendo la caché del backend.
    _autoRefresh = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _loading = true);
    try {
      final r = await GenexApi.fetchResumen();
      if (!mounted) return;
      setState(() {
        _resumen = r;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Fuerza un sondeo nuevo de los 18 (puede tardar).
  Future<void> _forzarRefresco() async {
    setState(() => _refrescando = true);
    try {
      final r = await GenexApi.refrescar();
      if (!mounted) return;
      setState(() {
        _resumen = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al refrescar: $e'),
              backgroundColor: AppTheme.errorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _refrescando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.dns_rounded, color: AppTheme.primaryBlue),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Servicios Genex',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                ),
                Text(
                  _subtitulo(),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.darkTextMuted),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_refrescando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Sondear ahora los 18 genex',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _forzarRefresco,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildGrid(),
    );
  }

  String _subtitulo() {
    final r = _resumen;
    if (r == null) return '18 estaciones';
    final edad = r.edadSegundos;
    if (edad == null) return '${r.totalGenex} estaciones';
    return '${r.totalGenex} estaciones · actualizado hace ${edad.round()}s';
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
            const Text('No se pudo cargar el panel de servicios',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.darkTextMuted)),
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

  Widget _buildGrid() {
    final servicios = _resumen?.servicios ?? [];
    return RefreshIndicator(
      onRefresh: () => _cargar(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tarjetas de ~300px de ancho, responsive.
          const cardWidth = 300.0;
          final cols = (constraints.maxWidth / cardWidth).floor().clamp(1, 4);
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              mainAxisExtent: 170,
            ),
            itemCount: servicios.length,
            itemBuilder: (context, i) => _ServiceCard(
              resumen: servicios[i],
              onTap: () => _abrirDetalle(servicios[i].servicio),
            ),
          );
        },
      ),
    );
  }

  Future<void> _abrirDetalle(String servicio) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GenexServiceDetailScreen(servicio: servicio),
      ),
    );
    // Al volver, refrescamos por si hubo cambios.
    _cargar(silencioso: true);
  }
}

class _ServiceCard extends StatelessWidget {
  final GenexServicioResumen resumen;
  final VoidCallback onTap;

  const _ServiceCard({required this.resumen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final base = resumen.instalados > 0 ? resumen.instalados : resumen.total;
    final ratio = base > 0 ? resumen.activos / base : 0.0;
    final color = _colorEstado(resumen, ratio);

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: Theme.of(context).dividerColor, width: 1),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      GenexServiceMeta.label(resumen.servicio),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.darkTextMuted),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${resumen.activos}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    ' / ${resumen.total} activos',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor:
                      Theme.of(context).dividerColor.withOpacity(0.5),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (resumen.detenidos > 0)
                    _chip('${resumen.detenidos} detenido', AppTheme.errorRed),
                  if (resumen.deshabilitados > 0)
                    _chip('${resumen.deshabilitados} deshab.',
                        AppTheme.warningAmber),
                  if (resumen.noInstalado > 0)
                    _chip('${resumen.noInstalado} no inst.',
                        AppTheme.darkTextMuted),
                  if (resumen.sinRespuesta > 0)
                    _chip('${resumen.sinRespuesta} sin resp.',
                        AppTheme.darkTextMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _colorEstado(GenexServicioResumen r, double ratio) {
    if (r.instalados == 0) return AppTheme.darkTextMuted;
    if (r.activos == r.instalados) return AppTheme.successGreen;
    if (r.activos == 0) return AppTheme.errorRed;
    return AppTheme.warningAmber;
  }
}
