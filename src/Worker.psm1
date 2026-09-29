#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkerConfig {
    param([System.Collections.IDictionary]$Settings = [Environment]::GetEnvironmentVariables())
    $defaults = @{
        GITHUB_OWNER = 'HPyn'; GITHUB_REPO = 'vanity-metrics'; GITHUB_BRANCH = 'main'
        GITHUB_PATH = 'log.md'; GITHUB_TOKEN_FILE = '/run/secrets/github_token'
        TIME_ZONE = 'Australia/Sydney'; WORK_START_HOUR = '9'; WORK_END_HOUR = '17'
        INTERVAL_MINUTES = '30'; COMMIT_PROBABILITY = '0.4'; BUSY_WEEK_MODULO = '4'
        BUSY_WEEK_REMAINDER = '0'; BUSY_WEEK_MULTIPLIER = '2.5'
        QUIET_WEEK_REMAINDER = '2'; QUIET_WEEK_MULTIPLIER = '0.4'; DRY_RUN = 'true'
    }
    $config = @{}
    foreach ($key in $defaults.Keys) {
        $value = if ($Settings.Contains($key)) { [string]$Settings[$key] } else { $defaults[$key] }
        if ([string]::IsNullOrWhiteSpace($value)) { throw "Configuration: $key must not be empty." }
        $config[$key] = $value.Trim()
    }
    foreach ($key in @('WORK_START_HOUR', 'WORK_END_HOUR', 'INTERVAL_MINUTES', 'BUSY_WEEK_MODULO', 'BUSY_WEEK_REMAINDER', 'QUIET_WEEK_REMAINDER')) {
        $number = 0
        if (-not [int]::TryParse($config[$key], [ref]$number)) { throw "Configuration: $key must be an integer." }
        $config[$key] = $number
    }
    foreach ($key in @('COMMIT_PROBABILITY', 'BUSY_WEEK_MULTIPLIER', 'QUIET_WEEK_MULTIPLIER')) {
        $number = 0.0
        if (-not [double]::TryParse($config[$key], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or -not [double]::IsFinite($number)) {
            throw "Configuration: $key must be a finite number using a decimal point."
        }
        $config[$key] = $number
    }
    $dryRun = $false
    if (-not [bool]::TryParse($config.DRY_RUN, [ref]$dryRun)) { throw 'Configuration: DRY_RUN must be true or false.' }
    $config.DRY_RUN = $dryRun
    if ($config.WORK_START_HOUR -lt 0 -or $config.WORK_END_HOUR -gt 24 -or $config.WORK_START_HOUR -ge $config.WORK_END_HOUR) {
        throw 'Configuration: work hours must satisfy 0 <= WORK_START_HOUR < WORK_END_HOUR <= 24.'
    }
    if ($config.INTERVAL_MINUTES -lt 1 -or $config.INTERVAL_MINUTES -gt 60 -or 60 % $config.INTERVAL_MINUTES -ne 0) {
        throw 'Configuration: INTERVAL_MINUTES must be a positive divisor of 60.'
    }
    if ($config.COMMIT_PROBABILITY -lt 0 -or $config.COMMIT_PROBABILITY -gt 1 -or $config.BUSY_WEEK_MULTIPLIER -lt 0 -or $config.QUIET_WEEK_MULTIPLIER -lt 0) {
        throw 'Configuration: probability must be 0..1 and multipliers must be nonnegative.'
    }
    if ($config.BUSY_WEEK_MODULO -lt 2 -or $config.BUSY_WEEK_REMAINDER -lt 0 -or $config.BUSY_WEEK_REMAINDER -ge $config.BUSY_WEEK_MODULO -or $config.QUIET_WEEK_REMAINDER -lt 0 -or $config.QUIET_WEEK_REMAINDER -ge $config.BUSY_WEEK_MODULO -or $config.BUSY_WEEK_REMAINDER -eq $config.QUIET_WEEK_REMAINDER) {
        throw 'Configuration: busy/quiet remainders must be distinct and within 0..BUSY_WEEK_MODULO-1.'
    }
    if ($config.GITHUB_OWNER -notmatch '^[A-Za-z0-9-]+$' -or $config.GITHUB_REPO -notmatch '^[A-Za-z0-9_.-]+$') {
        throw 'Configuration: invalid GitHub owner or repository name.'
    }
    if ($config.GITHUB_PATH.StartsWith('/') -or $config.GITHUB_PATH.Contains('\') -or @($config.GITHUB_PATH.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw 'Configuration: GITHUB_PATH must be a repository-relative file path.'
    }
    try { $config.TimeZone = [TimeZoneInfo]::FindSystemTimeZoneById($config.TIME_ZONE) }
    catch { throw 'Configuration: TIME_ZONE must identify an installed time zone, for example Australia/Sydney.' }
    return $config
}

function Get-CommitDecision {
    param([hashtable]$Config, [DateTimeOffset]$UtcNow = [DateTimeOffset]::UtcNow, [double]$Roll = (Get-Random -Minimum 0.0 -Maximum 1.0))
    $local = [TimeZoneInfo]::ConvertTime($UtcNow, $Config.TimeZone)
    $week = [Globalization.ISOWeek]::GetWeekOfYear($local.DateTime)
    $remainder = $week % $Config.BUSY_WEEK_MODULO
    $multiplier = if ($remainder -eq $Config.BUSY_WEEK_REMAINDER) { $Config.BUSY_WEEK_MULTIPLIER }
        elseif ($remainder -eq $Config.QUIET_WEEK_REMAINDER) { $Config.QUIET_WEEK_MULTIPLIER } else { 1.0 }
    $probability = [Math]::Min(1.0, $Config.COMMIT_PROBABILITY * $multiplier)
    $working = $local.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday) -and $local.Hour -ge $Config.WORK_START_HOUR -and $local.Hour -lt $Config.WORK_END_HOUR
    $reason = if (-not $working) { 'outside working hours' } elseif ($Roll -ge $probability) { 'probability check skipped' } else { 'selected' }
    return [pscustomobject]@{ ShouldCommit = $working -and $Roll -lt $probability; Reason = $reason; LocalTime = $local; Week = $week; Probability = $probability }
}

