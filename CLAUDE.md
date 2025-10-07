# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository processes and integrates international trade data from EXIOBASE with US-BEA (Bureau of Economic Analysis) data to create comprehensive trade flow datasets with environmental and economic impact factors.

**Data Sources:**
- EXIOBASE MRIO (Multi-Regional Input-Output) data from https://model.earth/exiobase/tradeflow/
- US-BEA API data from https://model.earth/exiobase/tradeflow/bea/
- EPA USEEIO commodity and sector crosswalks

**Key Concept:** The repository uses "industry" (5-char codes like PADDY, WHEAT, BUSIN) for EXIOBASE industry categories and "commodity" (6-char codes) for USEEIO commodity classifications. "beasummary" is used for BEA summary tables rather than "sector" which has too many conflicting meanings.

## Repository Structure

```
year/{YYYY}/                    # Data organized by year (e.g., 2019, 2022)
  ├── {COUNTRY}/               # Country-specific data (US, CN, CA, etc.)
  │   ├── domestic/            # Domestic trade flows within the country
  │   │   ├── trade.csv                    # Base bilateral trade flows
  │   │   ├── bea_trade_detail.csv         # BEA-enhanced trade details (US only)
  │   │   ├── state_trade_flows.csv        # State-level trade flows (US only)
  │   │   ├── trade_employment.csv         # Employment impacts
  │   │   ├── trade_factor.csv             # Environmental factors
  │   │   ├── trade_impact.csv             # Economic impacts
  │   │   ├── trade_material.csv           # Material flows
  │   │   ├── trade_resource.csv           # Resource consumption
  │   │   ├── bea_industry_mapping.csv     # BEA industry concordance
  │   │   ├── state_industry_impacts.csv   # State economic impacts
  │   │   └── trade_price_indices.csv      # Trade price indices
  │   ├── imports/             # Import flows (same file structure)
  │   ├── exports/             # Export flows (same file structure)
  │   └── bea-report.md        # BEA integration validation report (US only)
  ├── industry.csv             # EXIOBASE industry definitions
  ├── factor.csv               # Environmental/economic factors
  ├── flow.csv                 # FEDEFL flow definitions
  ├── flow_summary.json        # Flow statistics summary
  └── flow_validation.json     # Flow validation results

concordance/                    # Crosswalk/mapping files
  ├── exio_to_useeio2_commodity_concordance.csv
  ├── BEA_service_to_useeio2_sector_concordance.csv
  └── exio_country_concordance.csv

config.yaml                     # Configuration file (year, country)
```

## Data Architecture

### Core Trade Flow Structure
- `trade.csv`: Base bilateral trade flows with structure:
  - `trade_id`: Unique identifier for each trade relationship
  - `year`: Trade year
  - `region1`, `region2`: Trading regions (2-letter country codes or state codes)
  - `industry1`, `industry2`: EXIOBASE industry codes (5-char)
  - `amount`: Trade value in USD

### US-BEA Integration (US only)
For US data, additional BEA-enhanced tables are generated:
- `bea_trade_detail.csv`: Links trade flows to BEA industry categories
- `state_trade_flows.csv`: State-level disaggregation (large file, ~50MB)
- `bea_industry_mapping.csv`: EXIOBASE to BEA industry concordance

### Flow Classification System
Flows are categorized by:
- `context`: environmental, emission/air, emission/water, resource/natural, economic
- `compartment`: environmental, air, water, natural resources, economic
- `flow_class`: environmental, resource, economic
- `trade_relevance`: Numeric score (5-20) indicating importance for trade analysis

High-relevance flows (trade_relevance ≥ 14) typically include:
- Employment (person*year)
- Value added (USD)
- Carbon dioxide, Methane (kg)
- Energy use (MJ), Land use (m2), Water use (L)

## Configuration

`config.yaml` specifies the processing parameters:
```yaml
year: 2019
country: US
```

## Important Data Distinctions

### NAICS Version Changes
The repository handles transitions between NAICS classification systems:
- **NAICS 2012** (used by CEDA): Original classification
- **NAICS 2017** (used by USEEIO): Modified with:
  - Household Appliance Consolidation: 335221, 335222, 335224, 335228 → 335220
  - Aluminum Manufacturing Split: 331313 → 331313 + 33131B

### Concordance Mappings
Three EPA crosswalks link different classification systems:
1. EXIOBASE commodities → USEEIO commodities
2. BEA service categories → USEEIO sectors
3. EXIOBASE Country/Region → BEA Service, Census Goods, TiVA regions

## Working with the Data

### Finding Industry/Commodity Information
- Check `year/{YYYY}/industry.csv` for EXIOBASE industry definitions and categories
- Use concordance files in `concordance/` for mapping between classification systems

### Understanding Trade Flows
- Trade flows are organized by direction: domestic, imports, exports
- Each flow type has consistent file structure across countries
- US data includes additional BEA integration files not present for other countries

### Flow Validation
- `flow_summary.json`: Quick statistics on flow counts by context/compartment/class
- `flow_validation.json`: Detailed validation results for flow definitions

## Data Processing Notes

- Files are CSV format with consistent column structures
- Large files (especially `state_trade_flows.csv`) may exceed 40-50MB
- Trade IDs uniquely identify bilateral industry relationships
- State codes are used for US sub-national analysis (region1/region2 fields)
- BEA API integration is US-specific; other countries use EXIOBASE data only
