import 'evidencia.dart';

class Incidente {
  const Incidente({
    required this.id,
    required this.categoria,
    required this.titulo,
    required this.descripcion,
    required this.estado,
    required this.creadaUtc,
    required this.latitud,
    required this.longitud,
    required this.radioMetros,
    required this.notaRevision,
    required this.evidencias,
  });

  final int id;
  final String categoria;
  final String titulo;
  final String descripcion;
  final String estado;
  final DateTime creadaUtc;
  final double latitud;
  final double longitud;
  final int radioMetros;
  final String? notaRevision;
  final List<EvidenciaRemota> evidencias;

  factory Incidente.fromJson(Map<String, dynamic> json) {
    dynamic field(String camel, String pascal) => json[camel] ?? json[pascal];
    final rawEvidence = field('evidencias', 'Evidencias');
    final evidence = rawEvidence is List
        ? rawEvidence
            .whereType<Map<String, dynamic>>()
            .map(EvidenciaRemota.fromJson)
            .toList()
        : <EvidenciaRemota>[];

    return Incidente(
      id: _asInt(field('alertaId', 'AlertaId')),
      categoria: field('categoria', 'Categoria')?.toString() ?? 'OTRA',
      titulo: field('titulo', 'Titulo')?.toString() ?? 'Incidente',
      descripcion: field('descripcion', 'Descripcion')?.toString() ?? '',
      estado: field('estado', 'Estado')?.toString() ?? 'PENDIENTE',
      creadaUtc: DateTime.tryParse(
            field('creadaUtc', 'CreadaUtc')?.toString() ?? '',
          ) ??
          DateTime.now().toUtc(),
      latitud: _asDouble(field('latitud', 'Latitud')),
      longitud: _asDouble(field('longitud', 'Longitud')),
      radioMetros: _asInt(field('radioMetros', 'RadioMetros')),
      notaRevision: field('notaRevision', 'NotaRevision')?.toString(),
      evidencias: evidence,
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

class EvidenciaRemota {
  const EvidenciaRemota({
    required this.id,
    required this.nombreArchivo,
    required this.contentType,
    required this.latitud,
    required this.longitud,
    required this.precisionMetros,
    required this.capturadaUtc,
  });

  final String id;
  final String nombreArchivo;
  final String contentType;
  final double latitud;
  final double longitud;
  final double precisionMetros;
  final DateTime capturadaUtc;

  factory EvidenciaRemota.fromJson(Map<String, dynamic> json) {
    dynamic field(String camel, String pascal) => json[camel] ?? json[pascal];
    return EvidenciaRemota(
      id: field('evidenciaId', 'EvidenciaId')?.toString() ?? '',
      nombreArchivo: field('nombreArchivo', 'NombreArchivo')?.toString() ?? '',
      contentType: field('contentType', 'ContentType')?.toString() ?? '',
      latitud: _asDouble(field('latitud', 'Latitud')),
      longitud: _asDouble(field('longitud', 'Longitud')),
      precisionMetros: _asDouble(
        field('precisionMetros', 'PrecisionMetros'),
      ),
      capturadaUtc: DateTime.tryParse(
            field('capturadaUtc', 'CapturadaUtc')?.toString() ?? '',
          ) ??
          DateTime.now().toUtc(),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
