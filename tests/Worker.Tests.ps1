BeforeDiscovery { Import-Module "$PSScriptRoot/../src/Worker.psm1" -Force }
BeforeAll { Import-Module "$PSScriptRoot/../src/Worker.psm1" }

Describe 'Configuration' {
    It 'defaults to safe dry-run and the existing business rules' {
        $config = Get-WorkerConfig @{}
        $config.DRY_RUN | Should -BeTrue
        $config.TIME_ZONE | Should -Be 'Australia/Sydney'
        $config.COMMIT_PROBABILITY | Should -Be 0.4
    }
    It 'rejects invalid <Name>' -TestCases @(
        @{ Name = 'COMMIT_PROBABILITY'; Value = 'NaN' }
        @{ Name = 'COMMIT_PROBABILITY'; Value = '1.1' }
        @{ Name = 'COMMIT_PROBABILITY'; Value = '0,4' }
        @{ Name = 'BUSY_WEEK_MULTIPLIER'; Value = '-1' }
        @{ Name = 'BUSY_WEEK_MODULO'; Value = '0' }
        @{ Name = 'BUSY_WEEK_REMAINDER'; Value = '2' }
        @{ Name = 'QUIET_WEEK_REMAINDER'; Value = '4' }
        @{ Name = 'INTERVAL_MINUTES'; Value = '0' }
        @{ Name = 'INTERVAL_MINUTES'; Value = '7' }
        @{ Name = 'WORK_START_HOUR'; Value = '17' }
        @{ Name = 'WORK_END_HOUR'; Value = '25' }
        @{ Name = 'DRY_RUN'; Value = 'yes' }
        @{ Name = 'GITHUB_REPO'; Value = '' }
        @{ Name = 'GITHUB_PATH'; Value = '../log.md' }
        @{ Name = 'TIME_ZONE'; Value = 'Not/AZone' }
    ) {
        param($Name, $Value)
        { Get-WorkerConfig @{ $Name = $Value } } | Should -Throw '*Configuration:*'
    }
    It 'parses decimal settings independently of the host locale' {
        $oldCulture = [Globalization.CultureInfo]::CurrentCulture
        try {
            [Globalization.CultureInfo]::CurrentCulture = 'de-DE'
            (Get-WorkerConfig @{ COMMIT_PROBABILITY = '0.25' }).COMMIT_PROBABILITY | Should -Be 0.25
        }
        finally { [Globalization.CultureInfo]::CurrentCulture = $oldCulture }
    }
}

