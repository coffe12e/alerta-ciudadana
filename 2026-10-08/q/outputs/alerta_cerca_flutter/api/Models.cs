namespace AlertaCerca.Api;

public sealed record Incident
{
    public int AlertaId { get; init; }
    public string Categoria { get; init; } = "OTRA";
    public string Titulo { get; init; } = "";
    public string Descripcion { get; init; } = "";
    public string Estado { get; init; } = "PENDIENTE";
    public DateTimeOffset CreadaUtc { get; init; }
    public DateTimeOffset ActualizadaUtc { get; init; }
    public double Latitud { get; init; }
    public double Longitud { get; init; }
    public int RadioMetros { get; init; } = 3000;
    public string? NotaRevision { get; init; }
    public List<Evidence> Evidencias { get; init; } = new();
}

public sealed record Evidence
{
    public string EvidenciaId { get; init; } = "";
    public string NombreArchivo { get; init; } = "";
    public string ContentType { get; init; } = "application/octet-stream";
    public double Latitud { get; init; }
    public double Longitud { get; init; }
    public double PrecisionMetros { get; init; }
    public DateTimeOffset CapturadaUtc { get; init; }
}

public sealed record EvidenceMetadata
{
    public double Latitud { get; init; }
    public double Longitud { get; init; }
    public double PrecisionMetros { get; init; }
    public DateTimeOffset CapturadaUtc { get; init; }
}

public sealed record ReportRequest
{
    public string Categoria { get; init; } = "OTRA";
    public string Titulo { get; init; } = "";
    public string Descripcion { get; init; } = "";
    public double Latitud { get; init; }
    public double Longitud { get; init; }
    public List<EvidenceMetadata> EvidenciasMetadata { get; init; } = new();
}

public sealed record UpdateIncidentRequest
{
    public string Estado { get; init; } = "";
    public int RadioMetros { get; init; } = 3000;
    public string? NotaRevision { get; init; }
}
