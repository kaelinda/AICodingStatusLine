# Read input from stdin
$input = @($Input) -join "`n"

if (-not $input) {
    [Console]::Out.Write("Claude")
    exit 0
}

$esc = [char]0x1b

if ($env:USERPROFILE) {
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
} else {
    $settingsPath = Join-Path $HOME ".claude\settings.json"
}

$script:claudeSettings = $null
if (Test-Path $settingsPath) {
    try {
        $script:claudeSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } catch {}
}

function Get-SettingsEnvValue([string]$name) {
    if (-not $script:claudeSettings -or -not $script:claudeSettings.env) {
        return $null
    }

    $property = $script:claudeSettings.env.PSObject.Properties[$name]
    if ($property -and $null -ne $property.Value -and "$($property.Value)") {
        return [string]$property.Value
    }

    return $null
}

function Resolve-StatuslineSetting([string[]]$names, [string]$defaultValue) {
    foreach ($name in $names) {
        $envValue = [Environment]::GetEnvironmentVariable($name)
        if ($envValue) {
            return $envValue
        }
    }

    foreach ($name in $names) {
        $settingsValue = Get-SettingsEnvValue $name
        if ($settingsValue) {
            return $settingsValue
        }
    }

    return $defaultValue
}

function Resolve-BoolStatuslineSetting([string[]]$names, [bool]$defaultValue) {
    $requested = Resolve-StatuslineSetting $names ""
    if (-not $requested) {
        return $defaultValue
    }

    switch ($requested.ToLowerInvariant()) {
        "1" { return $true }
        "true" { return $true }
        "yes" { return $true }
        "on" { return $true }
        "0" { return $false }
        "false" { return $false }
        "no" { return $false }
        "off" { return $false }
        default { return $defaultValue }
    }
}

$themeName = Resolve-StatuslineSetting @("STATUSLINE_THEME", "CLAUDE_CODE_STATUSLINE_THEME") "default"
$layoutName = Resolve-StatuslineSetting @("STATUSLINE_MODE", "CLAUDE_CODE_STATUSLINE_LAYOUT") "compact"
$barStyleName = Resolve-StatuslineSetting @("STATUSLINE_BAR_STYLE", "CLAUDE_CODE_STATUSLINE_BAR_STYLE") "ascii"
$script:configuredMaxWidth = Resolve-StatuslineSetting @("STATUSLINE_MAX_WIDTH", "CLAUDE_CODE_STATUSLINE_MAX_WIDTH") ""
$script:sevenDayTimeSetting = Resolve-StatuslineSetting @("STATUSLINE_DAILY_TIME_FORMAT", "STATUSLINE_SEVEN_DAY_TIME_FORMAT", "CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT") ""
$script:showBarsGitLine = Resolve-BoolStatuslineSetting @("STATUSLINE_SHOW_GIT_LINE", "CLAUDE_CODE_STATUSLINE_SHOW_GIT_LINE") $true
$script:showBarsOverviewLine = Resolve-BoolStatuslineSetting @("STATUSLINE_SHOW_OVERVIEW_LINE", "CLAUDE_CODE_STATUSLINE_SHOW_OVERVIEW_LINE") $true
$script:showHourlyBar = Resolve-BoolStatuslineSetting @("STATUSLINE_SHOW_HOURLY_BAR", "CLAUDE_CODE_STATUSLINE_SHOW_HOURLY_BAR") $true
$script:showDailyBar = Resolve-BoolStatuslineSetting @("STATUSLINE_SHOW_DAILY_BAR", "CLAUDE_CODE_STATUSLINE_SHOW_DAILY_BAR") $true
if ($layoutName -notin @("compact", "bars")) { $layoutName = "compact" }
switch -Wildcard ($barStyleName) {
    "dots" {
        $barFilledChar = [string][char]0x25CF
        $barEmptyChar = [string][char]0x25CB
    }
    "squares" {
        $barFilledChar = [string][char]0x25A0
        $barEmptyChar = [string][char]0x25A1
    }
    "blocks" {
        $barFilledChar = [string][char]0x2588
        $barEmptyChar = [string][char]0x2591
    }
    "braille" {
        $barFilledChar = [string][char]0x28FF
        $barEmptyChar = [string][char]0x2880
    }
    "shades" {
        $barFilledChar = [string][char]0x2593
        $barEmptyChar = [string][char]0x2591
    }
    "diamonds" {
        $barFilledChar = [string][char]0x25C6
        $barEmptyChar = [string][char]0x25C7
    }
    "custom:*" {
        $parts = $barStyleName -split ':', 3
        $barFilledChar = if ($parts.Length -ge 2 -and $parts[1]) { $parts[1] } else { "=" }
        $barEmptyChar = if ($parts.Length -ge 3 -and $parts[2]) { $parts[2] } else { "-" }
    }
    default {
        $barStyleName = "ascii"
        $barFilledChar = "="
        $barEmptyChar = "-"
    }
}

