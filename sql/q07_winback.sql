-- =====================================================================
-- q07_winback.sql
--
-- Business question: of those who leave, how many come back, and how
--                    long does it take?
-- Why it matters:    one in five users has more than one subscription
--                    period. Knowing WHEN they return says until when
--                    win-back spending is worthwhile.
-- Definitions:
--   * exit      = a subscriptions period with status 'churned'
--   * return    = start of the same user's next period
--   * days away = next period start - current period end
--                 (always > 30, by the churn definition)
--   * population = exits up to 2016-03-31, so that a 365-day wait fits
--                  in the data (ends 2017-03-31). Without this cut,
--                  recent leavers would look like "never returned".
-- Split: how the subscription ended (auto-renew or manual on the last
--        transaction; with or without an explicit cancellation).
-- =====================================================================
WITH exits AS (
    SELECT
        s.msno,
        s.end_date,
        s.last_auto_renew,
        s.ended_with_cancel,
        LEAD(s.start_date) OVER (PARTITION BY s.msno ORDER BY s.period_no) - s.end_date AS days_away
    FROM subscriptions s
)
SELECT
    last_auto_renew,
    ended_with_cancel,
    COUNT(*)                                                              AS exits,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_away <= 60)  / COUNT(*), 1) AS pct_back_60d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_away <= 90)  / COUNT(*), 1) AS pct_back_90d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_away <= 180) / COUNT(*), 1) AS pct_back_180d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_away <= 365) / COUNT(*), 1) AS pct_back_365d,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_away)
        FILTER (WHERE days_away <= 365)                                   AS median_days_away
FROM exits
WHERE end_date <= DATE '2016-03-31'
GROUP BY last_auto_renew, ended_with_cancel
ORDER BY last_auto_renew, ended_with_cancel;
