#requires -Version 7.4
[CmdletBinding()]
param([switch]$Once, [switch]$CheckAccess)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/Worker.psm1" -Force
try { $config = Get-WorkerConfig }
catch { Write-WorkerLog $_.Exception.Message -Level ERROR; exit 1 }

if ($CheckAccess) {
    try {
        $null = Get-GitHubFile $config
        Write-WorkerLog 'GitHub authentication and target file read succeeded. Write permission is verified only by an actual commit.'
        exit 0
    }
    catch { Write-WorkerLog $_.Exception.Message -Level ERROR; exit 1 }
}
if ($Once) {
    try { Invoke-WorkerTick $config; exit 0 }
    catch { Write-WorkerLog $_.Exception.Message -Level ERROR; exit 1 }
}

# Signal callbacks run on a .NET thread and must not execute PowerShell scriptblocks.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WorkerShutdown {
    public static volatile bool Requested;
    private static PosixSignalRegistration term, interrupt;
    public static void Register() {
        if (!OperatingSystem.IsWindows()) {
            term = PosixSignalRegistration.Create(PosixSignal.SIGTERM, ctx => { ctx.Cancel = true; Requested = true; });
            interrupt = PosixSignalRegistration.Create(PosixSignal.SIGINT, ctx => { ctx.Cancel = true; Requested = true; });
        }
    }
    public static void Dispose() { term?.Dispose(); interrupt?.Dispose(); }
}
'@
[WorkerShutdown]::Register()
$statePath = Join-Path ([IO.Path]::GetTempPath()) 'vanity-metrics-health.json'
$failure = $null
function Save-Health {
    @{ heartbeat = [DateTimeOffset]::UtcNow.ToString('o'); error = $script:failure } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath "$statePath.tmp" -Encoding utf8
    Move-Item -LiteralPath "$statePath.tmp" -Destination $statePath -Force
}

Write-WorkerLog "Worker started: $($config.GITHUB_OWNER)/$($config.GITHUB_REPO), branch $($config.GITHUB_BRANCH); interval $($config.INTERVAL_MINUTES)m; timezone $($config.TIME_ZONE); dry-run=$($config.DRY_RUN)."
try {
    Save-Health
    if (-not $config.DRY_RUN) {
        try { $null = Get-GitHubFile $config; Write-WorkerLog 'Startup GitHub access check passed.' }
        catch { $failure = $_.Exception.Message; Write-WorkerLog $failure -Level ERROR }
    }
    $next = Get-NextTickUtc -UtcNow ([DateTimeOffset]::UtcNow) -IntervalMinutes $config.INTERVAL_MINUTES
    Write-WorkerLog "Next scheduled tick: $($next.ToString('o'))."
    while (-not (Test-WorkerStopping)) {
        Save-Health
        if ([DateTimeOffset]::UtcNow -ge $next) {
            try {
                if ($failure -and -not $config.DRY_RUN) { $null = Get-GitHubFile $config }
                Invoke-WorkerTick $config
                $failure = $null
            }
            catch [OperationCanceledException] { break }
            catch { $failure = $_.Exception.Message; Write-WorkerLog $failure -Level ERROR }
            $next = Get-NextTickUtc -UtcNow ([DateTimeOffset]::UtcNow) -IntervalMinutes $config.INTERVAL_MINUTES
            Save-Health
        }
        Start-Sleep -Seconds 1
    }
}
finally {
    [WorkerShutdown]::Dispose()
    Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
    Write-WorkerLog 'Worker stopped.'
}
