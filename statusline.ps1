# Read input from stdin
$input = @($Input) -join "`n"

if (-not $input) {
    [Console]::Out.Write("Claude")
    exit 0
}

$esc = [char]0x1b

# ANSI palette tuned for dim terminal chrome with one strong accent.
$accent = "${esc}[38;2;77;166;255m"
$teal   = "${esc}[38;2;77;175;176m"
$branch = "${esc}[38;2;196;208;212m"
$red    = "${esc}[38;2;255;85;85m"
$orange = "${esc}[38;2;255;176;85m"
$yellow = "${esc}[38;2;230;200;0m"
$green  = "${esc}[38;2;0;160;0m"
$white  = "${esc}[38;2;228;232;234m"
$dim    = "${esc}[2m"
$reset  = "${esc}[0m"

$sepPlain = " | "
$sepText = " ${dim}|${reset} "

function New-Segment([string]$text, [string]$plain) {
    return [pscustomobject]@{
        Text = $text
        Plain = $plain
    }
}

function Format-Tokens([long]$num) {
    if ($num -ge 1000000) { return "{0:F1}m" -f ($num / 1000000) }
    if ($num -ge 1000) { return "{0:F0}k" -f ($num / 1000) }
    return "$num"
}

function Get-UsageColor([int]$pct) {
    if ($pct -ge 90) { return $red }
    if ($pct -ge 70) { return $orange }
    if ($pct -ge 50) { return $yellow }
    return $green
}

function Get-MaxWidth {
    if ($env:CLAUDE_CODE_STATUSLINE_MAX_WIDTH -match '^[1-9]\d*$') {
        return [int]$env:CLAUDE_CODE_STATUSLINE_MAX_WIDTH
    }
    if ($env:COLUMNS -match '^[1-9]\d*$') {
        return [int]$env:COLUMNS
    }
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 0) {
            return [int]$Host.UI.RawUI.WindowSize.Width
        }
    } catch {}
    return 100
}

function Truncate-Middle([string]$value, [int]$limit) {
    if ($value.Length -le $limit) { return $value }
    if ($limit -le 3) { return "..." }

    $leftKeep = [math]::Floor(($limit - 3) / 2)
    $rightKeep = $limit - 3 - $leftKeep
    return $value.Substring(0, $leftKeep) + "..." + $value.Substring($value.Length - $rightKeep)
}

function Get-OAuthToken {
    if ($env:CLAUDE_CODE_OAUTH_TOKEN) {
        return $env:CLAUDE_CODE_OAUTH_TOKEN
    }

    $credPath = Join-Path $env:LOCALAPPDATA "Claude Code\credentials.json"
    if ($env:LOCALAPPDATA -and (Test-Path $credPath)) {
        try {
            $creds = Get-Content $credPath -Raw | ConvertFrom-Json
            $token = $creds.claudeAiOauth.accessToken
            if ($token -and $token -ne "null") { return $token }
        } catch {}
    }

    $credsFile = Join-Path $env:USERPROFILE ".claude\.credentials.json"
    if (Test-Path $credsFile) {
        try {
            $creds = Get-Content $credsFile -Raw | ConvertFrom-Json
            $token = $creds.claudeAiOauth.accessToken
            if ($token -and $token -ne "null") { return $token }
        } catch {}
    }

    return $null
}

function Format-ResetTime([string]$isoStr, [string]$style) {
    if (-not $isoStr -or $isoStr -eq "null") { return $null }
    try {
        $dt = [DateTimeOffset]::Parse($isoStr).LocalDateTime
        switch ($style) {
            "time"     { return $dt.ToString("h:mm") }
            "datetime" { return $dt.ToString("MMM d h:mm") }
            default    { return $dt.ToString("MMM d") }
        }
    } catch {
        return $null
    }
}

function Get-GitStat([string]$repoPath) {
    $lines = @()
    try { $lines += @(git -C $repoPath diff --numstat 2>$null) } catch {}
    try { $lines += @(git -C $repoPath diff --cached --numstat 2>$null) } catch {}

    $added = 0
    $deleted = 0
    foreach ($line in $lines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 2) { continue }
        if ($parts[0] -match '^\d+$') { $added += [int]$parts[0] }
        if ($parts[1] -match '^\d+$') { $deleted += [int]$parts[1] }
    }

    if (($added + $deleted) -gt 0) {
        return "+$added -$deleted"
    }
    return $null
}

function Build-ModelSegment {
    return New-Segment "${accent}${script:modelName}${reset}" $script:modelName
}

