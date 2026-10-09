# API de demostración

API ASP.NET Core minimalista para que el MVP Flutter pueda recibir reportes con evidencia geolocalizada, calcular alertas cercanas y permitir la moderación de incidentes.

La información se guarda en **App_Data** como JSON e imágenes privadas. Es almacenamiento de desarrollo local, no una base de datos para producción.

## Endpoints

- **POST /api/reportes**: acepta JSON sin fotos o **multipart/form-data** con hasta 4 partes **evidencias** y un arreglo JSON **evidenciasMetadata**.
- **GET /api/alertas/cercanas?lat=...&lon=...&radioMetros=...**: devuelve solo incidentes **VERIFICADA** dentro del radio configurado por moderación.
- **GET /api/admin/incidentes?estado=PENDIENTE**: lista incidentes. Requiere **Authorization: Bearer <token>**.
- **PATCH /api/admin/incidentes/{id}/estado**: cambia el estado, radio y nota de revisión. Requiere token.
- **GET /api/admin/incidentes/{id}/evidencias/{evidenciaId}**: obtiene una foto privada para moderación. Requiere token.
- **GET /health**: estado de la API.

Estados admitidos: **PENDIENTE**, **EN_REVISION**, **VERIFICADA**, **RECHAZADA**, **RESUELTA**. Solo **VERIFICADA** se difunde. Los estados **RECHAZADA** y **RESUELTA** son finales en esta demo.

## Token

Si no se define **ALERTA_ADMIN_TOKEN**, la API genera un token aleatorio nuevo al iniciarse y lo muestra en la consola. En un entorno administrado, configura una variable de entorno protegida. No guardes el token en el código ni lo distribuyas en una versión móvil pública.

Esta autorización compartida es un atajo de demo, no sustituye a un proveedor de identidad ni a roles individuales.
