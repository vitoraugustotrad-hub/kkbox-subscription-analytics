-- =====================================================================
-- q01_churn_trend.sql
--
-- Business question: how has churn evolved, what explains its spikes,
--                    and how much does the number depend on the
--                    definition?
-- Why it matters:    churn is the headline metric of a subscription
--                    business; before acting on it, it must be clear
--                    what moves it and how fragile the number is.
-- Unit:              each row of tx_daily is one "expiry". It churns
--                    when no transaction follows within N days of
--                    effective_end (gap_days IS NULL or > N).
-- =====================================================================


-- ---------------------------------------------------------------------
-- A. Monthly churn (30-day window) and cancellation rate
--
-- Only expiries up to 2017-03-01 are included so the 30-day window is
-- fully observable (data ends 2017-03-31).
-- Reading notes:
--   * 2015-01 is the left edge of the data (few expiries, mostly
--     cancellations) and 2017-03 holds a single day. Both are excluded
--     from the published series.
--   * churned is the numerator of pct_churn_30d, kept so the rate can
--     be checked (Mar 2016 and Nov 2016 round to the same 16.93%).
-- ---------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', effective_end)::DATE                       AS month,
    COUNT(*)                                                       AS expiries,
    COUNT(*) FILTER (WHERE gap_days IS NULL OR gap_days > 30)      AS churned,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gap_days IS NULL OR gap_days > 30)
          / COUNT(*), 2)                                           AS pct_churn_30d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_cancel) / COUNT(*), 2) AS pct_cancellation
FROM tx_daily
WHERE effective_end <= DATE '2017-03-01'
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- B. What explains the spikes: churn by transaction type
--
-- Part A shows four months far above the baseline (2015-04, 2015-06,
-- 2016-03, 2016-11). Hypothesis: free promotions expiring. This splits
-- expiries into spike vs normal months and, inside each, by free vs
-- paid and auto-renew vs manual. Cancellations are excluded to look
-- only at users who simply did not renew.
-- ---------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', effective_end)::DATE IN
        (DATE '2015-04-01', DATE '2015-06-01', DATE '2016-03-01', DATE '2016-11-01') AS spike_month,
    is_free,
    is_auto_renew,
    COUNT(*)                                                         AS expiries,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY
        DATE_TRUNC('month', effective_end)::DATE IN
        (DATE '2015-04-01', DATE '2015-06-01', DATE '2016-03-01', DATE '2016-11-01')), 1) AS pct_of_expiries,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gap_days IS NULL OR gap_days > 30)
          / COUNT(*), 2)                                             AS pct_churn_30d
FROM tx_daily
WHERE effective_end >= DATE '2015-02-01'
  AND effective_end <  DATE '2017-01-01'
  AND NOT is_cancel
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;


-- ---------------------------------------------------------------------
-- C. Sensitivity: churn under 15-, 30- and 60-day windows
--
-- Only expiries up to 2017-01-30, so that even the 60-day window is
-- fully observable. 2017 therefore contains January only.
-- ---------------------------------------------------------------------
SELECT
    DATE_TRUNC('year', effective_end)::DATE AS year,
    COUNT(*)                                AS expiries,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gap_days IS NULL OR gap_days > 15) / COUNT(*), 2) AS pct_churn_15d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gap_days IS NULL OR gap_days > 30) / COUNT(*), 2) AS pct_churn_30d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gap_days IS NULL OR gap_days > 60) / COUNT(*), 2) AS pct_churn_60d
FROM tx_daily
WHERE effective_end <= DATE '2017-01-30'
GROUP BY 1
ORDER BY 1;