# ANSI palette tuned for dim terminal chrome with one strong accent.
switch ($themeName) {
    "forest" {
        $accent = "${esc}[38;2;120;196;120m"
        $teal   = "${esc}[38;2;94;170;150m"
        $branch = "${esc}[38;2;214;224;205m"
        $muted  = "${esc}[38;2;132;144;124m"
        $red    = "${esc}[38;2;224;108;117m"
        $orange = "${esc}[38;2;214;170;84m"
        $yellow = "${esc}[38;2;198;183;101m"
        $green  = "${esc}[38;2;120;196;120m"
        $white  = "${esc}[38;2;234;238;228m"
    }
    "dracula" {
        $accent = "${esc}[38;2;189;147;249m"
        $teal   = "${esc}[38;2;139;233;253m"
        $branch = "${esc}[38;2;248;248;242m"
        $muted  = "${esc}[38;2;98;114;164m"
        $red    = "${esc}[38;2;255;85;85m"
        $orange = "${esc}[38;2;255;184;108m"
        $yellow = "${esc}[38;2;241;250;140m"
        $green  = "${esc}[38;2;80;250;123m"
        $white  = "${esc}[38;2;248;248;242m"
    }
    "monokai" {
        $accent = "${esc}[38;2;102;217;239m"
        $teal   = "${esc}[38;2;166;226;46m"
        $branch = "${esc}[38;2;230;219;116m"
        $muted  = "${esc}[38;2;117;113;94m"
        $red    = "${esc}[38;2;249;38;114m"
        $orange = "${esc}[38;2;253;151;31m"
        $yellow = "${esc}[38;2;230;219;116m"
        $green  = "${esc}[38;2;166;226;46m"
        $white  = "${esc}[38;2;248;248;242m"
    }
    "solarized" {
        $accent = "${esc}[38;2;38;139;210m"
        $teal   = "${esc}[38;2;42;161;152m"
        $branch = "${esc}[38;2;147;161;161m"
        $muted  = "${esc}[38;2;88;110;117m"
        $red    = "${esc}[38;2;220;50;47m"
        $orange = "${esc}[38;2;203;75;22m"
        $yellow = "${esc}[38;2;181;137;0m"
        $green  = "${esc}[38;2;133;153;0m"
        $white  = "${esc}[38;2;238;232;213m"
    }
    "ocean" {
        $accent = "${esc}[38;2;0;188;212m"
        $teal   = "${esc}[38;2;0;151;167m"
        $branch = "${esc}[38;2;178;235;242m"
        $muted  = "${esc}[38;2;120;144;156m"
        $red    = "${esc}[38;2;239;83;80m"
        $orange = "${esc}[38;2;255;152;0m"
        $yellow = "${esc}[38;2;255;213;79m"
        $green  = "${esc}[38;2;102;187;106m"
        $white  = "${esc}[38;2;224;247;250m"
    }
    "sunset" {
        $accent = "${esc}[38;2;255;138;101m"
        $teal   = "${esc}[38;2;255;183;77m"
        $branch = "${esc}[38;2;255;204;128m"
        $muted  = "${esc}[38;2;161;136;127m"
        $red    = "${esc}[38;2;239;83;80m"
        $orange = "${esc}[38;2;255;112;66m"
        $yellow = "${esc}[38;2;255;213;79m"
        $green  = "${esc}[38;2;174;213;129m"
        $white  = "${esc}[38;2;255;243;224m"
    }
    "amber" {
        $accent = "${esc}[38;2;255;193;7m"
        $teal   = "${esc}[38;2;220;184;106m"
        $branch = "${esc}[38;2;240;230;200m"
        $muted  = "${esc}[38;2;158;148;119m"
        $red    = "${esc}[38;2;232;98;92m"
        $orange = "${esc}[38;2;232;152;62m"
        $yellow = "${esc}[38;2;212;170;50m"
        $green  = "${esc}[38;2;140;179;105m"
        $white  = "${esc}[38;2;245;240;224m"
    }
    "rose" {
        $accent = "${esc}[38;2;244;143;177m"
        $teal   = "${esc}[38;2;206;147;216m"
        $branch = "${esc}[38;2;248;215;224m"
        $muted  = "${esc}[38;2;173;139;159m"
        $red    = "${esc}[38;2;239;83;80m"
        $orange = "${esc}[38;2;255;138;101m"
        $yellow = "${esc}[38;2;255;213;79m"
        $green  = "${esc}[38;2;165;214;167m"
        $white  = "${esc}[38;2;253;232;239m"
    }
    default {
        $accent = "${esc}[38;2;77;166;255m"
        $teal   = "${esc}[38;2;77;175;176m"
        $branch = "${esc}[38;2;196;208;212m"
        $muted  = "${esc}[38;2;115;132;139m"
        $red    = "${esc}[38;2;255;85;85m"
        $orange = "${esc}[38;2;255;176;85m"
        $yellow = "${esc}[38;2;230;200;0m"
        $green  = "${esc}[38;2;0;160;0m"
        $white  = "${esc}[38;2;228;232;234m"
    }
}
$dim    = "${esc}[2m"
$reset  = "${esc}[0m"
$defaultSevenDayTimeFormat = "%m %d %H:%M"
$shortSevenDayDateFormat = "%m %d"

