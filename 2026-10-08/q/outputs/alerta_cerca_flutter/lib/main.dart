import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'models/alerta.dart';
import 'models/evidencia.dart';
import 'screens/administracion_page.dart';
import 'services/alerta_api.dart';
import 'services/ubicacion_service.dart';

void main() {
  runApp(const AlertaCercaApp());
}

class AlertaCercaApp extends StatelessWidget {
  const AlertaCercaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const verde = Color(0xFF145C52);

    return MaterialApp(
      title: 'ALERTA CERCA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: verde,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7F5),
          foregroundColor: Color(0xFF17322D),
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE3EAE6)),
          ),
        ),
      ),
      home: const InicioPage(),
    );
  }
}

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> with WidgetsBindingObserver {
  final AlertaApi _api = AlertaApi();

  Position? _posicion;
  List<Alerta> _alertas = [];
  int _radioMetros = 3000;
  bool _cargando = false;
  bool _monitoreoProximidad = false;
  bool _consultaAutomatica = false;
  Timer? _temporizadorProximidad;
  final Set<int> _alertasConocidas = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _monitoreoProximidad) {
      unawaited(_revisarProximidad(avisar: true));
      _programarMonitoreo();
    } else {
      _temporizadorProximidad?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _temporizadorProximidad?.cancel();
    _api.dispose();
    super.dispose();
  }

  void _programarMonitoreo() {
    _temporizadorProximidad?.cancel();
    if (!_monitoreoProximidad ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _temporizadorProximidad = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_revisarProximidad(avisar: true)),
    );
  }

  Future<void> _alternarMonitoreo(bool activar) async {
    if (!activar) {
      _temporizadorProximidad?.cancel();
      setState(() => _monitoreoProximidad = false);
      return;
    }

    setState(() {
      _monitoreoProximidad = true;
      _error = null;
    });
    final pudoConsultar = await _revisarProximidad(avisar: false);
    if (!mounted) return;
    if (!pudoConsultar) {
      setState(() => _monitoreoProximidad = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo activar el aviso de proximidad. Revisa GPS y conexión.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _programarMonitoreo();
  }

  Future<bool> _revisarProximidad({required bool avisar}) async {
    if (!_monitoreoProximidad ||
        _consultaAutomatica ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return true;
    }
    _consultaAutomatica = true;
    try {
      final posicion = await UbicacionService.obtenerActual();
      final alertas = await _api.obtenerCercanas(
        latitud: posicion.latitude,
        longitud: posicion.longitude,
        radioMetros: _radioMetros,
      );
      final nuevas = alertas.where((alerta) {
        return _alertasConocidas.add(alerta.id);
      }).toList();

      if (mounted) {
        setState(() {
          _posicion = posicion;
          _alertas = alertas;
        });
        if (avisar && nuevas.isNotEmpty) {
          final texto = nuevas.length == 1
              ? 'Nueva alerta verificada cerca: ${nuevas.first.titulo}'
              : 'Hay ${nuevas.length} nuevas alertas verificadas cerca.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(texto),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _consultaAutomatica = false;
    }
  }

  Future<void> _actualizarUbicacionYAlertas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final posicion = await UbicacionService.obtenerActual();
      await _actualizarConPosicion(posicion);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _actualizarConPosicion(Position posicion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final alertas = await _api.obtenerCercanas(
        latitud: posicion.latitude,
        longitud: posicion.longitude,
        radioMetros: _radioMetros,
      );
      if (!mounted) return;
      _alertasConocidas.addAll(alertas.map((alerta) => alerta.id));
      setState(() {
        _posicion = posicion;
        _alertas = alertas;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _posicion = posicion;
        _error = error.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _abrirFormulario() async {
    final enviado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReporteSheet(
        api: _api,
        posicionInicial: _posicion,
      ),
    );

    if (!mounted || enviado != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte enviado para revisión.'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    await _actualizarUbicacionYAlertas();
  }

  void _abrirAdministracion() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdministracionPage(api: _api),
      ),
    );
  }

  String get _radioLabel =>
      _radioMetros < 1000 ? '$_radioMetros m' : '${_radioMetros ~/ 1000} km';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ALERTA CERCA',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
            ),
            Text(
              'Información útil en tu zona',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (opcion) {
              if (opcion == 'administracion') _abrirAdministracion();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'administracion',
                child: Text('Administración de incidentes'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Actualizar alertas',
            onPressed: _cargando ? null : _actualizarUbicacionYAlertas,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _actualizarUbicacionYAlertas,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
          children: [
            _UbicacionCard(
              cargando: _cargando,
              tieneUbicacion: _posicion != null,
              radioLabel: _radioLabel,
              onTap: _actualizarUbicacionYAlertas,
            ),
            Card(
              child: SwitchListTile(
                value: _monitoreoProximidad,
                onChanged: _cargando ? null : _alternarMonitoreo,
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text(
                  'Avisarme de alertas cercanas',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Revisa la zona cada minuto mientras ALERTA CERCA está abierta.',
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Alertas cercanas',
                    style: TextStyle(
                      color: Color(0xFF17322D),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DropdownButton<int>(
                  value: _radioMetros,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(14),
                  items: const [
                    DropdownMenuItem(value: 1000, child: Text('1 km')),
                    DropdownMenuItem(value: 3000, child: Text('3 km')),
                    DropdownMenuItem(value: 5000, child: Text('5 km')),
                    DropdownMenuItem(value: 10000, child: Text('10 km')),
                  ],
                  onChanged: _cargando
                      ? null
                      : (radio) async {
                          if (radio == null) return;
                          setState(() => _radioMetros = radio);
                          if (_posicion != null) {
                            await _actualizarConPosicion(_posicion!);
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 38),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _EstadoVacio(
                icono: Icons.cloud_off_outlined,
                titulo: 'No se pudieron cargar las alertas',
                detalle: _error!,
                accion: 'Intentar de nuevo',
                onTap: _actualizarUbicacionYAlertas,
              )
            else if (_posicion == null)
              _EstadoVacio(
                icono: Icons.near_me_outlined,
                titulo: 'Consulta lo que ocurre cerca',
                detalle:
                    'La app usa tu ubicación cuando pides actualizar las alertas.',
                accion: 'Usar mi ubicación',
                onTap: _actualizarUbicacionYAlertas,
              )
            else if (_alertas.isEmpty)
              _EstadoVacio(
                icono: Icons.check_circle_outline_rounded,
                titulo: 'No hay alertas verificadas',
                detalle:
                    'No encontramos alertas activas en un radio de $_radioLabel.',
                accion: 'Actualizar',
                onTap: _actualizarUbicacionYAlertas,
              )
            else
              ..._alertas.map(
                (alerta) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AlertaCard(alerta: alerta),
                ),
              ),
            const SizedBox(height: 12),
            const _NotaSeguridad(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Reportar situación'),
      ),
    );
  }
}

class _UbicacionCard extends StatelessWidget {
  const _UbicacionCard({
    required this.cargando,
    required this.tieneUbicacion,
    required this.radioLabel,
    required this.onTap,
  });

  final bool cargando;
  final bool tieneUbicacion;
  final String radioLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF145C52), Color(0xFF267969)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 25,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(Icons.shield_outlined, color: Colors.white, size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tieneUbicacion ? 'Zona actualizada' : 'Mantente informado',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tieneUbicacion
                      ? 'Radio seleccionado: $radioLabel'
                      : 'Consulta alertas verificadas cerca de ti.',
                  style: const TextStyle(color: Color(0xFFE0F0EC), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Actualizar ubicación',
            onPressed: cargando ? null : onTap,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF145C52),
            ),
            icon: cargando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.accion,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final String accion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3EAE6)),
      ),
      child: Column(
        children: [
          Icon(icono, size: 38, color: const Color(0xFF397D70)),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF17322D),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF61716B), height: 1.4),
          ),
          const SizedBox(height: 17),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(accion),
          ),
        ],
      ),
    );
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({required this.alerta});

  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    final color = _colorCategoria(alerta.categoria);
    final distancia = alerta.distanciaMetros < 1000
        ? '${alerta.distanciaMetros.round()} m'
        : '${(alerta.distanciaMetros / 1000).toStringAsFixed(1)} km';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _mostrarDetalle(context, alerta),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_iconoCategoria(alerta.categoria), color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alerta.titulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF17322D),
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: Color(0xFF21836F),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_nombreCategoria(alerta.categoria)} · $distancia',
                      style: const TextStyle(
                        color: Color(0xFF60716B),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      alerta.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF344A43),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Ver detalles',
                      style: TextStyle(
                        color: Color(0xFF145C52),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _colorCategoria(String categoria) {
    switch (categoria.toUpperCase()) {
      case 'INUNDACION':
      case 'INUNDACIÓN':
        return const Color(0xFF2475A8);
      case 'INCENDIO':
        return const Color(0xFFCF562F);
      case 'PERSONA_DESAPARECIDA':
        return const Color(0xFF8C4C98);
      case 'ROBO_VEHICULO':
      case 'ROBO_VEHÍCULO':
        return const Color(0xFFB27A17);
      default:
        return const Color(0xFF397D70);
    }
  }

  static IconData _iconoCategoria(String categoria) {
    switch (categoria.toUpperCase()) {
      case 'INUNDACION':
      case 'INUNDACIÓN':
        return Icons.water_damage_outlined;
      case 'INCENDIO':
        return Icons.local_fire_department_outlined;
      case 'PERSONA_DESAPARECIDA':
        return Icons.person_search_outlined;
      case 'ROBO_VEHICULO':
      case 'ROBO_VEHÍCULO':
        return Icons.directions_car_outlined;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  static String _nombreCategoria(String categoria) {
    switch (categoria.toUpperCase()) {
      case 'PERSONA_DESAPARECIDA':
        return 'Persona desaparecida';
      case 'ROBO_VEHICULO':
      case 'ROBO_VEHÍCULO':
        return 'Robo de vehículo';
      case 'INUNDACION':
      case 'INUNDACIÓN':
        return 'Inundación';
      case 'INCENDIO':
        return 'Incendio';
      default:
        return categoria;
    }
  }
}

Future<void> _mostrarDetalle(BuildContext context, Alerta alerta) async {
  final fecha = alerta.creadaUtc.toLocal();
  final fechaTexto =
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/'
      '${fecha.year} · '
      '${fecha.hour.toString().padLeft(2, '0')}:'
      '${fecha.minute.toString().padLeft(2, '0')}';

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_rounded, color: Color(0xFF21836F)),
              SizedBox(width: 8),
              Text(
                'Alerta verificada',
                style: TextStyle(
                  color: Color(0xFF21836F),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            alerta.titulo,
            style: const TextStyle(
              color: Color(0xFF17322D),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            alerta.descripcion,
            style: const TextStyle(color: Color(0xFF344A43), height: 1.45),
          ),
          const SizedBox(height: 16),
          Text(
            'Publicada: $fechaTexto',
            style: const TextStyle(color: Color(0xFF61716B), fontSize: 13),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sigue las indicaciones oficiales y evita acercarte a una zona peligrosa.',
            style: TextStyle(
              color: Color(0xFF8D4A23),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    ),
  );
}

class _NotaSeguridad extends StatelessWidget {
  const _NotaSeguridad();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: Color(0xFF75847E)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ALERTA CERCA complementa los canales oficiales. No sustituye los servicios de emergencia.',
              style: TextStyle(
                color: Color(0xFF75847E),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReporteSheet extends StatefulWidget {
  const ReporteSheet({
    required this.api,
    required this.posicionInicial,
    super.key,
  });

  final AlertaApi api;
  final Position? posicionInicial;

  @override
  State<ReporteSheet> createState() => _ReporteSheetState();
}

class _ReporteSheetState extends State<ReporteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _descripcion = TextEditingController();
  final ImagePicker _selectorImagenes = ImagePicker();
  final List<EvidenciaAdjunta> _evidencias = [];

  String _categoria = 'INUNDACION';
  Position? _posicion;
  bool _enviando = false;
  bool _obteniendoUbicacion = false;
  bool _adjuntandoEvidencia = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _posicion = widget.posicionInicial;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _tomarUbicacion() async {
    setState(() {
      _obteniendoUbicacion = true;
      _error = null;
    });

    try {
      final posicion = await UbicacionService.obtenerActual();
      if (!mounted) return;
      setState(() {
        _posicion = posicion;
        _obteniendoUbicacion = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _obteniendoUbicacion = false;
      });
    }
  }

  Future<void> _adjuntarEvidencia(ImageSource origen) async {
    if (_evidencias.length >= 4) {
      setState(() => _error = 'Puedes adjuntar hasta 4 fotografías por reporte.');
      return;
    }

    setState(() {
      _adjuntandoEvidencia = true;
      _error = null;
    });
    try {
      final imagen = await _selectorImagenes.pickImage(
        source: origen,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 82,
      );
      if (imagen == null || !mounted) return;
      if (await imagen.length() > 5 * 1024 * 1024) {
        setState(() => _error = 'La foto pesa más de 5 MB. Elige una imagen más pequeña.');
        return;
      }

      final posicion = await UbicacionService.obtenerActual();
      if (!mounted) return;
      setState(() {
        _evidencias.add(
          EvidenciaAdjunta(
            archivo: imagen,
            latitud: posicion.latitude,
            longitud: posicion.longitude,
            precisionMetros: posicion.accuracy,
            capturadaUtc: posicion.timestamp.toUtc(),
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo completar el adjunto. Revisa los permisos de la foto y la ubicación GPS. '
            '${error.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _adjuntandoEvidencia = false);
    }
  }

  Future<void> _enviar() async {
    if (_enviando || _adjuntandoEvidencia) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enviando = true;
      _error = null;
    });

    late final Position posicion;
    try {
      posicion = await UbicacionService.obtenerActual();
      if (!mounted) return;
      setState(() => _posicion = posicion);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _enviando = false;
      });
      return;
    }

    try {
      await widget.api.crearReporte(
        NuevoReporte(
          categoria: _categoria,
          titulo: _titulo.text.trim(),
          descripcion: _descripcion.text.trim(),
          latitud: posicion.latitude,
          longitud: posicion.longitude,
          evidencias: List.unmodifiable(_evidencias),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAF8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reportar situación',
                  style: TextStyle(
                    color: Color(0xFF17322D),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'El reporte quedará pendiente de revisión antes de difundirse.',
                  style: TextStyle(color: Color(0xFF61716B), height: 1.35),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: _categoria,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'INUNDACION',
                      child: Text('Inundación'),
                    ),
                    DropdownMenuItem(
                      value: 'INCENDIO',
                      child: Text('Incendio'),
                    ),
                    DropdownMenuItem(
                      value: 'PERSONA_DESAPARECIDA',
                      child: Text('Persona desaparecida'),
                    ),
                    DropdownMenuItem(
                      value: 'ROBO_VEHICULO',
                      child: Text('Robo de vehículo'),
                    ),
                    DropdownMenuItem(value: 'OTRA', child: Text('Otra')),
                  ],
                  onChanged: _enviando
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _categoria = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titulo,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Título breve',
                    hintText: 'Ej. Calle inundada',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                          ? 'Escribe un título.'
                          : null,
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _descripcion,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    hintText: 'Describe lo que observaste.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                          ? 'Escribe una descripción.'
                          : null,
                ),
                const SizedBox(height: 14),
                Text(
                  'Fotografías con ubicación GPS (${_evidencias.length}/4)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _enviando || _adjuntandoEvidencia
                          ? null
                          : () => _adjuntarEvidencia(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Tomar foto'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _enviando || _adjuntandoEvidencia
                          ? null
                          : () => _adjuntarEvidencia(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Elegir foto'),
                    ),
                    if (_adjuntandoEvidencia)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
                if (_evidencias.isNotEmpty)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _evidencias.map((evidencia) {
                      final fecha = evidencia.capturadaUtc.toLocal();
                      return SizedBox(
                        width: 145,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Image.file(
                                File(evidencia.archivo.path),
                                width: 145,
                                height: 95,
                                fit: BoxFit.cover,
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 7, 4, 2),
                                child: Text(
                                  '${evidencia.latitud.toStringAsFixed(5)}, '
                                  '${evidencia.longitud.toStringAsFixed(5)}\n'
                                  '±${evidencia.precisionMetros.round()} m · '
                                  '${fecha.hour.toString().padLeft(2, '0')}:'
                                  '${fecha.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  tooltip: 'Quitar evidencia',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _enviando
                                      ? null
                                      : () => setState(
                                            () => _evidencias.remove(evidencia),
                                          ),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _enviando || _obteniendoUbicacion || _adjuntandoEvidencia
                      ? null
                      : _tomarUbicacion,
                  icon: _obteniendoUbicacion
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(
                    _posicion == null
                        ? 'Usar mi ubicación'
                        : 'Actualizar ubicación del reporte',
                  ),
                ),
                if (_posicion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ubicación capturada: '
                    '${_posicion!.latitude.toStringAsFixed(5)}, '
                    '${_posicion!.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: Color(0xFF61716B),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB3261E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _enviando || _adjuntandoEvidencia ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_enviando ? 'Enviando…' : 'Enviar a revisión'),
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






