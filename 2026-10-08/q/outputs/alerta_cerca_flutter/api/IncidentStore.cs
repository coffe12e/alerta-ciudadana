using System.Text.Json;

namespace AlertaCerca.Api;

public sealed class IncidentStore
{
    private readonly string _jsonPath;
    private readonly string _evidenceDirectory;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly JsonSerializerOptions _jsonOptions =
        new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private List<Incident> _items;

    public IncidentStore(string dataDirectory)
    {
        Directory.CreateDirectory(dataDirectory);
        _evidenceDirectory = Path.Combine(dataDirectory, "evidencias");
        Directory.CreateDirectory(_evidenceDirectory);
        _jsonPath = Path.Combine(dataDirectory, "incidentes.json");

        try
        {
            _items = File.Exists(_jsonPath)
                ? JsonSerializer.Deserialize<List<Incident>>(
                      File.ReadAllText(_jsonPath), _jsonOptions) ?? new()
                : new();
        }
        catch (JsonException)
        {
            _items = new();
        }
    }

    public string EvidenceDirectory => _evidenceDirectory;

    public async Task<List<Incident>> ListAsync()
    {
        await _gate.WaitAsync();
        try
        {
            return _items.ToList();
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<Incident> AddAsync(Incident incident)
    {
        await _gate.WaitAsync();
        try
        {
            var nextId = _items.Count == 0 ? 1 : _items.Max(item => item.AlertaId) + 1;
            var saved = incident with { AlertaId = nextId };
            _items.Add(saved);
            await SaveAsync();
            return saved;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<Incident?> UpdateAsync(
        int id,
        Func<Incident, Incident> update)
    {
        await _gate.WaitAsync();
        try
        {
            var index = _items.FindIndex(item => item.AlertaId == id);
            if (index < 0) return null;

            var updated = update(_items[index]);
            _items[index] = updated;
            await SaveAsync();
            return updated;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<(Incident? Incident, Evidence? Evidence, string? Path)>
        FindEvidenceAsync(int incidentId, string evidenceId)
    {
        await _gate.WaitAsync();
        try
        {
            var incident = _items.FirstOrDefault(item => item.AlertaId == incidentId);
            var evidence = incident?.Evidencias.FirstOrDefault(
                item => item.EvidenciaId == evidenceId);
            if (incident is null || evidence is null)
                return (null, null, null);

            var path = Path.Combine(_evidenceDirectory, evidence.NombreArchivo);
            return File.Exists(path)
                ? (incident, evidence, path)
                : (incident, evidence, null);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task SaveAsync()
    {
        var temporaryPath = _jsonPath + ".tmp";
        await File.WriteAllTextAsync(
            temporaryPath,
            JsonSerializer.Serialize(_items, _jsonOptions));
        File.Move(temporaryPath, _jsonPath, overwrite: true);
    }
}