Describe 'Local-time scheduling and probability' {
    BeforeAll { $config = Get-WorkerConfig @{} }
    It 'includes Sydney Monday morning when UTC is still Sunday (<Utc>)' -TestCases @(
        @{ Utc = '2026-07-05T23:00:00Z'; Offset = 10 }
        @{ Utc = '2026-01-04T22:00:00Z'; Offset = 11 }
        @{ Utc = '2026-10-04T22:00:00Z'; Offset = 11 }
    ) {
        param($Utc, $Offset)
        $decision = Get-CommitDecision $config ([DateTimeOffset]$Utc) 0
        $decision.ShouldCommit | Should -BeTrue
        $decision.LocalTime.Hour | Should -Be 9
        $decision.LocalTime.Offset.TotalHours | Should -Be $Offset
    }
    It 'skips outside local working hours (<Utc>)' -TestCases @(
        @{ Utc = '2026-07-05T22:59:00Z' }
        @{ Utc = '2026-07-06T07:00:00Z' }
        @{ Utc = '2026-09-04T23:00:00Z' }
        @{ Utc = '2026-09-05T23:00:00Z' }
    ) {
        param($Utc)
        (Get-CommitDecision $config ([DateTimeOffset]$Utc) 0).ShouldCommit | Should -BeFalse
    }
    It 'preserves busy, quiet, and normal weeks (<Utc>)' -TestCases @(
        @{ Utc = '2026-01-18T22:00:00Z'; Probability = 1.0 }
        @{ Utc = '2026-01-04T22:00:00Z'; Probability = 0.16 }
        @{ Utc = '2026-01-11T22:00:00Z'; Probability = 0.4 }
    ) {
        param($Utc, $Probability)
        $decision = Get-CommitDecision $config ([DateTimeOffset]$Utc) 0
        [Math]::Round($decision.Probability, 2) | Should -Be $Probability
    }
    It 'uses an exclusive probability threshold' {
        (Get-CommitDecision $config ([DateTimeOffset]'2026-01-11T22:00:00Z') 0.4).ShouldCommit | Should -BeFalse
        (Get-CommitDecision $config ([DateTimeOffset]'2026-01-11T22:00:00Z') 0.399).ShouldCommit | Should -BeTrue
    }
    It 'never commits with zero probability, even with a zero roll' {
        $zero = Get-WorkerConfig @{ COMMIT_PROBABILITY = '0' }
        (Get-CommitDecision $zero ([DateTimeOffset]'2026-01-11T22:00:00Z') 0).ShouldCommit | Should -BeFalse
    }
    It 'caps a multiplied probability at one' {
        $high = Get-WorkerConfig @{ BUSY_WEEK_MULTIPLIER = '100' }
        (Get-CommitDecision $high ([DateTimeOffset]'2026-01-18T22:00:00Z') 0.999).Probability | Should -Be 1
    }
    It 'uses strictly future boundaries and skips missed intervals (<Utc>)' -TestCases @(
        @{ Utc = '2026-09-29T00:00:00Z'; Expected = '2026-09-29T00:30:00Z' }
        @{ Utc = '2026-09-29T00:29:59Z'; Expected = '2026-09-29T00:30:00Z' }
        @{ Utc = '2026-09-29T23:59:59Z'; Expected = '2026-09-30T00:00:00Z' }
    ) {
        param($Utc, $Expected)
        (Get-NextTickUtc ([DateTimeOffset]$Utc) 30) | Should -Be ([DateTimeOffset]$Expected)
    }
}

Describe 'Filler generation' {
    It 'produces one to three sentences of six to fifteen words and a blank line' {
        1..20 | ForEach-Object {
            $text = New-FillerText
            $text | Should -Match '\.\n\n$'
            $sentences = @($text.Trim().Split('.') | Where-Object { $_.Trim() })
            $sentences.Count | Should -BeIn (1..3)
            foreach ($sentence in $sentences) {
                $sentence.Trim() | Should -Match '^[A-Z][a-z ]+$'
                $sentence.Trim().Split(' ').Count | Should -BeIn (6..15)
            }
        }
    }
}

