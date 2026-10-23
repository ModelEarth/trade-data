# BEA Trade Analysis Validation Report

**Generated**: 2026-10-23 03:12:20
**Year**: 2022
**Country**: US
**Trade Flows**: domestic,imports,exports
**Force Regeneration**: False

## Optimization Status

- File existence checking enabled - existing trade.csv files reused

## US Data Source Integration

### Exiobase Data
- Successfully processed Exiobase MRIO data
- Generated base trade flows with trade_id structure

### US-BEA API Integration
- Successfully integrated US-BEA API data

### BEA API Usage Statistics
- API calls made: 11
- Cache files created: 77

## BEA Enhanced Output Files Generated

### Enhanced Relational Tables
- `trade.csv` - Base trade flows
- `interstate.csv` - State-to-state trade details
- `interstate_factor.csv` - State-level trade flows
- `export_competitiveness.csv` - Export competitiveness analysis
- `import_dependency.csv` - Import dependency analysis
- `flow.csv` - FEDEFL flow details
- `industry.csv` - Industry mapping (using existing file from parent directory)
- `category_state.csv` - BEA state weights by state_industry_code
- `trade-us.csv` - National purchases by industry pair, US producers and imports
- `industry_category.csv` - Each industry's state_industry_code

