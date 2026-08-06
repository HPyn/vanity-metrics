param($Timer)

# Writes a Lorem Ipsum paragraph into log.md on GitHub, roughly during
# Sydney/Melbourne business hours on weekdays. See ../../README.md.
#
# "Busy" weeks: some weeks of the year should look busier than others
# rather than a flat, uniform commit rate. Which weeks are busy/quiet is
# driven by ISO week-of-year modulo BUSY_WEEK_MODULO, so the pattern
# repeats every BUSY_WEEK_MODULO weeks all year.

function Get-SydneyNow {
    $utcNow = [DateTime]::UtcNow
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('AUS Eastern Standard Time')
    return [System.TimeZoneInfo]::ConvertTimeFromUtc($utcNow, $tz)
}

$now = Get-SydneyNow

$isWeekday = $now.DayOfWeek -ge [DayOfWeek]::Monday -and $now.DayOfWeek -le [DayOfWeek]::Friday
$workStartHour = [int]($env:WORK_START_HOUR ?? '9')
$workEndHour = [int]($env:WORK_END_HOUR ?? '17')
$inWorkingHours = $now.Hour -ge $workStartHour -and $now.Hour -lt $workEndHour

if (-not ($isWeekday -and $inWorkingHours)) {
    Write-Information "Outside business hours ($($now.ToString('yyyy-MM-dd HH:mm')) Sydney) - skipping."
    return
}

$baseProbability = [double]($env:COMMIT_PROBABILITY ?? '0.4')

$weekOfYear = [System.Globalization.ISOWeek]::GetWeekOfYear($now)
$busyModulo = [int]($env:BUSY_WEEK_MODULO ?? '4')
$busyRemainder = [int]($env:BUSY_WEEK_REMAINDER ?? '0')
$busyMultiplier = [double]($env:BUSY_WEEK_MULTIPLIER ?? '2.5')
$quietRemainder = [int]($env:QUIET_WEEK_REMAINDER ?? '2')
$quietMultiplier = [double]($env:QUIET_WEEK_MULTIPLIER ?? '0.4')

$weekMod = $weekOfYear % $busyModulo
$multiplier = 1.0
if ($weekMod -eq $busyRemainder) {
    $multiplier = $busyMultiplier
}
elseif ($weekMod -eq $quietRemainder) {
    $multiplier = $quietMultiplier
}

$effectiveProbability = [Math]::Min(1.0, $baseProbability * $multiplier)

$roll = Get-Random -Minimum 0.0 -Maximum 1.0
if ($roll -ge $effectiveProbability) {
    Write-Information "Rolled $([Math]::Round($roll,3)) >= $([Math]::Round($effectiveProbability,3)) (week $weekOfYear, x$multiplier) - no commit this tick."
    return
}

$loremWords = @(
    'lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur', 'adipiscing', 'elit', 'sed', 'do',
    'eiusmod', 'tempor', 'incididunt', 'ut', 'labore', 'et', 'dolore', 'magna', 'aliqua', 'enim',
    'ad', 'minim', 'veniam', 'quis', 'nostrud', 'exercitation', 'ullamco', 'laboris', 'nisi',
    'aliquip', 'ex', 'ea', 'commodo', 'consequat', 'duis', 'aute', 'irure', 'in', 'reprehenderit',
    'voluptate', 'velit', 'esse', 'cillum', 'fugiat', 'nulla', 'pariatur', 'excepteur', 'sint',
    'occaecat', 'cupidatat', 'non', 'proident', 'sunt', 'culpa', 'qui', 'officia', 'deserunt',
    'mollit', 'anim', 'id', 'est', 'laborum'
)

$sentenceCount = Get-Random -Minimum 1 -Maximum 4
$sentences = for ($i = 0; $i -lt $sentenceCount; $i++) {
    $wordCount = Get-Random -Minimum 6 -Maximum 16
    $sentenceWords = 1..$wordCount | ForEach-Object { Get-Random -InputObject $loremWords }
    $sentence = $sentenceWords -join ' '
    "$($sentence.Substring(0, 1).ToUpper())$($sentence.Substring(1))."
}
$filler = ($sentences -join ' ') + "`n`n"

$owner = $env:GITHUB_OWNER
$repo = $env:GITHUB_REPO
$path = $env:GITHUB_PATH
$branch = $env:GITHUB_BRANCH ?? 'main'
$headers = @{
    Authorization = "Bearer $env:GITHUB_TOKEN"
    Accept        = 'application/vnd.github+json'
    'User-Agent'  = 'vanity-metrics-filler'
}

$existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/$path`?ref=$branch" -Headers $headers -Method Get

$currentContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($existing.content))
$newContent = $currentContent + $filler
$newContentBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($newContent))

$commitMessage = "chore: automated filler commit ($($now.ToString('yyyy-MM-dd HH:mm')) (Sydney local time)) - see README, this is not real work"

$putBody = @{
    message = $commitMessage
    content = $newContentBase64
    sha     = $existing.sha
    branch  = $branch
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/$path" -Headers $headers -Method Put -Body $putBody -ContentType 'application/json' | Out-Null

Write-Information "Committed filler text - week $weekOfYear, multiplier x$multiplier, effective probability $([Math]::Round($effectiveProbability, 3))."
