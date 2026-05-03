# Stock Portfolio Risk & Return Analyzer

A statistical analysis toolkit for equity portfolio evaluation, built in R with a SQLite backend.

**Author:** Zach Wilson  
**Stack:** R · SQLite · quantmod · tidyverse · ggplot2

---

## Overview

This project pulls historical price data for a 12-ticker equity portfolio from Yahoo Finance, stores it in a normalized SQLite database, and applies core financial statistics to characterize risk and return:

- **Annualized return & volatility** (geometric mean, log-return standard deviation)
- **Sharpe ratio** (risk-adjusted return vs. risk-free rate)
- **CAPM regression** — beta, Jensen's alpha, R²
- **Maximum drawdown** (peak-to-trough loss)
- **Historical VaR & CVaR** at 95% confidence (tail risk)
- **Pairwise correlation matrix** across all tickers
- **Hypothesis testing** — one-sample t-tests on mean daily returns

---

## Project Structure

```
stock-portfolio-analyzer/
├── data/
│   └── portfolio.db          # SQLite database
├── R/
│   ├── 01_pull_data.R        # Yahoo Finance ETL via quantmod
│   ├── 02_load_db.R          # Write to SQLite, compute returns
│   └── 03_analysis.R         # Risk metrics, regression, correlation
├── reports/
│   └── portfolio_analysis.Rmd
├── schema.sql                 # Full database schema
└── README.md
```

---

## Quickstart

### Prerequisites

```r
install.packages(c(
  "quantmod", "tidyverse", "DBI", "RSQLite",
  "lubridate", "glue", "broom", "ggplot2",
  "rmarkdown", "knitr", "kableExtra"
))
```

### Run the Pipeline

```r
source("R/01_pull_data.R")   # ~30 seconds to pull all tickers
source("R/02_load_db.R")     # loads into SQLite, computes returns
source("R/03_analysis.R")    # risk metrics, CAPM, correlation

# Generate the report
rmarkdown::render("reports/portfolio_analysis.Rmd")
```

---

## Ticker Universe

| Symbol | Company | Sector |
|--------|---------|--------|
| SPY    | SPDR S&P 500 ETF *(benchmark)* | Broad Market |
| AAPL   | Apple Inc. | Technology |
| MSFT   | Microsoft Corp. | Technology |
| GOOGL  | Alphabet Inc. | Technology |
| NVDA   | NVIDIA Corp. | Technology |
| JPM    | JPMorgan Chase | Financials |
| V      | Visa Inc. | Financials |
| BRK-B  | Berkshire Hathaway | Financials |
| UNH    | UnitedHealth Group | Healthcare |
| JNJ    | Johnson & Johnson | Healthcare |
| XOM    | Exxon Mobil | Energy |
| QQQ    | Invesco NASDAQ-100 ETF | Broad Market |
| GLD    | SPDR Gold Shares | Commodities |

---

## Key Methodology Notes

- **Returns** are computed on **adjusted close prices** (accounts for splits and dividends)
- **Log returns** are used throughout — additive over time, better statistical properties for normality tests
- **CAPM benchmark** is SPY (S&P 500 ETF)
- **Risk-free rate** defaults to 5.0% annualized (update in `03_analysis.R`)
- **VaR** is historical (non-parametric) — no normality assumption required

---

## Database Schema

Five normalized tables: `tickers`, `daily_prices`, `daily_returns`, `risk_metrics`, `correlation_matrix` — plus three reporting views (`v_prices`, `v_returns`, `v_risk_summary`). See `schema.sql` for full DDL.

---

## Skills Demonstrated

- Financial data engineering (ETL from API → relational database)
- Time-series analysis in R with `quantmod` and `xts`
- Applied statistics: regression (CAPM), hypothesis testing, risk metrics
- SQL schema design and query optimization
- Reproducible research with R Markdown
