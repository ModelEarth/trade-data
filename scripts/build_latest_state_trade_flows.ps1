param(
    [string]$Year = "2019",
    [string]$Country = "US",
    [string]$Flow = "domestic"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$datasetDir = Join-Path $repoRoot ("year/{0}/{1}/{2}" -f $Year, $Country, $Flow)
$industryPath = Join-Path $repoRoot ("year/{0}/industry.csv" -f $Year)
$tradePath = Join-Path $datasetDir "trade.csv"
$impactPath = Join-Path $datasetDir "state_industry_impacts.csv"
$pricePath = Join-Path $datasetDir "trade_price_indices.csv"
$factorPath = Join-Path $datasetDir "trade_factor.csv"
$outputPath = Join-Path $datasetDir "state_trade_flows.csv"

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
        $categoryText = [string]$lookup.category
        $nameText = [string]$lookup.name
    }

    $text = ("{0} {1} {2}" -f $IndustryCode, $categoryText, $nameText).ToLowerInvariant()
    if ($text -match "agric|cattle|poultry|crop|fish|forestry|food|dairy|meat|rice|wheat|vegetable|fruit|seed|tobacco") {
        return "agriculture"
    }
    if ($text -match "mining|coal|crude|petroleum|natural gas|ore|quarry|uranium|fuel|refiner|chemical and fertilizer minerals|hydrocarbon") {
        return "mining"
    }
    if ($text -match "construction") {
        return "construction"
    }
    if ($text -match "utilit|electricity|water|sewage|distribution services of electricity|gas coke") {
        return "utilities"
    }
    if ($text -match "transport|wholesale|retail|motor vehicles|distribution and trade services|post and telecommunication|air transport|rail|land transport|water transport") {
        return "transportation"
    }
    if ($text -match "manufactur|textile|paper|wood|machinery|metal|electronic|rubber|plastic|furniture|pharma|medical|vehicle|chemical|fabricated|printing") {
        return "manufacturing"
    }
    return "services"
}

function Add-ToHashtableDouble {
    param(
        [hashtable]$Table,
        [string]$Key,
        [double]$Amount
    )

    if (-not $Table.ContainsKey($Key)) {
        $Table[$Key] = 0.0
    }
    $Table[$Key] = [double]$Table[$Key] + $Amount
}

Write-Host "Loading latest state trade inputs from $datasetDir"

$industryLookup = @{}
Import-Csv $industryPath | ForEach-Object {
    $industryLookup[$_.industry_id] = @{
        name = $_.name
        category = $_.category
    }
}

$weightsByIndustry = @{}
$jobsByStateIndustry = @{}
$statesByIndustry = @{}
Import-Csv $impactPath | ForEach-Object {
    $stateCode = ([string]$_.region) -replace "^US-", ""
    $industryCode = [string]$_.industry_code
    $output = [double]$_.total_output_impact
    $jobs = [double]$_.direct_jobs + [double]$_.indirect_jobs + [double]$_.induced_jobs
    $key = "{0}|{1}" -f $stateCode, $industryCode

    Add-ToHashtableDouble -Table $weightsByIndustry -Key $industryCode -Amount $output
    $jobsByStateIndustry[$key] = $jobs

    if (-not $statesByIndustry.ContainsKey($industryCode)) {
        $statesByIndustry[$industryCode] = New-Object System.Collections.Generic.List[object]
    }
    $statesByIndustry[$industryCode].Add([pscustomobject]@{
        state = $stateCode
        weight = [Math]::Max($output, 0.0)
        jobs = $jobs
    })
}

$priceAdjustmentByTrade = @{}
Import-Csv $pricePath | ForEach-Object {
    $priceAdjustmentByTrade[$_.trade_id] = [double]$_.currency_adjustment_factor
}

$factorByTrade = @{}
Import-Csv $factorPath | ForEach-Object {
    Add-ToHashtableDouble -Table $factorByTrade -Key ([string]$_.trade_id) -Amount ([double]$_.level)
}

