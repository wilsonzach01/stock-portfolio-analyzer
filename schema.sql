-- ============================================================
-- Stock Portfolio Risk & Return Analyzer
-- SQLite Schema
-- Author: Zach Wilson
-- ============================================================

-- ------------------------------------------------------------
-- 1. TICKERS — master list of securities in the portfolio
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tickers (
    ticker_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol      TEXT    NOT NULL UNIQUE,       -- e.g. 'AAPL'
    company     TEXT,                          -- e.g. 'Apple Inc.'
    sector      TEXT,                          -- e.g. 'Technology'
    asset_class TEXT    DEFAULT 'Equity',      -- Equity / ETF / Index
    benchmark   INTEGER DEFAULT 0,             -- 1 = benchmark (e.g. SPY)
    added_at    TEXT    DEFAULT (datetime('now'))
);

-- ------------------------------------------------------------
-- 2. DAILY_PRICES — raw OHLCV data from Yahoo Finance
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_prices (
    price_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    ticker_id   INTEGER NOT NULL REFERENCES tickers(ticker_id),
    trade_date  TEXT    NOT NULL,   -- ISO-8601: 'YYYY-MM-DD'
    open        REAL,
    high        REAL,
    low         REAL,
    close       REAL    NOT NULL,
    adj_close   REAL    NOT NULL,   -- dividend/split adjusted — use for returns
    volume      INTEGER,
    UNIQUE(ticker_id, trade_date)
);

CREATE INDEX IF NOT EXISTS idx_prices_ticker_date
    ON daily_prices(ticker_id, trade_date);

-- ------------------------------------------------------------
-- 3. DAILY_RETURNS — computed log returns (filled by R)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_returns (
    return_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    ticker_id       INTEGER NOT NULL REFERENCES tickers(ticker_id),
    trade_date      TEXT    NOT NULL,
    log_return      REAL,           -- ln(P_t / P_t-1)
    simple_return   REAL,           -- (P_t - P_t-1) / P_t-1
    UNIQUE(ticker_id, trade_date)
);

CREATE INDEX IF NOT EXISTS idx_returns_ticker_date
    ON daily_returns(ticker_id, trade_date);

-- ------------------------------------------------------------
-- 4. RISK_METRICS — rolling & full-period stats (filled by R)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS risk_metrics (
    metric_id           INTEGER PRIMARY KEY AUTOINCREMENT,
    ticker_id           INTEGER NOT NULL REFERENCES tickers(ticker_id),
    period_start        TEXT    NOT NULL,
    period_end          TEXT    NOT NULL,
    annualized_return   REAL,   -- geometric mean annualized
    annualized_vol      REAL,   -- std dev of daily log returns * sqrt(252)
    sharpe_ratio        REAL,   -- (ann_return - risk_free) / ann_vol
    max_drawdown        REAL,   -- peak-to-trough max loss
    beta                REAL,   -- vs. benchmark (SPY)
    alpha               REAL,   -- Jensen's alpha
    r_squared           REAL,   -- R² from benchmark regression
    var_95              REAL,   -- 1-day 95% historical VaR
    cvar_95             REAL,   -- Conditional VaR (Expected Shortfall)
    computed_at         TEXT    DEFAULT (datetime('now')),
    UNIQUE(ticker_id, period_start, period_end)
);

-- ------------------------------------------------------------
-- 5. CORRELATION_MATRIX — pairwise correlations (filled by R)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS correlation_matrix (
    corr_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    ticker_id_a     INTEGER NOT NULL REFERENCES tickers(ticker_id),
    ticker_id_b     INTEGER NOT NULL REFERENCES tickers(ticker_id),
    period_start    TEXT    NOT NULL,
    period_end      TEXT    NOT NULL,
    pearson_corr    REAL,
    computed_at     TEXT    DEFAULT (datetime('now')),
    UNIQUE(ticker_id_a, ticker_id_b, period_start, period_end)
);

-- ------------------------------------------------------------
-- Useful views for reporting
-- ------------------------------------------------------------

-- Prices joined with ticker symbols (easier to query in R)
CREATE VIEW IF NOT EXISTS v_prices AS
SELECT
    t.symbol,
    t.company,
    t.sector,
    t.benchmark,
    dp.trade_date,
    dp.open,
    dp.high,
    dp.low,
    dp.close,
    dp.adj_close,
    dp.volume
FROM daily_prices dp
JOIN tickers t USING (ticker_id);

-- Returns joined with symbols
CREATE VIEW IF NOT EXISTS v_returns AS
SELECT
    t.symbol,
    t.sector,
    t.benchmark,
    dr.trade_date,
    dr.log_return,
    dr.simple_return
FROM daily_returns dr
JOIN tickers t USING (ticker_id);

-- Risk summary for dashboard
CREATE VIEW IF NOT EXISTS v_risk_summary AS
SELECT
    t.symbol,
    t.company,
    t.sector,
    rm.period_start,
    rm.period_end,
    ROUND(rm.annualized_return * 100, 2)  AS ann_return_pct,
    ROUND(rm.annualized_vol    * 100, 2)  AS ann_vol_pct,
    ROUND(rm.sharpe_ratio,              3) AS sharpe,
    ROUND(rm.max_drawdown      * 100, 2)  AS max_drawdown_pct,
    ROUND(rm.beta,                      3) AS beta,
    ROUND(rm.alpha             * 100, 2)  AS alpha_pct,
    ROUND(rm.var_95            * 100, 2)  AS var_95_pct,
    ROUND(rm.cvar_95           * 100, 2)  AS cvar_95_pct
FROM risk_metrics rm
JOIN tickers t USING (ticker_id);