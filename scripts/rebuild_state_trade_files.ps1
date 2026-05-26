param(
    [string]$Year = "2019",
    [string]$Country = "US",
    [string]$Flow = "domestic"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$datasetDir = Join-Path $repoRoot ("year/{0}/{1}/{2}" -f $Year, $Country, $Flow)

$tradePath = Join-Path $datasetDir "trade.csv"
$employmentPath = Join-Path $datasetDir "trade_employment.csv"
$industryPath = Join-Path $repoRoot ("year/{0}/industry.csv" -f $Year)
$stateCodesPath = Join-Path $datasetDir "state_codes.csv"
$stateSpecsPath = Join-Path $datasetDir "state_specializations.csv"
$multipliersPath = Join-Path $datasetDir "employment_multipliers.csv"

$flowOutputPath = Join-Path $datasetDir "state_trade_flows.csv"
$impactOutputPath = Join-Path $datasetDir "state_industry_impacts.csv"
$specOutputPath = Join-Path $datasetDir "state_specializations.csv"

$primaryStateCount = 5
$extraStateCount = 7

function Get-BroadCategory {
    param(
        [string]$IndustryCode,
        [hashtable]$IndustryLookup
    )

    $lookup = $null
    if ($IndustryLookup.ContainsKey($IndustryCode)) {
        $lookup = $IndustryLookup[$IndustryCode]
    }

    $categoryText = ""
    $nameText = ""
    if ($null -ne $lookup) {
        if ($lookup.ContainsKey("Category")) {
            $categoryText = [string]$lookup["Category"]
        }
        if ($lookup.ContainsKey("Name")) {
            $nameText = [string]$lookup["Name"]
        }
    }

    $text = "{0} {1} {2}" -f $IndustryCode, $categoryText, $nameText
    $text = $text.ToLowerInvariant()

    if (
        $text -match "agric|cattle|poultry|crop|fish|forestry|food|dairy|meat|rice|wheat|vegetable|fruit|seed|tobacco"
    ) {
        return "agriculture"
    }
    if (
        $text -match "mining|coal|crude|petroleum|natural gas|ore|quarry|uranium|fuel|refiner|chemical and fertilizer minerals|hydrocarbon"
    ) {
        return "mining"
    }
    if ($text -match "construction") {
        return "construction"
    }
    if ($text -match "utilit|electricity|water|sewage|distribution services of electricity|gas coke") {
        return "utilities"
    }
    if (
        $text -match "transport|wholesale|retail|motor vehicles|distribution and trade services|post and telecommunication|air transport|rail|land transport|water transport"
    ) {
        return "transportation"
    }
    if (
        $text -match "manufactur|textile|paper|wood|machinery|metal|electronic|rubber|plastic|furniture|pharma|medical|vehicle|chemical|fabricated|printing"
    ) {
        return "manufacturing"
    }

    return "services"
}

function Get-SpecializationCategory {
    param([string]$Specialization)

    switch -Regex ($Specialization.ToLowerInvariant()) {
        "agric" { return "agriculture" }
        "manufact" { return "manufacturing" }
        "automotive|aerospace|chemicals" { return "manufacturing" }
        "energy" { return "mining" }
        "transport" { return "transportation" }
        "construction" { return "construction" }
        "utilit|water" { return "utilities" }
        default { return "services" }
    }
}

function Get-SelectedStates {
    param(
        [string[]]$OrderedStates,
        [int]$PrimaryCount,
        [int]$ExtraCount,
        [int]$Seed
    )

    $selected = New-Object System.Collections.Generic.List[string]
    $primaryLimit = [Math]::Min($PrimaryCount, $OrderedStates.Count)
    for ($i = 0; $i -lt $primaryLimit; $i++) {
        $selected.Add($OrderedStates[$i])
    }

    $remaining = @()
    if ($OrderedStates.Count -gt $primaryLimit) {
        $remaining = $OrderedStates[$primaryLimit..($OrderedStates.Count - 1)]
    }

    if ($remaining.Count -eq 0) {
        return $selected.ToArray()
    }

    $cursor = [Math]::Abs($Seed)
    $step = 7
    for ($i = 0; $i -lt $ExtraCount; $i++) {
        $index = ($cursor + ($i * $step)) % $remaining.Count
        $candidate = $remaining[$index]
        if (-not $selected.Contains($candidate)) {
            $selected.Add($candidate)
        }
    }

    return $selected.ToArray()
}

Write-Host "Loading source files from $datasetDir"

$industryLookup = @{}
Import-Csv $industryPath | ForEach-Object {
    $industryLookup[$_.industry_id] = @{
        Name = $_.name
        Category = $_.category
    }
}

$employmentIntensityByTrade = @{}
Import-Csv $employmentPath | ForEach-Object {
    $employmentIntensityByTrade[$_.trade_id] = [double]$_.employment_intensity
}

$multiplierByIndustry = @{}
Import-Csv $multipliersPath | ForEach-Object {
    $multiplierByIndustry[$_.industry] = @{
        direct = [double]$_.direct
        indirect = [double]$_.indirect
        induced = [double]$_.induced
    }
}

$stateNames = @{}
$stateCodes = New-Object System.Collections.Generic.List[string]
Import-Csv $stateCodesPath | ForEach-Object {
    $stateCodes.Add($_.state_code)
    $stateNames[$_.state_code] = $_.state_name
}

$specializationsByState = @{}
foreach ($stateCode in $stateCodes) {
    $specializationsByState[$stateCode] = New-Object System.Collections.Generic.List[string]
}

Import-Csv $stateSpecsPath | ForEach-Object {
    if ($specializationsByState.ContainsKey($_.state_code)) {
        $specializationsByState[$_.state_code].Add($_.specialization)
    }
}

$broadCategories = @("services", "manufacturing", "agriculture", "mining", "construction", "utilities", "transportation")

$stateProfiles = @{}
foreach ($stateCode in $stateCodes) {
    $specs = $specializationsByState[$stateCode]
    $affinity = @{}
    foreach ($category in $broadCategories) {
        $affinity[$category] = 1.0
    }

    foreach ($spec in $specs) {
        $mappedCategory = Get-SpecializationCategory $spec
        $affinity[$mappedCategory] += 1.35
    }

    $stateProfiles[$stateCode] = @{
        size = 1.0 + ($specs.Count * 0.25)
        affinity = $affinity
    }
}

$orderedStatesByCategory = @{}
foreach ($category in $broadCategories) {
    $orderedStatesByCategory[$category] = @(
        $stateCodes |
            Sort-Object -Property @{
                Expression = {
                    -1 * (
                        [double]$stateProfiles[$_].size *
                        [double]$stateProfiles[$_].affinity[$category]
                    )
                }
            }, @{
                Expression = { $_ }
            }
    )
}

$pairTotals = @{}
$stateIndustryTotals = @{}

Write-Host "Rebuilding state trade files from trade.csv and trade_employment.csv"
$tradeRows = Import-Csv $tradePath
$rowCount = 0

foreach ($row in $tradeRows) {
    $rowCount += 1
    $tradeId = [int]$row.trade_id
    $amount = [double]$row.amount
    if ($amount -le 0) {
        continue
    }

    $sourceCategory = Get-BroadCategory -IndustryCode $row.industry1 -IndustryLookup $industryLookup
    $destinationCategory = Get-BroadCategory -IndustryCode $row.industry2 -IndustryLookup $industryLookup
    $stateIndustryCode = $sourceCategory

    $employmentIntensity = 0.0
    if ($employmentIntensityByTrade.ContainsKey($row.trade_id)) {
        $employmentIntensity = [double]$employmentIntensityByTrade[$row.trade_id]
    }

    $originCandidates = Get-SelectedStates -OrderedStates $orderedStatesByCategory[$sourceCategory] -PrimaryCount $primaryStateCount -ExtraCount $extraStateCount -Seed $tradeId
    $destinationCandidates = Get-SelectedStates -OrderedStates $orderedStatesByCategory[$destinationCategory] -PrimaryCount $primaryStateCount -ExtraCount $extraStateCount -Seed ($tradeId * 3)

    $originWeights = @{}
    $destinationWeights = @{}
    $originTotal = 0.0
    $destinationTotal = 0.0

    foreach ($stateCode in $originCandidates) {
        $weight = [double]$stateProfiles[$stateCode].size * [double]$stateProfiles[$stateCode].affinity[$sourceCategory]
        $originWeights[$stateCode] = $weight
        $originTotal += $weight
    }
    foreach ($stateCode in $destinationCandidates) {
        $weight = [double]$stateProfiles[$stateCode].size * [double]$stateProfiles[$stateCode].affinity[$destinationCategory]
        $destinationWeights[$stateCode] = $weight
        $destinationTotal += $weight
    }

    if ($originTotal -le 0 -or $destinationTotal -le 0) {
        continue
    }

    $pairDenominator = 0.0
    foreach ($originState in $originCandidates) {
        $originShare = $originWeights[$originState] / $originTotal
        foreach ($destinationState in $destinationCandidates) {
            if ($originState -eq $destinationState) {
                continue
            }
            $destinationShare = $destinationWeights[$destinationState] / $destinationTotal
            $pairDenominator += ($originShare * $destinationShare)
        }
    }

    if ($pairDenominator -le 0) {
        continue
    }

    foreach ($originState in $originCandidates) {
        $originShare = $originWeights[$originState] / $originTotal
        foreach ($destinationState in $destinationCandidates) {
            if ($originState -eq $destinationState) {
                continue
            }

            $destinationShare = $destinationWeights[$destinationState] / $destinationTotal
            $share = ($originShare * $destinationShare) / $pairDenominator
            $allocatedLevel = $amount * $share
            $allocatedEmployment = ($allocatedLevel * $employmentIntensity) / 1000000000.0

            $pairKey = "{0}|{1}|{2}" -f $originState, $destinationState, $stateIndustryCode
            if (-not $pairTotals.ContainsKey($pairKey)) {
                $pairTotals[$pairKey] = @{
                    origin_state = $originState
                    destination_state = $destinationState
                    state_industry_code = $stateIndustryCode
                    level = 0.0
                    employment_impact = 0.0
                }
            }
            $pairTotals[$pairKey].level += $allocatedLevel
            $pairTotals[$pairKey].employment_impact += $allocatedEmployment

            foreach ($stateCode in @($originState, $destinationState)) {
                $stateKey = "{0}|{1}" -f $stateCode, $stateIndustryCode
                if (-not $stateIndustryTotals.ContainsKey($stateKey)) {
                    $stateIndustryTotals[$stateKey] = @{
                        region = "US-{0}" -f $stateCode
                        industry_code = $stateIndustryCode
                        level = 0.0
                        employment_impact = 0.0
                    }
                }
                $stateIndustryTotals[$stateKey].level += $allocatedLevel
                $stateIndustryTotals[$stateKey].employment_impact += $allocatedEmployment
            }
        }
    }
}

Write-Host ("Processed {0} national trade rows into {1} aggregated state pairs" -f $rowCount, $pairTotals.Count)

$flowRows = New-Object System.Collections.Generic.List[object]
$tradeCounter = 1
foreach ($key in ($pairTotals.Keys | Sort-Object)) {
    $row = $pairTotals[$key]
    $flowRows.Add([pscustomobject]@{
        trade_id = $tradeCounter
        origin_state = $row.origin_state
        destination_state = $row.destination_state
        state_industry_code = $row.state_industry_code
        level = [Math]::Round([double]$row.level, 6)
        flow_type = "inter_state"
        employment_impact = [Math]::Round([double]$row.employment_impact, 12)
    })
    $tradeCounter += 1
}
$flowRows | Export-Csv -Path $flowOutputPath -NoTypeInformation

$impactRows = New-Object System.Collections.Generic.List[object]
foreach ($key in ($stateIndustryTotals.Keys | Sort-Object)) {
    $row = $stateIndustryTotals[$key]
    $industryCode = $row.industry_code
    $multiplier = $null
    if ($multiplierByIndustry.ContainsKey($industryCode)) {
        $multiplier = $multiplierByIndustry[$industryCode]
    } else {
        $multiplier = $multiplierByIndustry["default"]
    }

    $employmentImpact = [double]$row.employment_impact
    $outputImpact = [double]$row.level

    $impactRows.Add([pscustomobject]@{
        state_code = $row.region.Substring(3)
        industry_code = $industryCode
        direct_jobs = [Math]::Round($employmentImpact * [double]$multiplier.direct, 12)
        indirect_jobs = [Math]::Round($employmentImpact * [double]$multiplier.indirect, 12)
        induced_jobs = [Math]::Round($employmentImpact * [double]$multiplier.induced, 12)
        total_output_impact = [Math]::Round($outputImpact, 6)
        tax_revenue_impact = [Math]::Round($outputImpact * 0.12, 6)
    })
}
$impactRows | Export-Csv -Path $impactOutputPath -NoTypeInformation

$specializationRows = New-Object System.Collections.Generic.List[object]
$stateIndustryIndex = @{}
foreach ($entry in $stateIndustryTotals.GetEnumerator()) {
    $stateCode = $entry.Value.region.Substring(3)
    if (-not $stateIndustryIndex.ContainsKey($stateCode)) {
        $stateIndustryIndex[$stateCode] = New-Object System.Collections.Generic.List[object]
    }
    $stateIndustryIndex[$stateCode].Add([pscustomobject]@{
        industry = $entry.Value.industry_code
        level = [double]$entry.Value.level
    })
}

foreach ($stateCode in $stateCodes) {
    $topIndustries = @()
    if ($stateIndustryIndex.ContainsKey($stateCode)) {
        $topIndustries = @(
            $stateIndustryIndex[$stateCode] |
                Sort-Object -Property @{ Expression = { -1 * $_.level } }, @{ Expression = { $_.industry } } |
                Select-Object -First 3
        )
    }

    if ($topIndustries.Count -eq 0) {
        $topIndustries = @(
            [pscustomobject]@{ industry = "services"; level = 1.0 },
            [pscustomobject]@{ industry = "manufacturing"; level = 0.5 },
            [pscustomobject]@{ industry = "transportation"; level = 0.25 }
        )
    }

    foreach ($industry in $topIndustries) {
        $specializationRows.Add([pscustomobject]@{
            state_code = $stateCode
            specialization = $industry.industry
        })
    }
}
$specializationRows | Export-Csv -Path $specOutputPath -NoTypeInformation

Write-Host "Wrote rebuilt files:"
Write-Host " - $flowOutputPath"
Write-Host " - $impactOutputPath"
Write-Host " - $specOutputPath"
