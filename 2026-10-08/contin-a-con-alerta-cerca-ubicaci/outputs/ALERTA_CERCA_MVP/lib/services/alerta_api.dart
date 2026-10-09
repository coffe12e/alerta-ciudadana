import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/alerta.dart';
import '../models/evidencia.dart';
import '../models/incidente.dart';

class AlertaApi {
  AlertaApi({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = String.fromEnvironment(
    'ALERTA_API_URL',
    defaultValue: 'http://10.0.2.2:5080',
  );

  final http.Client _client;

  Future<List<Alerta>> obtenerCercanas({
    required double latitud,
    required double longitud,
    required int radioMetros,
  }) async {
    final uri = Uri.parse('$baseUrl/api/alertas/cercanas').replace(
      queryParameters: {
        'lat': latitud.toString(),
        'lon': longitud.toString(),
        'radioMetros': radioMetros.toString(),
      },
    );

    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response));
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw Exception('La API respondió con un formato inesperado.');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Alerta.fromJson)
        .toList();
  }

  Future<int> crearReporte(NuevoReporte reporte) async {
    if (reporte.evidencias.isEmpty) {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/reportes'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(reporte.toJson()),
          )
          .timeout(const Duration(seconds: 30));
      return _leerId(response);
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/reportes'),
    )
      ..headers['Accept'] = 'application/json'
      ..fields.addAll({
        'categoria': reporte.categoria,
        'titulo': reporte.titulo,
        'descripcion': reporte.descripcion,
        'latitud': reporte.latitud.toString(),
        'longitud': reporte.longitud.toString(),
        'evidenciasMetadata': jsonEncode(
          reporte.evidencias.map((item) => item.toMetadataJson()).toList(),
        ),
      });

    for (final evidencia in reporte.evidencias) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'evidencias',
          evidencia.archivo.path,
          filename: evidencia.archivo.name,
        ),
      );
    }

    final streamed = await _client.send(request).timeout(
          const Duration(seconds: 45),
        );
    final response = await http.Response.fromStream(streamed);
    return _leerId(response);
  }

  Future<List<Incidente>> obtenerIncidentesAdmin({
    required String token,
    String? estado,
  }) async {
    final query = estado == null || estado == 'TODOS'
        ? <String, String>{}
        : <String, String>{'estado': estado};
    final uri = Uri.parse('$baseUrl/api/admin/incidentes')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await _client
        .get(uri, headers: _adminHeaders(token))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response));
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw Exception('La API respondió con un formato inesperado.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Incidente.fromJson)
        .toList();
  }

  Future<void> actualizarIncidente({
    required int id,
    required String estado,
    required String token,
    required int radioMetros,
    String notaRevision = '',
  }) async {
    final response = await _client
        .patch(
          Uri.parse('$baseUrl/api/admin/incidentes/$id/estado'),
          headers: {
            ..._adminHeaders(token),
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode({
            'estado': estado,
            'radioMetros': radioMetros,
            'notaRevision': notaRevision,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response));
    }
  }

  Future<Uint8List> obtenerEvidenciaAdmin({
    required int incidenteId,
    required String evidenciaId,
    required String token,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/admin/incidentes/$incidenteId/evidencias/$evidenciaId',
    );
    final response = await _client
        .get(uri, headers: _adminHeaders(token))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response));
    }
    return response.bodyBytes;
  }

  int _leerId(http.Response response) {
    if (response.statusCode != 201) {
      throw Exception(_mensajeError(response));
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final id = decoded['id'] ?? decoded['Id'] ?? decoded['alertaId'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  Map<String, String> _adminHeaders(String token) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  String _mensajeError(http.Response response) {
    try {
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final message = decoded['error'] ?? decoded['message'] ?? decoded['title'];
      if (message != null && message.toString().isNotEmpty) {
        return message.toString();
      }
    } catch (_) {
      // El servidor quizá devolvió una respuesta que no es JSON.
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isNotEmpty) return body;
    return 'Error HTTP ' +
        response.statusCode.toString() +
        ' al comunicarse con la API.';
  }

  void dispose() => _client.close();
}