function Get-NextTickUtc {
    param([DateTimeOffset]$UtcNow, [int]$IntervalMinutes)
    $seconds = $IntervalMinutes * 60L
    # Restarts and missed ticks never cause a burst of catch-up commits.
    $next = ([long][Math]::Floor($UtcNow.ToUnixTimeSeconds() / $seconds) + 1) * $seconds
    return [DateTimeOffset]::FromUnixTimeSeconds($next)
}

function New-FillerText {
    $words = 'lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute irure dolor in reprehenderit voluptate velit esse cillum fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt culpa qui officia deserunt mollit anim id est laborum'.Split(' ')
    $sentenceCount = Get-Random -Minimum 1 -Maximum 4
    $sentences = for ($i = 0; $i -lt $sentenceCount; $i++) {
        $sentence = ((1..(Get-Random -Minimum 6 -Maximum 16) | ForEach-Object { Get-Random -InputObject $words }) -join ' ')
        $sentence.Substring(0, 1).ToUpperInvariant() + $sentence.Substring(1) + '.'
    }
    return ($sentences -join ' ') + "`n`n"
}

function Write-WorkerLog {
    param([string]$Message, [ValidateSet('INFO', 'ERROR')][string]$Level = 'INFO')
    Write-Host "$([DateTimeOffset]::UtcNow.ToString('o')) [$Level] $Message"
}

function Test-WorkerStopping {
    $shutdownType = 'WorkerShutdown' -as [type]
    return $null -ne $shutdownType -and $shutdownType::Requested
}

function Wait-WorkerDelay {
    param([int]$Seconds)
    for ($i = 0; $i -lt $Seconds; $i++) {
        if (Test-WorkerStopping) { throw [OperationCanceledException]::new('Worker stopping.') }
        Start-Sleep -Seconds 1
    }
}

function Invoke-GitHubTransport {
    param([hashtable]$Request)
    Invoke-WebRequest @Request
}

