using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AlertaCerca.Api;

var builder = WebApplication.CreateBuilder(args);
var dataDirectory = Path.Combine(builder.Environment.ContentRootPath, "App_Data");
builder.Services.AddSingleton(new IncidentStore(dataDirectory));

var adminToken = builder.Configuration["ALERTA_ADMIN_TOKEN"];
var tokenGeneratedForDemo = string.IsNullOrWhiteSpace(adminToken);
if (tokenGeneratedForDemo)
{
    adminToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
}

var app = builder.Build();
var store = app.Services.GetRequiredService<IncidentStore>();
var jsonOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web);

if (tokenGeneratedForDemo)
{
    app.Logger.LogWarning(
        "Token temporal de administrador para esta demo local: {AdminToken}",
        adminToken);
    app.Logger.LogWarning(
        "No uses este mecanismo de token ni HTTP sin TLS en producción.");
}

app.MapGet("/health", () => Results.Ok(new { estado = "ok" }));

app.MapGet(
    "/api/alertas/cercanas",
    async (double lat, double lon, int radioMetros, IncidentStore incidentStore) =>
    {
        if (!CoordenadasValidas(lat, lon))
            return Results.BadRequest(new { error = "La ubicación no es válida." });
        if (radioMetros is < 100 or > 50000)
            return Results.BadRequest(new { error = "El radio debe estar entre 100 y 50000 metros." });

        var incidentes = await incidentStore.ListAsync();
        var cercanas = incidentes
            .Where(item => item.Estado == "VERIFICADA")
            .Select(item => new
            {
                Incidente = item,
                Distancia = DistanciaMetros(lat, lon, item.Latitud, item.Longitud)
            })
            .Where(result =>
                result.Distancia <= Math.Min(radioMetros, result.Incidente.RadioMetros))
            .OrderBy(result => result.Distancia)
            .Select(result => new
            {
                alertaId = result.Incidente.AlertaId,
                categoria = result.Incidente.Categoria,
                titulo = result.Incidente.Titulo,
                descripcion = result.Incidente.Descripcion,
                estado = result.Incidente.Estado,
                creadaUtc = result.Incidente.CreadaUtc,
                latitud = Math.Round(result.Incidente.Latitud, 3),
                longitud = Math.Round(result.Incidente.Longitud, 3),
                radioMetros = result.Incidente.RadioMetros,
                distanciaMetros = Math.Round(result.Distancia, 1)
            })
            .ToList();

        return Results.Ok(cercanas);
    });