$pairTotals = @{}
$tradeRows = Import-Csv $tradePath
foreach ($trade in $tradeRows) {
    $tradeId = [string]$trade.trade_id
    $amount = [double]$trade.amount
    if ($amount -le 0) {
        continue
    }

    $sourceIndustry = Get-BroadCategory -IndustryCode $trade.industry1 -IndustryLookup $industryLookup
    $destinationIndustry = Get-BroadCategory -IndustryCode $trade.industry2 -IndustryLookup $industryLookup

    if (-not $statesByIndustry.ContainsKey($sourceIndustry) -or -not $statesByIndustry.ContainsKey($destinationIndustry)) {
        continue
    }

    $originStates = $statesByIndustry[$sourceIndustry]
    $destinationStates = $statesByIndustry[$destinationIndustry]
    $originTotal = [double]$weightsByIndustry[$sourceIndustry]
    $destinationTotal = [double]$weightsByIndustry[$destinationIndustry]
    if ($originTotal -le 0 -or $destinationTotal -le 0) {
        continue
    }

    $priceAdjustment = 1.0
    if ($priceAdjustmentByTrade.ContainsKey($tradeId)) {
        $priceAdjustment = [double]$priceAdjustmentByTrade[$tradeId]
    }
    $tradeFactor = 0.0
    if ($factorByTrade.ContainsKey($tradeId)) {
        $tradeFactor = [double]$factorByTrade[$tradeId]
    }

    $denominator = 0.0
    foreach ($origin in $originStates) {
        foreach ($destination in $destinationStates) {
            if ($origin.state -eq $destination.state) {
                continue
            }
            $denominator += ([double]$origin.weight / $originTotal) * ([double]$destination.weight / $destinationTotal)
        }
    }
    if ($denominator -le 0) {
        continue
    }

    foreach ($origin in $originStates) {
        $originShare = [double]$origin.weight / $originTotal
        foreach ($destination in $destinationStates) {
            if ($origin.state -eq $destination.state) {
                continue
            }

            $destinationShare = [double]$destination.weight / $destinationTotal
            $share = ($originShare * $destinationShare) / $denominator
            $allocatedLevel = $amount * $share
            $allocatedAdjusted = $allocatedLevel * $priceAdjustment
            $allocatedFactor = $tradeFactor * $share
            $allocatedJobs = (([double]$origin.jobs + [double]$destination.jobs) / 2.0) * $share
            $key = "{0}|{1}|{2}" -f $origin.state, $destination.state, $sourceIndustry

            if (-not $pairTotals.ContainsKey($key)) {
                $pairTotals[$key] = @{
                    origin_state = $origin.state
                    destination_state = $destination.state
                    state_industry_code = $sourceIndustry
                    level = 0.0
                    price_adjusted_level = 0.0
                    factor_impact = 0.0
                    employment_impact = 0.0
                }
            }
            $pairTotals[$key].level += $allocatedLevel
            $pairTotals[$key].price_adjusted_level += $allocatedAdjusted
            $pairTotals[$key].factor_impact += $allocatedFactor
            $pairTotals[$key].employment_impact += $allocatedJobs
        }
    }
}

$rows = New-Object System.Collections.Generic.List[object]
$counter = 1
foreach ($key in ($pairTotals.Keys | Sort-Object)) {
    $row = $pairTotals[$key]
    $rows.Add([pscustomobject]@{
        trade_id = $counter
        origin_state = $row.origin_state
        destination_state = $row.destination_state
        state_industry_code = $row.state_industry_code
        level = [Math]::Round([double]$row.level, 6)
        price_adjusted_level = [Math]::Round([double]$row.price_adjusted_level, 6)
        factor_impact = [Math]::Round([double]$row.factor_impact, 6)
        flow_type = "derived_inter_state"
        employment_impact = [Math]::Round([double]$row.employment_impact, 12)
    })
    $counter += 1
}

$rows | Export-Csv -Path $outputPath -NoTypeInformation
Write-Host ("Wrote {0} derived state trade flow rows to {1}" -f $rows.Count, $outputPath)
