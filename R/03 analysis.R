# =============================================================
# 03_analysis.R
# Core statistical analysis: risk metrics, CAPM regression,
# correlation matrix, VaR/CVaR
# Author: Zach Wilson | Stock Portfolio Risk & Return Analyzer
# =============================================================

library(tidyverse)
library(DBI)
library(RSQLite)
library(glue)
library(broom)

RISK_FREE_RATE <- 0.05   # annualized; update to current T-bill rate
TRADING_DAYS   <- 252

DB_PATH <- "data/portfolio.db"
con     <- dbConnect(SQLite(), DB_PATH)

# -------------------------------------------------------------
# LOAD RETURNS FROM DB
# -------------------------------------------------------------

returns_wide <- dbGetQuery(con, "
  SELECT symbol, trade_date, log_return
  FROM v_returns
  ORDER BY trade_date
") |>
  pivot_wider(names_from = symbol, values_from = log_return) |>
  column_to_rownames("trade_date")

# Separate benchmark (SPY) from portfolio
spy_returns      <- returns_wide[["SPY"]]
portfolio_syms   <- setdiff(colnames(returns_wide), "SPY")
portfolio_returns <- returns_wide[, portfolio_syms]

# Align on complete cases (common trading dates)
complete_idx      <- complete.cases(returns_wide)
spy_clean         <- spy_returns[complete_idx]
portfolio_clean   <- portfolio_returns[complete_idx, ]

message(glue("Analysis window: {sum(complete_idx)} overlapping trading days"))

# -------------------------------------------------------------
# HELPER FUNCTIONS
# -------------------------------------------------------------

annualized_return <- function(log_rets, n = TRADING_DAYS) {
  exp(mean(log_rets, na.rm = TRUE) * n) - 1
}

annualized_vol <- function(log_rets, n = TRADING_DAYS) {
  sd(log_rets, na.rm = TRUE) * sqrt(n)
}

sharpe_ratio <- function(log_rets, rf = RISK_FREE_RATE, n = TRADING_DAYS) {
  (annualized_return(log_rets, n) - rf) / annualized_vol(log_rets, n)
}

max_drawdown <- function(log_rets) {
  prices     <- exp(cumsum(log_rets))
  roll_max   <- cummax(prices)
  drawdowns  <- (prices - roll_max) / roll_max
  min(drawdowns, na.rm = TRUE)
}

historical_var <- function(log_rets, conf = 0.95) {
  quantile(log_rets, 1 - conf, na.rm = TRUE)
}

historical_cvar <- function(log_rets, conf = 0.95) {
  var_threshold <- historical_var(log_rets, conf)
  mean(log_rets[log_rets <= var_threshold], na.rm = TRUE)
}

capm_regression <- function(asset_rets, benchmark_rets) {
  rf_daily <- RISK_FREE_RATE / TRADING_DAYS
  excess_asset  <- asset_rets     - rf_daily
  excess_market <- benchmark_rets - rf_daily
  
  model  <- lm(excess_asset ~ excess_market)
  tidy_m <- broom::tidy(model)
  glance_m <- broom::glance(model)
  
  list(
    alpha     = tidy_m$estimate[1],
    beta      = tidy_m$estimate[2],
    r_squared = glance_m$r.squared,
    p_alpha   = tidy_m$p.value[1],
    p_beta    = tidy_m$p.value[2]
  )
}

# -------------------------------------------------------------
# COMPUTE RISK METRICS PER TICKER
# -------------------------------------------------------------

tickers_db <- dbGetQuery(con, "SELECT ticker_id, symbol FROM tickers WHERE benchmark = 0")

period_start <- min(rownames(returns_wide)[complete_idx])
period_end   <- max(rownames(returns_wide)[complete_idx])

risk_results <- map_dfr(portfolio_syms, function(sym) {
  
  rets <- portfolio_clean[[sym]]
  
  # Skip if insufficient data
  if (sum(!is.na(rets)) < 60) {
    warning(glue("Skipping {sym}: insufficient data"))
    return(NULL)
  }
  
  capm    <- capm_regression(rets, spy_clean)
  
  tibble(
    symbol            = sym,
    period_start      = period_start,
    period_end        = period_end,
    annualized_return = annualized_return(rets),
    annualized_vol    = annualized_vol(rets),
    sharpe_ratio      = sharpe_ratio(rets),
    max_drawdown      = max_drawdown(rets),
    beta              = capm$beta,
    alpha             = capm$alpha * TRADING_DAYS,  # annualize alpha
    r_squared         = capm$r_squared,
    var_95            = historical_var(rets),
    cvar_95           = historical_cvar(rets)
  )
})

message(glue("Computed risk metrics for {nrow(risk_results)} tickers."))
print(risk_results |> select(symbol, annualized_return, annualized_vol, sharpe_ratio, beta, max_drawdown))

# Write to DB
risk_db <- risk_results |>
  left_join(tickers_db, by = "symbol") |>
  select(ticker_id, period_start, period_end,
         annualized_return, annualized_vol, sharpe_ratio,
         max_drawdown, beta, alpha, r_squared, var_95, cvar_95)

dbExecute(con, "DELETE FROM risk_metrics")
dbWriteTable(con, "risk_metrics", risk_db, append = TRUE, row.names = FALSE)
message("Risk metrics written to DB.")

# -------------------------------------------------------------
# CORRELATION MATRIX
# -------------------------------------------------------------

cor_matrix <- cor(portfolio_clean, use = "pairwise.complete.obs")

# Convert to long format for DB storage
cor_long <- cor_matrix |>
  as.data.frame() |>
  rownames_to_column("symbol_a") |>
  pivot_longer(-symbol_a, names_to = "symbol_b", values_to = "pearson_corr") |>
  filter(symbol_a < symbol_b)   # store lower triangle only

cor_db <- cor_long |>
  left_join(tickers_db |> rename(ticker_id_a = ticker_id, symbol_a = symbol), by = "symbol_a") |>
  left_join(tickers_db |> rename(ticker_id_b = ticker_id, symbol_b = symbol), by = "symbol_b") |>
  mutate(period_start = period_start, period_end = period_end) |>
  select(ticker_id_a, ticker_id_b, period_start, period_end, pearson_corr)

dbExecute(con, "DELETE FROM correlation_matrix")
dbWriteTable(con, "correlation_matrix", cor_db, append = TRUE, row.names = FALSE)
message(glue("Correlation matrix written: {nrow(cor_db)} pairs."))

# -------------------------------------------------------------
# HYPOTHESIS TESTS — Is each ticker's mean return > 0?
# (One-sample t-test; useful for the Rmd report)
# -------------------------------------------------------------

hypothesis_tests <- map_dfr(portfolio_syms, function(sym) {
  rets <- portfolio_clean[[sym]]
  rets <- rets[!is.na(rets)]
  
  t_result <- t.test(rets, mu = 0, alternative = "greater")
  
  tibble(
    symbol    = sym,
    mean_log_return = mean(rets),
    t_stat    = t_result$statistic,
    p_value   = t_result$p.value,
    reject_h0 = t_result$p.value < 0.05
  )
})

message("\nHypothesis tests (H0: mean daily log return = 0):")
print(hypothesis_tests)

# Save analysis outputs
saveRDS(risk_results,      "data/risk_metrics.rds")
saveRDS(cor_matrix,        "data/correlation_matrix.rds")
saveRDS(hypothesis_tests,  "data/hypothesis_tests.rds")
saveRDS(returns_wide,      "data/returns_wide.rds")

dbDisconnect(con)
message("\nAnalysis complete. Next: knit reports/portfolio_analysis.Rmd")

