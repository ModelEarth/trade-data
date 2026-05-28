# state-trade-map

Interactive US state trade flow map using `year/2019/US/domestic/state_trade_flows.csv`.

`index.html` is intended to work in three modes: opened locally from disk, served from a local or repo web root, or mirrored through a `localsite` profile path. It tries repo-relative CSV paths first and then falls back to GitHub raw when needed. The page centers on the dataset's `level` field as "amount spent" and also includes an `employment_impact` toggle.

The state map reads the current 2019 US domestic state-layer CSVs directly. `state_trade_flows.csv` is derived from the latest `state_industry_impacts.csv`, `trade.csv`, `trade_factor.csv`, and `trade_price_indices.csv` inputs so the map can show state-to-state flows without using the stale NY/OH-only flow artifact.