app.MapPost(
    "/api/reportes",
    async (HttpRequest request, IncidentStore incidentStore) =>
    {
        ReportRequest reporte;
        List<IFormFile> archivos;
        if (request.HasFormContentType)
        {
            var form = await request.ReadFormAsync();
            if (!LeerDouble(form["latitud"], out var latitud) ||
                !LeerDouble(form["longitud"], out var longitud))
            {
                return Results.BadRequest(new { error = "La ubicación del reporte no es válida." });
            }

            var metadataText = form["evidenciasMetadata"].ToString();
            List<EvidenceMetadata> metadata;
            try
            {
                metadata = string.IsNullOrWhiteSpace(metadataText)
                    ? new List<EvidenceMetadata>()
                    : JsonSerializer.Deserialize<List<EvidenceMetadata>>(
                        metadataText, jsonOptions) ?? new List<EvidenceMetadata>();
            }
            catch (JsonException)
            {
                return Results.BadRequest(new { error = "Los datos GPS de las evidencias no son válidos." });
            }

            reporte = new ReportRequest
            {
                Categoria = form["categoria"].ToString(),
                Titulo = form["titulo"].ToString(),
                Descripcion = form["descripcion"].ToString(),
                Latitud = latitud,
                Longitud = longitud,
                EvidenciasMetadata = metadata
            };
            archivos = form.Files
                .Where(file => file.Name == "evidencias")
                .ToList();
        }
        else
        {
            reporte = await request.ReadFromJsonAsync<ReportRequest>(jsonOptions)
                ?? new ReportRequest();
            archivos = new List<IFormFile>();
        }

        var evidenciasMetadata = reporte.EvidenciasMetadata ?? new List<EvidenceMetadata>();
        if (string.IsNullOrWhiteSpace(reporte.Titulo) ||
            string.IsNullOrWhiteSpace(reporte.Descripcion))
        {
            return Results.BadRequest(new { error = "Escribe un título y una descripción." });
        }
        if (reporte.Titulo.Length > 120 || reporte.Descripcion.Length > 1000)
            return Results.BadRequest(new { error = "El título admite 120 caracteres y la descripción 1000." });
        if (!CoordenadasValidas(reporte.Latitud, reporte.Longitud))
            return Results.BadRequest(new { error = "La ubicación del reporte no es válida." });
        if (archivos.Count > 4 || archivos.Count != evidenciasMetadata.Count)
            return Results.BadRequest(new { error = "Cada foto debe incluir una ubicación GPS; el máximo es 4." });

        foreach (var archivo in archivos)
        {
            if (archivo.Length == 0 || archivo.Length > 5 * 1024 * 1024)
                return Results.BadRequest(new { error = "Cada fotografía debe pesar entre 1 byte y 5 MB." });
            if (!TipoImagenPermitido(archivo.ContentType))
                return Results.BadRequest(new { error = "Solo se aceptan archivos de imagen." });
        }
        if (evidenciasMetadata.Any(item =>
                !CoordenadasValidas(item.Latitud, item.Longitud) ||
                item.PrecisionMetros < 0 ||
                !double.IsFinite(item.PrecisionMetros) ||
                item.PrecisionMetros > 100000))
        {
            return Results.BadRequest(new { error = "Una evidencia contiene coordenadas o precisión inválidas." });
        }

        var evidencias = new List<Evidence>();
        for (var index = 0; index < archivos.Count; index++)
        {
            var archivo = archivos[index];
            var metadatos = evidenciasMetadata[index];
            var extension = ExtensionImagen(archivo.ContentType);
            var nombreSeguro = Guid.NewGuid().ToString("N") + extension;
            var ruta = Path.Combine(incidentStore.EvidenceDirectory, nombreSeguro);
            await using (var salida = File.Create(ruta))
            {
                await archivo.CopyToAsync(salida);
            }

            evidencias.Add(new Evidence
            {
                EvidenciaId = Guid.NewGuid().ToString("N"),
                NombreArchivo = nombreSeguro,
                ContentType = archivo.ContentType,
                Latitud = metadatos.Latitud,
                Longitud = metadatos.Longitud,
                PrecisionMetros = metadatos.PrecisionMetros,
                CapturadaUtc = metadatos.CapturadaUtc == default
                    ? DateTimeOffset.UtcNow
                    : metadatos.CapturadaUtc
            });
        }

        var ahora = DateTimeOffset.UtcNow;
        var incidente = await incidentStore.AddAsync(new Incident
        {
            Categoria = string.IsNullOrWhiteSpace(reporte.Categoria)
                ? "OTRA"
                : reporte.Categoria.Trim().ToUpperInvariant(),
            Titulo = reporte.Titulo.Trim(),
            Descripcion = reporte.Descripcion.Trim(),
            Estado = "PENDIENTE",
            CreadaUtc = ahora,
            ActualizadaUtc = ahora,
            Latitud = reporte.Latitud,
            Longitud = reporte.Longitud,
            RadioMetros = 3000,
            Evidencias = evidencias
        });

        return Results.Created(
            "/api/admin/incidentes",
            new { id = incidente.AlertaId, estado = incidente.Estado });
    });

app.MapGet(
    "/api/admin/incidentes",
    async (HttpRequest request, string? estado, IncidentStore incidentStore) =>
    {
        if (!TokenValido(request, adminToken!))
            return Results.Unauthorized();

        var incidentes = await incidentStore.ListAsync();
        var resultado = string.IsNullOrWhiteSpace(estado) || estado == "TODOS"
            ? incidentes
            : incidentes.Where(item =>
                    item.Estado.Equals(estado, StringComparison.OrdinalIgnoreCase))
                .ToList();

        return Results.Ok(resultado.OrderByDescending(item => item.CreadaUtc));
    });