function Invoke-GitHubRequest {
    param([hashtable]$Config, [ValidateSet('Get', 'Put')][string]$Method, [string]$Uri, [string]$Body)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if (Test-WorkerStopping) { throw [OperationCanceledException]::new('Worker stopping.') }
        try { $token = [IO.File]::ReadAllText($Config.GITHUB_TOKEN_FILE).Trim() }
        catch { throw 'Cannot read GITHUB_TOKEN_FILE. Mount a readable GitHub token secret and restart the worker.' }
        if ([string]::IsNullOrWhiteSpace($token) -or $token -match '\s') { throw 'GITHUB_TOKEN_FILE must contain one nonempty token.' }
        $request = @{
            Uri = $Uri; Method = $Method; TimeoutSec = 30; MaximumRedirection = 0; SkipHttpErrorCheck = $true
            Headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'vanity-metrics-filler' }
        }
        if ($Method -eq 'Put') { $request.Body = $Body; $request.ContentType = 'application/json; charset=utf-8' }
        try { $response = Invoke-GitHubTransport -Request $request }
        catch {
            # A failed PUT may already have committed. Never repeat an ambiguous write.
            if ($Method -eq 'Get' -and $attempt -lt 3) { Wait-WorkerDelay -Seconds (2 * $attempt); continue }
            throw "GitHub $Method failed due to a network error or timeout. Check connectivity; any uncertain write will not be retried."
        }
        $status = [int]$response.StatusCode
        if ($status -ge 200 -and $status -lt 300) { return ($response.Content | ConvertFrom-Json -AsHashtable) }
        if ($status -eq 409) {
            $errorRecord = [InvalidOperationException]::new('GitHub reported a write conflict.')
            $errorRecord.Data['StatusCode'] = 409
            throw $errorRecord
        }
        if ($status -eq 401) { throw 'GitHub authentication failed (401): token is invalid, expired, or revoked. Replace the token secret and recreate the container.' }
        $rateLimited = $status -eq 429 -or ($status -eq 403 -and ($response.Headers['Retry-After'] -or ($response.Headers['X-RateLimit-Remaining'] -join '') -eq '0'))
        if ($rateLimited) { throw 'GitHub rate limit reached. This tick is skipped; access will be checked again on the next scheduled tick.' }
        if ($status -eq 403) { throw 'GitHub access denied (403): check token Contents read/write permission, organization authorization, and branch rules.' }
        if ($status -eq 404) { throw 'GitHub target not found (404): check repository, branch, existing file, and token access to this repository.' }
        if ($Method -eq 'Get' -and $status -ge 500 -and $attempt -lt 3) { Wait-WorkerDelay -Seconds (2 * $attempt); continue }
        throw "GitHub $Method returned HTTP $status. This tick failed; inspect repository permissions or GitHub service status."
    }
}

function Get-GitHubContentUri {
    param([hashtable]$Config)
    $path = ($Config.GITHUB_PATH.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "https://api.github.com/repos/$($Config.GITHUB_OWNER)/$($Config.GITHUB_REPO)/contents/$path"
}

function Get-GitHubFile {
    param([hashtable]$Config)
    $uri = (Get-GitHubContentUri $Config) + '?ref=' + [Uri]::EscapeDataString($Config.GITHUB_BRANCH)
    $file = Invoke-GitHubRequest -Config $Config -Method Get -Uri $uri
    if ($file.type -ne 'file' -or $file.encoding -ne 'base64' -or -not $file.sha -or -not $file.ContainsKey('content')) {
        throw 'GitHub target must be an existing regular file smaller than 1 MB; rotate the filler log if it has grown too large.'
    }
    return $file
}

function Add-GitHubFiller {
    param([hashtable]$Config, [string]$Filler, [DateTimeOffset]$LocalTime)
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $file = Get-GitHubFile $Config
        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($file.content))
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" }
        $body = @{
            message = "chore: automated filler commit ($($LocalTime.ToString('yyyy-MM-dd HH:mm zzz')) $($Config.TIME_ZONE)) - see README, this is not real work"
            content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text + $Filler))
            sha = $file.sha; branch = $Config.GITHUB_BRANCH
        } | ConvertTo-Json -Compress
        try {
            $null = Invoke-GitHubRequest -Config $Config -Method Put -Uri (Get-GitHubContentUri $Config) -Body $body
            return
        }
        catch {
            if ($_.Exception.Data['StatusCode'] -eq 409 -and $attempt -lt 2) {
                Write-WorkerLog 'Write conflict; fetching current contents before one retry.'
                continue
            }
            throw
        }
    }
}

function Invoke-WorkerTick {
    param([hashtable]$Config, [DateTimeOffset]$UtcNow = [DateTimeOffset]::UtcNow)
    $decision = Get-CommitDecision -Config $Config -UtcNow $UtcNow
    if (-not $decision.ShouldCommit) { Write-WorkerLog "Skipped: $($decision.Reason) ($($decision.LocalTime.ToString('yyyy-MM-dd HH:mm zzz')))."; return }
    $filler = New-FillerText
    if ($Config.DRY_RUN) { Write-WorkerLog "DRY RUN: would append filler; week $($decision.Week), probability $($decision.Probability). No GitHub requests made."; return }
    Add-GitHubFiller -Config $Config -Filler $filler -LocalTime $decision.LocalTime
    Write-WorkerLog "Committed filler; week $($decision.Week), probability $($decision.Probability)."
}

Export-ModuleMember -Function Get-WorkerConfig, Get-CommitDecision, Get-NextTickUtc, New-FillerText, Write-WorkerLog, Test-WorkerStopping, Get-GitHubFile, Invoke-WorkerTick
