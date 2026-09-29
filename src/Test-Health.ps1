$ErrorActionPreference = 'Stop'
try {
    $state = Get-Content -Raw -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) 'vanity-metrics-health.json') | ConvertFrom-Json
    if ($state.error -or ([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($state.heartbeat)).TotalSeconds -gt 180) { exit 1 }
    exit 0
}
catch { exit 1 }
