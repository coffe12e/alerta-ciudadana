import 'package:geolocator/geolocator.dart';

class UbicacionService {
  static Future<Position> obtenerActual() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      throw Exception('Activa la ubicación del teléfono e inténtalo otra vez.');
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied) {
      throw Exception('Se necesita permiso de ubicación para buscar alertas.');
    }

    if (permiso == LocationPermission.deniedForever) {
      throw Exception(
        'El permiso está bloqueado. Actívalo en la configuración de la app.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      ),
    );
  }
}
