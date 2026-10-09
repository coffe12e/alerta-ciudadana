import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/incidente.dart';
import '../services/alerta_api.dart';

class AdministracionPage extends StatefulWidget {
  const AdministracionPage({required this.api, super.key});

  final AlertaApi api;

  @override
  State<AdministracionPage> createState() => _AdministracionPageState();
}

class _AdministracionPageState extends State<AdministracionPage> {
  final TextEditingController _tokenController = TextEditingController();
  String? _token;
  String _filtro = 'TODOS';
  List<Incidente> _incidentes = [];
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _conectar() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Pega el token que muestra la API.');
      return;
    }
    await _cargar(tokenTemporal: token);
  }

  Future<void> _cargar({String? tokenTemporal}) async {
    final token = tokenTemporal ?? _token;
    if (token == null) return;

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final incidentes = await widget.api.obtenerIncidentesAdmin(
        token: token,
        estado: _filtro,
      );
      if (!mounted) return;
      setState(() {
        _token = token;
        _incidentes = incidentes;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _cambiarEstado(Incidente incidente, String estado) async {
    var radio = incidente.radioMetros >= 1000 ? incidente.radioMetros : 3000;
    final nota = TextEditingController();
    final decision = await showDialog<(int, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_nombreEstado(estado)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (estado == 'VERIFICADA') ...[
                const Text('Radio en el que se distribuirá esta alerta'),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: radio,
                  items: const [
                    DropdownMenuItem(value: 1000, child: Text('1 km')),
                    DropdownMenuItem(value: 3000, child: Text('3 km')),
                    DropdownMenuItem(value: 5000, child: Text('5 km')),
                    DropdownMenuItem(value: 10000, child: Text('10 km')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => radio = value);
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: nota,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota de revisión (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                (radio, nota.text.trim()),
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    nota.dispose();
    if (decision == null || _token == null) return;

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await widget.api.actualizarIncidente(
        id: incidente.id,
        estado: estado,
        token: _token!,
        radioMetros: decision.$1,
        notaRevision: decision.$2,
      );
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Incidente actualizado: ${_nombreEstado(estado)}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración de incidentes'),
        actions: [
          if (_token != null)
            IconButton(
              tooltip: 'Actualizar incidentes',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _token == null ? _formularioAcceso() : _listaIncidentes(),
    );
  }

  Widget _formularioAcceso() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(
          Icons.admin_panel_settings_outlined,
          size: 54,
          color: Color(0xFF145C52),
        ),
        const SizedBox(height: 12),
        const Text(
          'Acceso de moderación',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Copia el token temporal que aparece en la consola de la API. '
          'Solo las personas autorizadas deben revisar evidencia y cambiar estados.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.45, color: Color(0xFF61716B)),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _tokenController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Token de administración',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.key_outlined),
          ),
          onSubmitted: (_) => _conectar(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _cargando ? null : _conectar,
          icon: _cargando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.lock_open_rounded),
          label: Text(_cargando ? 'Conectando…' : 'Entrar'),
        ),
      ],
    );
  }

  Widget _listaIncidentes() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DropdownButtonFormField<String>(
            value: _filtro,
            decoration: const InputDecoration(
              labelText: 'Filtrar por estado',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
              DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendientes')),
              DropdownMenuItem(value: 'EN_REVISION', child: Text('En revisión')),
              DropdownMenuItem(value: 'VERIFICADA', child: Text('Verificados')),
              DropdownMenuItem(value: 'RESUELTA', child: Text('Resueltos')),
              DropdownMenuItem(value: 'RECHAZADA', child: Text('Rechazados')),
            ],
            onChanged: _cargando
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _filtro = value);
                    _cargar();
                  },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB3261E)),
            ),
          ),
        if (_cargando) const LinearProgressIndicator(),
        Expanded(
          child: _incidentes.isEmpty && !_cargando
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'No hay incidentes para este filtro.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  itemCount: _incidentes.length,
                  itemBuilder: (context, index) => _IncidenteCard(
                    incidente: _incidentes[index],
                    token: _token!,
                    api: widget.api,
                    onCambiarEstado: _cambiarEstado,
                  ),
                ),
        ),
      ],
    );
  }
}

class _IncidenteCard extends StatelessWidget {
  const _IncidenteCard({
    required this.incidente,
    required this.token,
    required this.api,
    required this.onCambiarEstado,
  });

  final Incidente incidente;
  final String token;
  final AlertaApi api;
  final Future<void> Function(Incidente, String) onCambiarEstado;

