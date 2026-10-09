# ALERTA CERCA — MVP Flutter + API

Este paquete completa el flujo de demostración de ALERTA CERCA:

- La persona adjunta hasta 4 fotos desde la cámara o la galería. Al adjuntar cada foto, la app captura latitud, longitud, precisión GPS y hora.
- La app consulta alertas verificadas por proximidad cada minuto mientras permanece abierta y muestra un aviso dentro de la app cuando aparece una alerta nueva.
- Una persona moderadora entra al panel de incidentes con un token, revisa reportes y evidencia, y puede marcar un reporte en revisión, verificarlo, rechazarlo o cerrarlo como resuelto.
- La API calcula distancias y solo publica alertas en estado **VERIFICADA**. La respuesta pública redondea las coordenadas a aproximadamente 100 metros; la ubicación precisa queda disponible solo en el panel autenticado.

## Requisitos

- Flutter con Dart 3.5 o posterior.
- .NET 8 SDK para ejecutar la API. El runtime por sí solo no basta para compilarla.
- Android Studio y un emulador Android, o un teléfono Android conectado por USB/Wi-Fi.

## Preparar la app Flutter

En PowerShell, desde la carpeta donde quieras guardar el proyecto:

~~~powershell
flutter create alerta_cerca
cd alerta_cerca
~~~

Copia **lib** y **pubspec.yaml** de este paquete dentro de la carpeta creada, reemplazando los archivos existentes. Después ejecuta:

~~~powershell
flutter pub get
~~~

Abre **android/app/src/main/AndroidManifest.xml** y agrega estos permisos inmediatamente debajo de **<manifest ...>**:

~~~xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
~~~

Para ejecutar la API local por HTTP durante el desarrollo, agrega **android:usesCleartextTraffic="true"** al elemento **<application ...>**. Elimínalo al cambiar a HTTPS.

Para iOS, agrega a **ios/Runner/Info.plist** las claves **NSLocationWhenInUseUsageDescription**, **NSCameraUsageDescription** y **NSPhotoLibraryUsageDescription**, con una explicación en español de cada permiso.

## Iniciar la API

Abre una segunda ventana de PowerShell y ejecuta:

~~~powershell
cd ruta\al\paquete\alerta_cerca_flutter\api
dotnet run --urls "http://0.0.0.0:5080"
~~~

La primera vez se genera un token temporal de moderación y aparece en esa consola. Cópialo; la app lo pedirá al abrir **Más opciones → Administración de incidentes**. El token cambia al reiniciar la API si no configuras **ALERTA_ADMIN_TOKEN**.

La API guarda los registros en **api/App_Data/incidentes.json** y las imágenes privadas en **api/App_Data/evidencias**. No publica esas imágenes en una ruta pública: solo las entrega a una solicitud autenticada de administración.

## Ejecutar la app

Mantén la API abierta. En la primera ventana de PowerShell, desde el proyecto Flutter, ejecuta:

~~~powershell
flutter run --dart-define=ALERTA_API_URL=http://10.0.2.2:5080
~~~

**10.0.2.2** es la dirección de la computadora vista desde el emulador Android.

Para un teléfono Android conectado a la misma red Wi-Fi, reemplaza **10.0.2.2** por la dirección IPv4 de la computadora. Puedes verla con **ipconfig**. Permite el puerto 5080 en el firewall solo para la red privada de confianza.

## Flujo de la demostración

1. En la app, pulsa **Reportar situación**.
2. Escribe categoría, título y descripción.
3. Toma o elige una foto. La app no la agrega si no logra capturar su GPS.
4. Envía el reporte; queda como **PENDIENTE** y no se difunde.
5. Abre **Administración de incidentes**, pega el token de la consola y entra.
6. Expande el reporte para ver sus fotos, ubicaciones y horas. Marca el reporte **EN_REVISION**, **VERIFICADA** o **RECHAZADA**.
7. Al verificar, elige un radio de 1, 3, 5 o 10 km. Ese reporte ya puede aparecer en la lista de usuarios cercanos.
8. Cuando se resuelva, marca **RESUELTA**; dejará de aparecer en alertas cercanas.

Para probar la proximidad en un emulador, configura una ubicación de prueba dentro del radio de una alerta verificada desde los controles de ubicación del emulador.

## Alcance y privacidad

El monitoreo de proximidad es voluntario y funciona **solo mientras la app está abierta**. Consulta el GPS una vez por minuto y avisa dentro de la app. No envía notificaciones push ni vigila la ubicación en segundo plano. Eso requeriría un servicio push real, registro de dispositivos y permisos/configuración adicionales.

Esta API es para demostración local: persiste en JSON, usa un token temporal compartido y no implementa cuentas individuales, bitácora de auditoría, cifrado de archivos ni políticas de retención. No la expongas a Internet ni uses información real de personas desaparecidas, víctimas o menores. Para un piloto público se necesitan autenticación por usuario/rol, HTTPS, almacenamiento protegido, controles de acceso, auditoría y revisión del aviso de privacidad.

Las fotos pueden contener datos personales y la ubicación GPS es precisa. La moderación es el único flujo de acceso de esta demo a la evidencia almacenada. Conserva solo datos ficticios durante las pruebas.