app.MapPatch(
    "/api/admin/incidentes/{id:int}/estado",
    async (
        int id,
        UpdateIncidentRequest cambio,
        HttpRequest request,
        IncidentStore incidentStore) =>
    {
        if (!TokenValido(request, adminToken!))
            return Results.Unauthorized();

        var estado = cambio.Estado.Trim().ToUpperInvariant();
        var estadosPermitidos = new[] { "EN_REVISION", "VERIFICADA", "RECHAZADA", "RESUELTA" };
        if (!estadosPermitidos.Contains(estado))
            return Results.BadRequest(new { error = "El estado solicitado no es válido." });
        if (cambio.RadioMetros is < 100 or > 50000)
            return Results.BadRequest(new { error = "El radio debe estar entre 100 y 50000 metros." });

        var actualizado = await incidentStore.UpdateAsync(id, actual =>
        {
            if (actual.Estado is "RESUELTA" or "RECHAZADA")
                return actual;

            return actual with
            {
                Estado = estado,
                RadioMetros = estado == "VERIFICADA"
                    ? cambio.RadioMetros
                    : actual.RadioMetros,
                NotaRevision = string.IsNullOrWhiteSpace(cambio.NotaRevision)
                    ? actual.NotaRevision
                    : cambio.NotaRevision.Trim(),
                ActualizadaUtc = DateTimeOffset.UtcNow
            };
        });

        if (actualizado is null)
            return Results.NotFound(new { error = "No se encontró el incidente." });
        if (actualizado.Estado != estado)
            return Results.Conflict(new { error = "Un incidente cerrado no se puede reabrir." });

        return Results.Ok(actualizado);
    });

app.MapGet(
    "/api/admin/incidentes/{id:int}/evidencias/{evidenciaId}",
    async (
        int id,
        string evidenciaId,
        HttpRequest request,
        IncidentStore incidentStore) =>
    {
        if (!TokenValido(request, adminToken!))
            return Results.Unauthorized();

        var result = await incidentStore.FindEvidenceAsync(id, evidenciaId);
        if (result.Path is null || result.Evidence is null)
            return Results.NotFound(new { error = "No se encontró la evidencia." });

        return Results.File(result.Path, result.Evidence.ContentType);
    });

app.Run();

static bool TokenValido(HttpRequest request, string tokenEsperado)
{
    const string prefijo = "Bearer ";
    var encabezado = request.Headers["Authorization"].ToString();
    if (!encabezado.StartsWith(prefijo, StringComparison.OrdinalIgnoreCase))
        return false;

    var recibido = Encoding.UTF8.GetBytes(encabezado[prefijo.Length..].Trim());
    var esperado = Encoding.UTF8.GetBytes(tokenEsperado);
    return recibido.Length == esperado.Length &&
           CryptographicOperations.FixedTimeEquals(recibido, esperado);
}

static bool LeerDouble(string valor, out double resultado) =>
    double.TryParse(
        valor,
        NumberStyles.Float,
        CultureInfo.InvariantCulture,
        out resultado);

static bool CoordenadasValidas(double latitud, double longitud) =>
    double.IsFinite(latitud) &&
    double.IsFinite(longitud) &&
    latitud is >= -90 and <= 90 &&
    longitud is >= -180 and <= 180;

static double DistanciaMetros(double lat1, double lon1, double lat2, double lon2)
{
    const double radioTierraMetros = 6371000;
    var diferenciaLatitud = GradosARadianes(lat2 - lat1);
    var diferenciaLongitud = GradosARadianes(lon2 - lon1);
    var a = Math.Pow(Math.Sin(diferenciaLatitud / 2), 2) +
            Math.Cos(GradosARadianes(lat1)) *
            Math.Cos(GradosARadianes(lat2)) *
            Math.Pow(Math.Sin(diferenciaLongitud / 2), 2);
    a = Math.Clamp(a, 0, 1);
    return radioTierraMetros * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
}

static double GradosARadianes(double grados) => grados * Math.PI / 180;

static bool TipoImagenPermitido(string contentType) =>
    contentType.ToLowerInvariant() is
        "image/jpeg" or "image/png" or "image/webp" or "image/heic" or "image/heif";

static string ExtensionImagen(string contentType) =>
    contentType.ToLowerInvariant() switch
    {
        "image/jpeg" => ".jpg",
        "image/png" => ".png",
        "image/webp" => ".webp",
        "image/heic" => ".heic",
        "image/heif" => ".heif",
        _ => ".img"
    };