function Build-GitSegment {
    if (-not $script:cwd) { return $null }

    $basePlain = $script:displayDir
    if ($script:gitBranch) {
        $basePlain = "$($script:displayDir)@$($script:gitBranch)"
    }
    if ($script:showGitDiff -and $script:gitStat) {
        $basePlain = "$basePlain ($($script:gitStat))"
    }

    if ($script:gitTruncateWidth -gt 0 -and $basePlain.Length -gt $script:gitTruncateWidth) {
        $truncated = Truncate-Middle $basePlain $script:gitTruncateWidth
        return New-Segment "${teal}${truncated}${reset}" $truncated
    }

    $text = "${teal}$($script:displayDir)${reset}"
    if ($script:gitBranch) {
        $text += "${dim}@${reset}${branch}$($script:gitBranch)${reset}"
    }
    if ($script:showGitDiff -and $script:gitStat) {
        $parts = $script:gitStat -split ' '
        $text += " ${dim}(${reset}${green}$($parts[0])${reset} ${red}$($parts[1])${reset}${dim})${reset}"
    }

    return New-Segment $text $basePlain
}

function Build-CtxSegment {
    $pctColor = Get-UsageColor $script:pctUsed
    $plain = "ctx $($script:usedTokens)/$($script:totalTokens) $($script:pctUsed)%"
    $text = "${dim}ctx${reset} ${white}$($script:usedTokens)/$($script:totalTokens)${reset} ${pctColor}$($script:pctUsed)%${reset}"
    return New-Segment $text $plain
}

function Build-EffSegment {
    switch ($script:effortLevel) {
        "low" {
            $plain = "eff low"
            $valueText = "${branch}low${reset}"
        }
        "medium" {
            $plain = "eff med"
            $valueText = "${yellow}med${reset}"
        }
        default {
            $plain = "eff high"
            $valueText = "${orange}high${reset}"
        }
    }
    return New-Segment "${dim}eff${reset} $valueText" $plain
}

function Build-FiveHourSegment {
    if (-not $script:usageAvailable) {
        return New-Segment "${dim}5h${reset} ${dim}-${reset}" "5h -"
    }

    $pctColor = Get-UsageColor $script:fiveHourPct
    $plain = "5h $($script:fiveHourPct)%"
    $text = "${dim}5h${reset} ${pctColor}$($script:fiveHourPct)%${reset}"
    if ($script:showFiveHourReset -and $script:fiveHourReset) {
        $plain += " $($script:fiveHourReset)"
        $text += " ${dim}$($script:fiveHourReset)${reset}"
    }
    return New-Segment $text $plain
}

function Build-SevenDaySegment {
    if (-not $script:usageAvailable) {
        return New-Segment "${dim}7d${reset} ${dim}-${reset}" "7d -"
    }

    $pctColor = Get-UsageColor $script:sevenDayPct
    $plain = "7d $($script:sevenDayPct)%"
    $text = "${dim}7d${reset} ${pctColor}$($script:sevenDayPct)%${reset}"
    if ($script:showSevenDayReset -and $script:sevenDayReset) {
        $plain += " $($script:sevenDayReset)"
        $text += " ${dim}$($script:sevenDayReset)${reset}"
    }
    return New-Segment $text $plain
}

function Build-ExtraSegment {
    if ($script:extraEnabled -ne $true) { return $null }

    if ($script:extraUsed -and $script:extraLimit) {
        $plain = "extra `$$($script:extraUsed)/`$$($script:extraLimit)"
        $text = "${dim}extra${reset} ${white}`$$($script:extraUsed)/`$$($script:extraLimit)${reset}"
        return New-Segment $text $plain
    }

    return New-Segment "${dim}extra${reset} ${branch}enabled${reset}" "extra enabled"
}

function Compose-Output {
    $segments = [System.Collections.Generic.List[object]]::new()
    $script:gitSegmentLen = 0

    $segments.Add((Build-ModelSegment))

    $gitSegment = Build-GitSegment
    if ($gitSegment) {
        $script:gitSegmentLen = $gitSegment.Plain.Length
        $segments.Add($gitSegment)
    }

    $segments.Add((Build-CtxSegment))
    $segments.Add((Build-EffSegment))
    $segments.Add((Build-FiveHourSegment))

    if ($script:showSevenDay) {
        $segments.Add((Build-SevenDaySegment))
    }

    if ($script:showExtra) {
        $extraSegment = Build-ExtraSegment
        if ($extraSegment) {
            $segments.Add($extraSegment)
        }
    }

    $plainParts = @()
    $textParts = @()
    foreach ($segment in $segments) {
        $plainParts += $segment.Plain
        $textParts += $segment.Text
    }

    $plain = $plainParts -join $sepPlain
    $text = $textParts -join $sepText

    return [pscustomobject]@{
        Plain = $plain
        Text = $text
        Length = $plain.Length
    }
}

$data = $input | ConvertFrom-Json

$modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
$size = if ($data.context_window.context_window_size) { [long]$data.context_window.context_window_size } else { 200000 }
if ($size -eq 0) { $size = 200000 }

$inputTokens = if ($data.context_window.current_usage.input_tokens) { [long]$data.context_window.current_usage.input_tokens } else { 0 }
$cacheCreate = if ($data.context_window.current_usage.cache_creation_input_tokens) { [long]$data.context_window.current_usage.cache_creation_input_tokens } else { 0 }
$cacheRead = if ($data.context_window.current_usage.cache_read_input_tokens) { [long]$data.context_window.current_usage.cache_read_input_tokens } else { 0 }
$current = $inputTokens + $cacheCreate + $cacheRead

