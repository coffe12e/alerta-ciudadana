import 'package:image_picker/image_picker.dart';

class EvidenciaAdjunta {
  const EvidenciaAdjunta({
    required this.archivo,
    required this.latitud,
    required this.longitud,
    required this.precisionMetros,
    required this.capturadaUtc,
  });

  final XFile archivo;
  final double latitud;
  final double longitud;
  final double precisionMetros;
  final DateTime capturadaUtc;

  Map<String, dynamic> toMetadataJson() => {
        'latitud': latitud,
        'longitud': longitud,
        'precisionMetros': precisionMetros,
        'capturadaUtc': capturadaUtc.toUtc().toIso8601String(),
      };
}
