import 'evidencia.dart';

class Alerta {
  const Alerta({
    required this.id,
    required this.categoria,
    required this.titulo,
    required this.descripcion,
    required this.estado,
    required this.creadaUtc,
    required this.latitud,
    required this.longitud,
    required this.distanciaMetros,
  });

  final int id;
  final String categoria;
  final String titulo;
  final String descripcion;
  final String estado;
  final DateTime creadaUtc;
  final double latitud;
  final double longitud;
  final double distanciaMetros;

  factory Alerta.fromJson(Map<String, dynamic> json) {
    dynamic field(String camelCase, String pascalCase) =>
        json[camelCase] ?? json[pascalCase];

    final fecha = DateTime.tryParse(
          field('creadaUtc', 'CreadaUtc')?.toString() ?? '',
        ) ??
        DateTime.now().toUtc();

    return Alerta(
      id: _asInt(field('alertaId', 'AlertaId')),
      categoria: field('categoria', 'Categoria')?.toString() ?? 'OTRA',
      titulo: field('titulo', 'Titulo')?.toString() ?? 'Alerta',
      descripcion: field('descripcion', 'Descripcion')?.toString() ?? '',
      estado: field('estado', 'Estado')?.toString() ?? 'VERIFICADA',
      creadaUtc: fecha,
      latitud: _asDouble(field('latitud', 'Latitud')),
      longitud: _asDouble(field('longitud', 'Longitud')),
      distanciaMetros: _asDouble(
        field('distanciaMetros', 'DistanciaMetros'),
      ),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class NuevoReporte {
  const NuevoReporte({
    required this.categoria,
    required this.titulo,
    required this.descripcion,
    required this.latitud,
    required this.longitud,
    this.evidencias = const [],
  });

  final String categoria;
  final String titulo;
  final String descripcion;
  final double latitud;
  final double longitud;
  final List<EvidenciaAdjunta> evidencias;

  Map<String, dynamic> toJson() => {
        'categoria': categoria,
        'titulo': titulo,
        'descripcion': descripcion,
        'latitud': latitud,
        'longitud': longitud,
        'evidenciasMetadata':
            evidencias.map((item) => item.toMetadataJson()).toList(),
      };
}