$sepPlain = " | "
$sepText = " ${dim}|${reset} "
$includeUsageSummary = $true
$outputText = $null

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
    if ($script:configuredMaxWidth -match '^[1-9]\d*$') {
        return [int]$script:configuredMaxWidth
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

function Repeat-Char([string]$char, [int]$count) {
    if ($count -le 0) { return "" }
    return $char * $count
}

function Convert-FromStrftimeFormat([string]$format) {
    if (-not $format) { return $null }

    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $format.Length; $i++) {
        $ch = $format[$i]
        if ($ch -eq '%') {
            if ($i + 1 -ge $format.Length) { return $null }
            $i++
            switch ($format[$i]) {
                'y' { [void]$builder.Append('yy') }
                'Y' { [void]$builder.Append('yyyy') }
                'm' { [void]$builder.Append('MM') }
                'd' { [void]$builder.Append('dd') }
                'H' { [void]$builder.Append('HH') }
                'M' { [void]$builder.Append('mm') }
                'b' { [void]$builder.Append('MMM') }
                'B' { [void]$builder.Append('MMMM') }
                default { return $null }
            }
            continue
        }

        if (" -/:".Contains([string]$ch)) {
            [void]$builder.Append($ch)
            continue
        }

        return $null
    }

    return $builder.ToString()
}