  @override
  Widget build(BuildContext context) {
    final fecha = incidente.creadaUtc.toLocal();
    final fechaTexto =
        '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _colorEstado(incidente.estado).withOpacity(0.12),
          child: Icon(
            _iconoEstado(incidente.estado),
            color: _colorEstado(incidente.estado),
          ),
        ),
        title: Text(
          incidente.titulo,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${incidente.categoria} · ${_nombreEstado(incidente.estado)} · $fechaTexto',
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(incidente.descripcion),
          const SizedBox(height: 8),
          Text(
            'Coordenadas del reporte: '
            '${incidente.latitud.toStringAsFixed(5)}, '
            '${incidente.longitud.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF61716B)),
          ),
          if (incidente.radioMetros > 0)
            Text(
              'Radio de distribución: ${incidente.radioMetros} m',
              style: const TextStyle(fontSize: 12, color: Color(0xFF61716B)),
            ),
          if (incidente.notaRevision?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text('Nota: ${incidente.notaRevision}'),
          ],
          if (incidente.evidencias.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Evidencia y ubicación al adjuntar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final evidencia in incidente.evidencias)
              _EvidenciaAdmin(
                incidenteId: incidente.id,
                evidencia: evidencia,
                api: api,
                token: token,
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _acciones().map((accion) {
              return OutlinedButton(
                onPressed: () => onCambiarEstado(incidente, accion.$2),
                child: Text(accion.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _acciones() {
    switch (incidente.estado.toUpperCase()) {
      case 'PENDIENTE':
        return [
          ('Tomar revisión', 'EN_REVISION'),
          ('Verificar y publicar', 'VERIFICADA'),
          ('Rechazar', 'RECHAZADA'),
        ];
      case 'EN_REVISION':
        return [
          ('Verificar y publicar', 'VERIFICADA'),
          ('Rechazar', 'RECHAZADA'),
        ];
      case 'VERIFICADA':
        return [('Cerrar como resuelta', 'RESUELTA')];
      default:
        return [];
    }
  }
}

class _EvidenciaAdmin extends StatefulWidget {
  const _EvidenciaAdmin({
    required this.incidenteId,
    required this.evidencia,
    required this.api,
    required this.token,
  });

  final int incidenteId;
  final EvidenciaRemota evidencia;
  final AlertaApi api;
  final String token;

  @override
  State<_EvidenciaAdmin> createState() => _EvidenciaAdminState();
}

class _EvidenciaAdminState extends State<_EvidenciaAdmin> {
  late final Future<Uint8List> _imagen;

  @override
  void initState() {
    super.initState();
    _imagen = widget.api.obtenerEvidenciaAdmin(
      incidenteId: widget.incidenteId,
      evidenciaId: widget.evidencia.id,
      token: widget.token,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fecha = widget.evidencia.capturadaUtc.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          FutureBuilder<Uint8List>(
            future: _imagen,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _miniatura(
                  const Icon(Icons.broken_image_outlined),
                );
              }
              if (!snapshot.hasData) {
                return _miniatura(
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    child: InteractiveViewer(
                      child: Image.memory(snapshot.data!),
                    ),
                  ),
                ),
                child: _miniatura(
                  Image.memory(snapshot.data!, fit: BoxFit.cover),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${fecha.day.toString().padLeft(2, '0')}/'
              '${fecha.month.toString().padLeft(2, '0')}/'
              '${fecha.year} · '
              '${fecha.hour.toString().padLeft(2, '0')}:'
              '${fecha.minute.toString().padLeft(2, '0')}\n'
              '${widget.evidencia.latitud.toStringAsFixed(5)}, '
              '${widget.evidencia.longitud.toStringAsFixed(5)} '
              '(±${widget.evidencia.precisionMetros.round()} m)',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniatura(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 76,
          height: 76,
          color: const Color(0xFFE9EFEC),
          alignment: Alignment.center,
          child: child,
        ),
      );
}

String _nombreEstado(String estado) {
  switch (estado.toUpperCase()) {
    case 'PENDIENTE':
      return 'Pendiente';
    case 'EN_REVISION':
      return 'En revisión';
    case 'VERIFICADA':
      return 'Verificada';
    case 'RESUELTA':
      return 'Resuelta';
    case 'RECHAZADA':
      return 'Rechazada';
    default:
      return estado;
  }
}

Color _colorEstado(String estado) {
  switch (estado.toUpperCase()) {
    case 'VERIFICADA':
      return const Color(0xFF21836F);
    case 'RESUELTA':
      return const Color(0xFF52645E);
    case 'RECHAZADA':
      return const Color(0xFFB3261E);
    case 'EN_REVISION':
      return const Color(0xFFB27A17);
    default:
      return const Color(0xFF397D70);
  }
}

IconData _iconoEstado(String estado) {
  switch (estado.toUpperCase()) {
    case 'VERIFICADA':
      return Icons.verified_outlined;
    case 'RESUELTA':
      return Icons.check_circle_outline;
    case 'RECHAZADA':
      return Icons.cancel_outlined;
    case 'EN_REVISION':
      return Icons.rate_review_outlined;
    default:
      return Icons.pending_actions_outlined;
  }
}