Describe 'GitHub access and safe retries' {
    InModuleScope Worker {
        BeforeEach {
            $script:tokenPath = [IO.Path]::GetTempFileName()
            [IO.File]::WriteAllText($script:tokenPath, 'test-token-never-log')
            $script:config = Get-WorkerConfig @{ GITHUB_TOKEN_FILE = $script:tokenPath; DRY_RUN = 'false' }
            $script:requests = [Collections.Generic.List[hashtable]]::new()
            Mock Wait-WorkerDelay {}
        }
        AfterEach { Remove-Item -LiteralPath $script:tokenPath -Force }

        It 'encodes branch and path segments separately' {
            $config.GITHUB_BRANCH = 'test/docker'
            $config.GITHUB_PATH = 'logs/filler notes.md'
            Mock Invoke-GitHubTransport {
                param($Request)
                $script:requests.Add($Request)
                @{ StatusCode = 200; Content = '{"type":"file","encoding":"base64","sha":"a","content":""}' }
            }
            $null = Get-GitHubFile $config
            $requests[0].Uri | Should -Be 'https://api.github.com/repos/HPyn/vanity-metrics/contents/logs/filler%20notes.md?ref=test%2Fdocker'
            $requests[0].MaximumRedirection | Should -Be 0
        }
        It 'reports expired tokens without exposing credentials or response bodies' {
            Mock Invoke-GitHubTransport { @{ StatusCode = 401; Content = 'sensitive response test-token-never-log'; Headers = @{} } }
            { Get-GitHubFile $config } | Should -Throw '*expired*'
            try { Get-GitHubFile $config } catch { $_.Exception.Message | Should -Not -Match 'test-token-never-log|sensitive response' }
        }
        It 'reports permission errors separately from rate limits' {
            Mock Invoke-GitHubTransport { @{ StatusCode = 403; Content = ''; Headers = @{} } }
            { Get-GitHubFile $config } | Should -Throw '*Contents read/write*'
        }
        It 'defers rate-limited requests until another scheduled tick' {
            Mock Invoke-GitHubTransport { @{ StatusCode = 403; Content = ''; Headers = @{ 'X-RateLimit-Remaining' = @('0') } } }
            { Get-GitHubFile $config } | Should -Throw '*rate limit*'
            Should -Invoke Invoke-GitHubTransport -Times 1 -Exactly
        }
        It 'identifies missing targets' {
            Mock Invoke-GitHubTransport { @{ StatusCode = 404; Content = ''; Headers = @{} } }
            { Get-GitHubFile $config } | Should -Throw '*target not found*'
        }
        It 'rejects a file above the contents API inline limit' {
            Mock Invoke-GitHubTransport { @{ StatusCode = 200; Content = '{"type":"file","encoding":"none","sha":"a","content":""}' } }
            { Get-GitHubFile $config } | Should -Throw '*smaller than 1 MB*'
        }
        It 'retries transient reads a bounded number of times' {
            Mock Invoke-GitHubTransport { @{ StatusCode = 503; Content = ''; Headers = @{} } }
            { Get-GitHubFile $config } | Should -Throw '*503*'
            Should -Invoke Invoke-GitHubTransport -Times 3 -Exactly
            Should -Invoke Wait-WorkerDelay -Times 2 -Exactly
        }
        It 'does not retry an ambiguous write after a timeout' {
            Mock Invoke-GitHubTransport { throw 'timeout containing test-token-never-log' }
            { Invoke-GitHubRequest $config Put 'https://api.github.com/example' '{}' } | Should -Throw '*uncertain write will not be retried*'
            Should -Invoke Invoke-GitHubTransport -Times 1 -Exactly
        }
        It 'refetches a conflict and preserves concurrent UTF-8 content' {
            Mock Invoke-GitHubTransport {
                param($Request)
                $script:requests.Add($Request)
                switch ($script:requests.Count) {
                    1 { @{ StatusCode = 200; Content = (@{ type = 'file'; encoding = 'base64'; sha = 'old'; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("Original`n")) } | ConvertTo-Json) } }
                    2 { @{ StatusCode = 409; Content = ''; Headers = @{} } }
                    3 { @{ StatusCode = 200; Content = (@{ type = 'file'; encoding = 'base64'; sha = 'new'; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("Original`nConcurrent café")) } | ConvertTo-Json) } }
                    4 { @{ StatusCode = 200; Content = '{}' } }
                    default { throw 'Too many requests.' }
                }
            }
            Add-GitHubFiller $config "Filler.`n`n" ([DateTimeOffset]'2026-09-29T09:00:00+10:00')
            $requests.Count | Should -Be 4
            $body = $requests[3].Body | ConvertFrom-Json
            $body.sha | Should -Be 'new'
            $body.branch | Should -Be 'main'
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body.content)) | Should -Be "Original`nConcurrent café`nFiller.`n`n"
            $body.message | Should -Match 'automated filler commit.*not real work'
        }
        It 'stops retrying repeated conflicts' {
            Mock Get-GitHubFile { @{ content = ''; sha = 'a' } }
            Mock Invoke-GitHubTransport { @{ StatusCode = 409; Content = ''; Headers = @{} } }
            { Add-GitHubFiller $config 'text' ([DateTimeOffset]::UtcNow) } | Should -Throw '*conflict*'
            Should -Invoke Invoke-GitHubTransport -Times 2 -Exactly
        }
        It 'makes no GitHub calls in dry-run even when a commit is selected' {
            $config.DRY_RUN = $true
            Mock Get-CommitDecision { @{ ShouldCommit = $true; Week = 4; Probability = 1 } }
            Mock Invoke-GitHubTransport { throw 'Dry-run must not access GitHub.' }
            Invoke-WorkerTick $config
            Should -Invoke Invoke-GitHubTransport -Times 0 -Exactly
        }
    }
}
