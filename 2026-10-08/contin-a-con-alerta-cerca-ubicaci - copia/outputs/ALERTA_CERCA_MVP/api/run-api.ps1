$ErrorActionPreference = 'Stop'

dotnet run --project (Join-Path $PSScriptRoot 'AlertaCerca.Api.csproj') -- --urls 'http://0.0.0.0:5080'