$usedTokens = Format-Tokens $current
$totalTokens = Format-Tokens $size
$pctUsed = if ($size -gt 0) { [math]::Floor($current * 100 / $size) } else { 0 }

$effortLevel = if ($env:CLAUDE_CODE_EFFORT_LEVEL) { $env:CLAUDE_CODE_EFFORT_LEVEL } else { "medium" }
if (-not $env:CLAUDE_CODE_EFFORT_LEVEL) {
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($settings.effortLevel) { $effortLevel = $settings.effortLevel }
        } catch {}
    }
}

$cwd = $data.cwd
$displayDir = $null
$gitBranch = $null
$gitStat = $null
if ($cwd) {
    $displayDir = Split-Path $cwd -Leaf
    try { $gitBranch = git -C $cwd rev-parse --abbrev-ref HEAD 2>$null } catch {}
    $gitStat = Get-GitStat $cwd
}

$cacheDir = Join-Path $env:TEMP "claude"
$cacheFile = Join-Path $cacheDir "statusline-usage-cache.json"
$cacheMaxAge = 60
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

$needsRefresh = $true
$usageData = $null
if (Test-Path $cacheFile) {
    $cacheAge = ((Get-Date) - (Get-Item $cacheFile).LastWriteTime).TotalSeconds
    if ($cacheAge -lt $cacheMaxAge) {
        $needsRefresh = $false
    }
    $usageData = Get-Content $cacheFile -Raw
}

if ($needsRefresh) {
    $token = Get-OAuthToken
    if ($token) {
        try {
            $headers = @{
                "Accept" = "application/json"
                "Content-Type" = "application/json"
                "Authorization" = "Bearer $token"
                "anthropic-beta" = "oauth-2025-04-20"
                "User-Agent" = "claude-code/2.1.34"
            }
            $response = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" -Headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop
            $usageData = $response | ConvertTo-Json -Depth 10
            $usageData | Set-Content $cacheFile -Force
        } catch {}
    }
    if (-not $usageData -and (Test-Path $cacheFile)) {
        $usageData = Get-Content $cacheFile -Raw
    }
}

$usageAvailable = $false
$showSevenDay = $true
$showExtra = $false
$showFiveHourReset = $false
$showSevenDayReset = $false
$showGitDiff = [bool]$gitStat
$gitTruncateWidth = 0

$fiveHourPct = 0
$fiveHourReset = $null
$sevenDayPct = 0
$sevenDayReset = $null
$extraEnabled = $false
$extraUsed = $null
$extraLimit = $null

if ($usageData) {
    try {
        $usage = if ($usageData -is [string]) { $usageData | ConvertFrom-Json } else { $usageData }
        if ($usage.five_hour) {
            $usageAvailable = $true
            $fiveHourPct = [math]::Floor([double]$usage.five_hour.utilization)
            $fiveHourReset = Format-ResetTime $usage.five_hour.resets_at "time"
            $showFiveHourReset = [bool]$fiveHourReset

            $sevenDayPct = [math]::Floor([double]$usage.seven_day.utilization)
            $sevenDayReset = Format-ResetTime $usage.seven_day.resets_at "datetime"
            $showSevenDayReset = [bool]$sevenDayReset

            $extraEnabled = ($usage.extra_usage.is_enabled -eq $true)
            if ($extraEnabled) {
                $extraUsed = "{0:F2}" -f ([double]$usage.extra_usage.used_credits / 100)
                $extraLimit = "{0:F2}" -f ([double]$usage.extra_usage.monthly_limit / 100)
                $showExtra = $true
            }
        }
    } catch {}
}

$maxWidth = Get-MaxWidth
$composed = Compose-Output

if ($composed.Length -gt $maxWidth -and $showExtra) {
    $showExtra = $false
    $composed = Compose-Output
}

if ($composed.Length -gt $maxWidth -and $showSevenDayReset) {
    $showSevenDayReset = $false
    $composed = Compose-Output
}

if ($composed.Length -gt $maxWidth -and $showFiveHourReset) {
    $showFiveHourReset = $false
    $composed = Compose-Output
}

if ($composed.Length -gt $maxWidth -and $showGitDiff) {
    $showGitDiff = $false
    $composed = Compose-Output
}

if ($composed.Length -gt $maxWidth -and $showSevenDay) {
    $showSevenDay = $false
    $composed = Compose-Output
}

if ($composed.Length -gt $maxWidth -and $gitSegmentLen -gt 0) {
    $availableForGit = $maxWidth - ($composed.Length - $gitSegmentLen)
    if ($availableForGit -lt 3) { $availableForGit = 3 }
    $gitTruncateWidth = $availableForGit
    $composed = Compose-Output
}

[Console]::Out.Write($composed.Text)
