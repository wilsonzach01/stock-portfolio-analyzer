# =============================================================
# 01_pull_data.R
# Pull historical OHLCV data from Yahoo Finance via quantmod
# Author: Zach Wilson | Stock Portfolio Risk & Return Analyzer
# =============================================================

library(quantmod)
library(tidyverse)
library(lubridate)

# -------------------------------------------------------------
# CONFIG — edit your ticker universe here
# -------------------------------------------------------------

TICKERS <- tibble::tribble(
  ~symbol,  ~company,                        ~sector,              ~asset_class, ~benchmark,
  "SPY",    "SPDR S&P 500 ETF",              "Broad Market",       "ETF",        1L,
  "AAPL",   "Apple Inc.",                    "Technology",         "Equity",     0L,
  "MSFT",   "Microsoft Corp.",               "Technology",         "Equity",     0L,
  "GOOGL",  "Alphabet Inc.",                 "Technology",         "Equity",     0L,
  "JPM",    "JPMorgan Chase & Co.",          "Financials",         "Equity",     0L,
  "V",      "Visa Inc.",                     "Financials",         "Equity",     0L,
  "UNH",    "UnitedHealth Group Inc.",       "Healthcare",         "Equity",     0L,
  "JNJ",    "Johnson & Johnson",             "Healthcare",         "Equity",     0L,
  "XOM",    "Exxon Mobil Corp.",             "Energy",             "Equity",     0L,
  "BRK-B",  "Berkshire Hathaway Inc.",       "Financials",         "Equity",     0L,
  "NVDA",   "NVIDIA Corp.",                  "Technology",         "Equity",     0L,
  "QQQ",    "Invesco QQQ ETF (NASDAQ-100)",  "Broad Market",       "ETF",        0L,
  "GLD",    "SPDR Gold Shares",              "Commodities",        "ETF",        0L
)

START_DATE  <- "2020-01-01"
END_DATE    <- Sys.Date()

# -------------------------------------------------------------
# PULL DATA from Yahoo Finance
# Returns a named list of xts objects
# -------------------------------------------------------------

pull_yahoo_data <- function(tickers, start, end) {
  
  results <- list()
  failed  <- character(0)
  
  for (sym in tickers$symbol) {
    message(glue::glue("Pulling {sym}..."))
    
    tryCatch({
      # quantmod can't handle dashes in auto.assign object names;
      # use auto.assign=FALSE and assign manually instead
      xts_obj <- getSymbols(
        sym,
        src         = "yahoo",
        from        = start,
        to          = end,
        auto.assign = FALSE,   # ← key change: return the object directly
        warnings    = FALSE
      )
      
      results[[sym]] <- xts_obj
      
    }, error = function(e) {
      warning(glue::glue("Failed to pull {sym}: {e$message}"))
      failed <<- c(failed, sym)
    })
    
    Sys.sleep(0.3)
}
  
  if (length(failed) > 0) {
    message("\nFailed tickers: ", paste(failed, collapse = ", "))
  }
  
  return(results)
}

# -------------------------------------------------------------
# FLATTEN to a tidy long-format data frame
# -------------------------------------------------------------

xts_to_long <- function(xts_list, ticker_meta) {
  
  map_dfr(names(xts_list), function(sym) {
    
    xts_obj <- xts_list[[sym]]
    
    # Standardize column names (quantmod uses TICKER.Open etc.)
    colnames(xts_obj) <- c("open", "high", "low", "close", "volume", "adj_close")
    
    as.data.frame(xts_obj) |>
      rownames_to_column("trade_date") |>
      mutate(
        symbol     = sym,
        trade_date = as.Date(trade_date)
      ) |>
      select(symbol, trade_date, open, high, low, close, adj_close, volume)
    
  }) |>
    left_join(ticker_meta |> select(symbol, sector, benchmark), by = "symbol") |>
    arrange(symbol, trade_date)
}

# -------------------------------------------------------------
# RUN
# -------------------------------------------------------------

message("=== Pulling stock data from Yahoo Finance ===")
message(glue::glue("Date range: {START_DATE} to {END_DATE}"))
message(glue::glue("Tickers: {nrow(TICKERS)}"))

raw_xts   <- pull_yahoo_data(TICKERS, START_DATE, END_DATE)
prices_df <- xts_to_long(raw_xts, TICKERS)


# Quick sanity check — any NAs in adj_close?
na_check <- prices_df |>
  filter(is.na(adj_close)) |>
  count(symbol)

if (nrow(na_check) > 0) {
  warning("NAs found in adj_close:")
  print(na_check)
}

# Save raw data as RDS for downstream scripts
saveRDS(prices_df, "data/prices_raw.rds")
saveRDS(TICKERS,   "data/ticker_meta.rds")

message("\nSaved: data/prices_raw.rds, data/ticker_meta.rds")
message("Next: run 02_load_db.R")