function Resolve-SevenDayTimeFormat([string]$format) {
    $resolved = if ($format) { $format } else { $defaultSevenDayTimeFormat }
    $dotNetFormat = Convert-FromStrftimeFormat $resolved
    if (-not $dotNetFormat) {
        $resolved = $defaultSevenDayTimeFormat
        $dotNetFormat = Convert-FromStrftimeFormat $resolved
    }

    return [pscustomobject]@{
        Strftime = $resolved
        DotNet = $dotNetFormat
    }
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

function Format-ResetTime([string]$isoStr, [string]$dotNetFormat, [bool]$trimHour = $false) {
    if (-not $isoStr -or $isoStr -eq "null") { return $null }
    try {
        $dt = [DateTimeOffset]::Parse($isoStr).LocalDateTime
        $formatted = $dt.ToString($dotNetFormat, [System.Globalization.CultureInfo]::InvariantCulture)
        if ($trimHour) {
            $formatted = [regex]::Replace($formatted, '(^| )0(\d:)', '$1$2')
        }
        return $formatted
    } catch {
        return $null
    }
}

function Test-FutureTime([string]$isoStr) {
    if (-not $isoStr -or $isoStr -eq "null") { return $false }
    try {
        $dt = [DateTimeOffset]::Parse($isoStr)
        return ($dt -gt [DateTimeOffset]::UtcNow)
    } catch {
        return $false
    }
}

$sevenDayTimeFormat = Resolve-SevenDayTimeFormat $script:sevenDayTimeSetting

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
    if ($script:includeUsageSummary) {
        $segments.Add((Build-FiveHourSegment))
        if ($script:showSevenDay) {
            $segments.Add((Build-SevenDaySegment))
        }
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

function Build-UsageBarLine([string]$label, [int]$pctValue, [string]$pctText, [string]$fullTime, [string]$shortTime) {
    $timeText = $fullTime
    $minReadableBarWidth = 8
    if ($label -eq "5h" -and $script:maxWidth -le 44) {
        $timeText = $null
    }
    if ($label -eq "7d") {
        if ($script:maxWidth -le 44) {
            $timeText = $shortTime
        } elseif ($script:maxWidth -le 52 -and $shortTime) {
            $timeText = $shortTime
        }
    }

    $baseBarWidth = 10
    $minBarWidth = 4
    $fixedWidth = $label.Length + 1 + $pctText.Length + 1 + 2
    if ($timeText) { $fixedWidth += 1 + $timeText.Length }
    $availableWidth = $script:maxWidth - $fixedWidth

    if ($availableWidth -lt $minReadableBarWidth -and $timeText) {
        $timeText = $null
        $fixedWidth = $label.Length + 1 + $pctText.Length + 1 + 2
        $availableWidth = $script:maxWidth - $fixedWidth
    }

    if ($availableWidth -lt $minReadableBarWidth) {
        return $null
    }

    $barWidth = $baseBarWidth
    if ($availableWidth -lt $barWidth) { $barWidth = $availableWidth }
    if ($barWidth -lt $minBarWidth) { $barWidth = $minBarWidth }

    $filledWidth = if ($pctValue -gt 0) { [math]::Floor($pctValue * $barWidth / 100) } else { 0 }
    if ($filledWidth -gt $barWidth) { $filledWidth = $barWidth }
    $emptyWidth = $barWidth - $filledWidth

    $filledPlain = Repeat-Char $barFilledChar $filledWidth
    $emptyPlain = Repeat-Char $barEmptyChar $emptyWidth

    if ($pctText -eq "--") {
        $pctColor = $branch
        $timeColor = $branch
        $filledText = "${muted}${filledPlain}${reset}"
    } else {
        $pctColor = Get-UsageColor $pctValue
        $timeColor = $muted
        $filledText = "${pctColor}${filledPlain}${reset}"
    }

    $plain = "$label $pctText [$filledPlain$emptyPlain]"
    $text = "${dim}${label}${reset} ${pctColor}${pctText}${reset} ${dim}[${reset}${filledText}${muted}${emptyPlain}${reset}${dim}]${reset}"
    if ($timeText) {
        $plain += " $timeText"
        $text += "${timeColor}$timeText${reset}"
    }

    return New-Segment $text $plain
}

function Build-BarsGitLine {
    if (-not $script:displayDir) {
        return $null
    }

    $repoName = $script:displayDir
    $branchName = $script:gitBranch
    if ($branchName) {
        $plainText = "$repoName@$branchName"
        if ($plainText.Length -gt $script:maxWidth) {
            $branchNameLimit = $script:maxWidth - $repoName.Length - 1
            if ($branchNameLimit -le 3) {
                $branchName = "..."
            } elseif ($branchName.Length -gt $branchNameLimit) {
                $branchName = Truncate-Middle $branchName $branchNameLimit
            }
            $plainText = "$repoName@$branchName"
        }
        if ($plainText.Length -gt $script:maxWidth) {
            $plainText = Truncate-Middle $plainText $script:maxWidth
        }
        $combinedPlain = "$repoName@$branchName"
        if ($plainText -ne $combinedPlain) {
            $textOutput = "${muted}$plainText${reset}"
        } else {
            $textOutput = "${muted}$repoName${reset}${dim}@${reset}${muted}$branchName${reset}"
        }
        return New-Segment $textOutput $plainText
    }

    $plainText = $repoName
    if ($plainText.Length -gt $script:maxWidth) {
        $plainText = Truncate-Middle $plainText $script:maxWidth
    }
    return New-Segment "${muted}$plainText${reset}" $plainText
}

function Build-BarsOverviewLine {
    $segments = @(
        Build-ModelSegment
        Build-EffSegment
        Build-CtxSegment
    )

    $plain = ($segments | ForEach-Object { $_.Plain }) -join $sepPlain
    $text = ($segments | ForEach-Object { $_.Text }) -join $sepText
    return New-Segment $text $plain
}

function Append-OutputLine([string]$line) {
    if (-not $line) {
        return
    }

    if ($script:outputText) {
        $script:outputText += "`n$line"
    } else {
        $script:outputText = $line
    }
}

function Render-CompactOutput([bool]$includeUsage) {
    $script:includeUsageSummary = $includeUsage
    $composed = Compose-Output

    if ($composed.Length -gt $script:maxWidth -and $script:showExtra) {
        $script:showExtra = $false
        $composed = Compose-Output
    }

    if ($includeUsage -and $composed.Length -gt $script:maxWidth -and $script:showSevenDayReset) {
        $script:showSevenDayReset = $false
        $composed = Compose-Output
    }

    if ($includeUsage -and $composed.Length -gt $script:maxWidth -and $script:showFiveHourReset) {
        $script:showFiveHourReset = $false
        $composed = Compose-Output
    }

    if ($composed.Length -gt $script:maxWidth -and $script:showGitDiff) {
        $script:showGitDiff = $false
        $composed = Compose-Output
    }

    if ($includeUsage -and $composed.Length -gt $script:maxWidth -and $script:showSevenDay) {
        $script:showSevenDay = $false
        $composed = Compose-Output
    }

    if ($composed.Length -gt $script:maxWidth -and $script:gitSegmentLen -gt 0) {
        $availableForGit = $script:maxWidth - ($composed.Length - $script:gitSegmentLen)
        if ($availableForGit -lt 3) { $availableForGit = 3 }
        $script:gitTruncateWidth = $availableForGit
        $composed = Compose-Output
    }

    $script:outputText = $composed.Text
}

function Render-BarsOutput {
    $script:outputText = $null

    if ($script:showBarsGitLine) {
        $gitLine = Build-BarsGitLine
        if ($gitLine) {
            Append-OutputLine $gitLine.Text
        }
    }

    if ($script:showBarsOverviewLine) {
        $overviewLine = Build-BarsOverviewLine
        Append-OutputLine $overviewLine.Text
    }

    if ($script:showHourlyBar) {
        if ($script:usageAvailable) {
            $fiveLine = Build-UsageBarLine "5h" $script:fiveHourPct "$($script:fiveHourPct)%" $script:fiveHourReset $null
        } else {
            $fiveLine = Build-UsageBarLine "5h" 0 "--" "n/a" $null
        }
        if ($fiveLine) {
            Append-OutputLine $fiveLine.Text
        }
    }

    if ($script:showDailyBar) {
        if ($script:usageAvailable) {
            $sevenLine = Build-UsageBarLine "7d" $script:sevenDayPct "$($script:sevenDayPct)%" $script:sevenDayReset $script:sevenDayDate
        } else {
            $sevenLine = Build-UsageBarLine "7d" 0 "--" "n/a" $null
        }
        if ($sevenLine) {
            Append-OutputLine $sevenLine.Text
        }
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
    if ($script:claudeSettings -and $script:claudeSettings.effortLevel) {
        $effortLevel = $script:claudeSettings.effortLevel
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
$sevenDayDate = $null
$extraEnabled = $false
$extraUsed = $null
$extraLimit = $null

if ($usageData) {
    try {
        $usage = if ($usageData -is [string]) { $usageData | ConvertFrom-Json } else { $usageData }
        if ($usage.five_hour) {
            $usageAvailable = $true
            $fiveHourPct = [math]::Floor([double]$usage.five_hour.utilization)
            if (Test-FutureTime $usage.five_hour.resets_at) {
                $fiveHourReset = Format-ResetTime $usage.five_hour.resets_at "HH:mm" $true
                $showFiveHourReset = [bool]$fiveHourReset
            }

            $sevenDayPct = [math]::Floor([double]$usage.seven_day.utilization)
            if (Test-FutureTime $usage.seven_day.resets_at) {
                $sevenDayReset = Format-ResetTime $usage.seven_day.resets_at $sevenDayTimeFormat.DotNet
                $sevenDayDate = Format-ResetTime $usage.seven_day.resets_at (Convert-FromStrftimeFormat $shortSevenDayDateFormat)
                $showSevenDayReset = [bool]$sevenDayReset
            }

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
if ($layoutName -eq "bars") {
    Render-BarsOutput
} else {
    Render-CompactOutput $true
}

[Console]::Out.Write($outputText)
