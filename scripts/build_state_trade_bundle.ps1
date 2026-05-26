$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$dataRoot = Join-Path $repoRoot "year\2019\US\domestic"
$outputPath = Join-Path $repoRoot "state-trade-data.js"

& (Join-Path $PSScriptRoot "build_latest_state_trade_flows.ps1")

$files = [ordered]@{
    flowCsv = "state_trade_flows.csv"
    stateCodesCsv = "state_codes.csv"
    impactCsv = "state_industry_impacts.csv"
    specializationCsv = "state_specializations.csv"
}

$payload = [ordered]@{}
foreach ($entry in $files.GetEnumerator()) {
    $filePath = Join-Path $dataRoot $entry.Value
    $payload[$entry.Key] = [System.IO.File]::ReadAllText($filePath)
}

$json = $payload | ConvertTo-Json -Compress
$content = "window.STATE_TRADE_LOCAL_DATA = $json;"
[System.IO.File]::WriteAllText($outputPath, $content, [System.Text.Encoding]::UTF8)
