# =============================================================
# 02_load_db.R
# Load price data into SQLite and compute daily returns
# Author: Zach Wilson | Stock Portfolio Risk & Return Analyzer
# =============================================================

library(tidyverse)
library(DBI)
library(RSQLite)
library(glue)

# -------------------------------------------------------------
# CONNECT / INITIALIZE DATABASE
# -------------------------------------------------------------

DB_PATH <- "data/portfolio.db"

con <- dbConnect(SQLite(), DB_PATH)
message(glue("Connected to: {DB_PATH}"))

# Run schema DDL (idempotent — IF NOT EXISTS throughout)
schema_sql <- readLines("schema.sql") |> paste(collapse = "\n")

# Split on semicolons and execute each statement
statements <- schema_sql |>
  strsplit(";") |>
  unlist() |>
  trimws() |>
  keep(~ nchar(.x) > 10)  # skip empty/whitespace-only

walk(statements, ~ {
  tryCatch(
    dbExecute(con, .x),
    error = function(e) message("Schema stmt warning: ", e$message)
  )
})

message("Schema initialized.")

# -------------------------------------------------------------
# LOAD TICKER METADATA
# -------------------------------------------------------------

ticker_meta <- readRDS("data/ticker_meta.rds")
prices_df   <- readRDS("data/prices_raw.rds")

# Upsert tickers (INSERT OR IGNORE preserves existing IDs)
ticker_insert <- ticker_meta |>
  select(symbol, company, sector, asset_class, benchmark)

dbExecute(con, "DELETE FROM tickers")  # clean reload for dev; remove in prod
dbWriteTable(con, "tickers", ticker_insert, append = TRUE, row.names = FALSE)
message(glue("Loaded {nrow(ticker_insert)} tickers."))

# Fetch back with auto-assigned IDs
tickers_db <- dbGetQuery(con, "SELECT ticker_id, symbol FROM tickers")

# -------------------------------------------------------------
# LOAD DAILY PRICES
# -------------------------------------------------------------

prices_with_id <- prices_df |>
  left_join(tickers_db, by = "symbol") |>
  select(ticker_id, trade_date, open, high, low, close, adj_close, volume) |>
  mutate(trade_date = as.character(trade_date))

# Chunk-write to avoid SQLite parameter limits
chunk_size <- 5000
n_chunks   <- ceiling(nrow(prices_with_id) / chunk_size)

dbExecute(con, "DELETE FROM daily_prices")

walk(seq_len(n_chunks), ~ {
  idx_start <- (.x - 1) * chunk_size + 1
  idx_end   <- min(.x * chunk_size, nrow(prices_with_id))
  chunk     <- prices_with_id[idx_start:idx_end, ]
  dbWriteTable(con, "daily_prices", chunk, append = TRUE, row.names = FALSE)
})

n_prices <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM daily_prices")$n
message(glue("Loaded {n_prices} price rows."))

# -------------------------------------------------------------
# COMPUTE DAILY LOG RETURNS
# -------------------------------------------------------------

# Use adj_close for return computation (handles splits/dividends)
returns_df <- prices_df |>
  arrange(symbol, trade_date) |>
  group_by(symbol) |>
  mutate(
    simple_return = (adj_close - lag(adj_close)) / lag(adj_close),
    log_return    = log(adj_close / lag(adj_close))
  ) |>
  ungroup() |>
  filter(!is.na(log_return)) |>     # drop first row per ticker (no prior price)
  left_join(tickers_db, by = "symbol") |>
  select(ticker_id, trade_date, log_return, simple_return) |>
  mutate(trade_date = as.character(trade_date))

dbExecute(con, "DELETE FROM daily_returns")
dbWriteTable(con, "daily_returns", returns_df, append = TRUE, row.names = FALSE)

n_returns <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM daily_returns")$n
message(glue("Loaded {n_returns} return rows."))

# -------------------------------------------------------------
# QUICK VALIDATION QUERY
# -------------------------------------------------------------

validation <- dbGetQuery(con, "
  SELECT
    t.symbol,
    COUNT(*)            AS trading_days,
    MIN(dp.trade_date)  AS first_date,
    MAX(dp.trade_date)  AS last_date,
    ROUND(AVG(dp.adj_close), 2) AS avg_adj_close
  FROM daily_prices dp
  JOIN tickers t USING (ticker_id)
  GROUP BY t.symbol
  ORDER BY t.symbol
")

print(validation)

dbDisconnect(con)
message("\nDatabase written and connection closed.")
message("Next: run 03_analysis.R")
