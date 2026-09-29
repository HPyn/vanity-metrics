#requires -Version 7.4
param([string]$Image = 'vanity-metrics:local')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$project = 'vanity-metrics-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$invalidContainer = "$project-missing-token"
$tokenFile = [IO.Path]::GetTempFileName()
$saved = @{}
# Shell variables override --env-file. In Actions, GITHUB_PATH is a runner file,
# not our target log path. Isolate every fixture setting from the caller.
$fixture = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $repo '.env.example')) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $fixture[$Matches[1]] = $Matches[2] }
}
foreach ($key in $fixture.Keys) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key)
}
function Invoke-Docker {
    param([string[]]$Arguments)
    $output = & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed with exit code $LASTEXITCODE." }
    return $output
}
function Require {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
$compose = @('compose', '--project-directory', $repo, '--env-file', (Join-Path $repo '.env.example'), '-p', $project)
try {
    foreach ($key in $fixture.Keys) { [Environment]::SetEnvironmentVariable($key, $fixture[$key]) }
    $env:GITHUB_TOKEN_SOURCE = $tokenFile
    $env:VANITY_METRICS_IMAGE = $Image
    $env:DRY_RUN = 'true'
    $env:INTERVAL_MINUTES = '1'
    $env:WORK_START_HOUR = '0'
    $env:WORK_END_HOUR = '24'
    $env:COMMIT_PROBABILITY = '1'
    $env:QUIET_WEEK_MULTIPLIER = '1'
    $null = Invoke-Docker ($compose + @('config', '--quiet'))
    $null = Invoke-Docker ($compose + @('up', '-d', '--no-build', '--wait', '--wait-timeout', '90'))
    $id = (Invoke-Docker ($compose + @('ps', '-q', 'worker'))).Trim()
    $info = (Invoke-Docker @('inspect', $id) | ConvertFrom-Json)[0]
    Require ($info.Config.User -eq '10001:10001') 'Worker must run without root privileges.'
    Require $info.HostConfig.ReadonlyRootfs 'Worker root filesystem must be read-only.'
    Require ($info.State.Health.Status -eq 'healthy') 'Worker failed its health check.'
    Require ($info.HostConfig.RestartPolicy.Name -eq 'unless-stopped') 'Compose restart policy was not applied.'
    # Wait for one real scheduled tick; dry-run guarantees no network or repository writes.
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(70)
    do {
        $logs = (Invoke-Docker @('logs', $id)) -join "`n"
        if ($logs -match 'DRY RUN:|Skipped:') { break }
        Start-Sleep -Seconds 2
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    Require ($logs -match 'DRY RUN:|Skipped:') 'Worker did not execute a scheduled tick.'
    Require ($logs -notmatch '\[ERROR\]') 'Worker logged an unexpected error.'
    $null = Invoke-Docker ($compose + @('stop', 'worker'))
    $info = (Invoke-Docker @('inspect', $id) | ConvertFrom-Json)[0]
    Require ($info.State.ExitCode -eq 0) 'Worker failed to shut down gracefully.'
    $logs = (Invoke-Docker @('logs', $id)) -join "`n"
    Require ($logs -match 'Worker stopped\.') 'SIGTERM shutdown did not complete.'
    $null = Invoke-Docker ($compose + @('start', 'worker'))
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
    do {
        $info = (Invoke-Docker @('inspect', $id) | ConvertFrom-Json)[0]
        if ($info.State.Health.Status -eq 'healthy') { break }
        Start-Sleep -Seconds 2
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    Require ($info.State.Health.Status -eq 'healthy') 'Worker failed to recover after restart.'
    # Exercise live-mode failure reporting without credentials or network access.
    $null = Invoke-Docker @('run', '-d', '--name', $invalidContainer, '--network', 'none', '--read-only', '--tmpfs', '/tmp:rw,nosuid,nodev,size=128m,mode=1777', '-e', 'DRY_RUN=false', $Image)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(20)
    do {
        $logs = (Invoke-Docker @('logs', $invalidContainer)) -join "`n"
        if ($logs -match 'Cannot read GITHUB_TOKEN_FILE') { break }
        Start-Sleep -Seconds 1
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    Require ($logs -match '\[ERROR\].*Cannot read GITHUB_TOKEN_FILE') 'Missing-token failure was not clearly logged.'
    # The worker updates health immediately after recording the error.
    Start-Sleep -Seconds 2
    & docker exec $invalidContainer pwsh -NoLogo -NoProfile -File /app/Test-Health.ps1
    Require ($LASTEXITCODE -eq 1) 'Health probe must fail after an authentication setup error.'
    & docker run --rm --network none -e INTERVAL_MINUTES=0 $Image -Once
    Require ($LASTEXITCODE -eq 1) 'Invalid configuration must fail with a nonzero exit code.'
    Write-Host 'Container tests passed: Compose startup, health, scheduling, non-root/read-only operation, graceful stop, restart, missing-token health failure, and invalid configuration.'
}
catch {
    & docker @compose logs --no-color --tail 100 | Out-Host
    throw
}
finally {
    & docker rm -f $invalidContainer 2>$null | Out-Null
    & docker @compose down --remove-orphans | Out-Host
    Remove-Item -LiteralPath $tokenFile -Force
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
}
