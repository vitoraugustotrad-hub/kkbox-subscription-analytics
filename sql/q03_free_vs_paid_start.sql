-- =====================================================================
-- q03_free_vs_paid_start.sql
--
-- Business question: do users who enter through a free promotion
--                    become paying customers? How much is a user who
--                    started free worth over six months, compared with
--                    one who started paying?
-- Why it matters:    q01 and q02 showed promotions bring very large
--                    cohorts that evaporate. What is left to know is
--                    whether what remains pays off.
-- Definitions:
--   * population = users registered since Jan 2015 (same as the
--                  cohorts) whose first transaction was on or before
--                  2016-09-30, so the following 180 days fit in the data
--   * entry type = first transaction free or paid, auto-renew or manual
--   * window     = 180 days from the first transaction
-- Approach:
--   1. first_tx: first tx_daily row per user (DISTINCT ON)
--   2. windowed: what they paid and on how many days, within 180 days
--   3. summary by entry type
-- Reading note: manual payers often buy long plans (90/180/410 days)
--   up front, which pulls revenue into the window and makes a second
--   payment unnecessary. "paid 2+ times" understates their retention.
-- =====================================================================
WITH first_tx AS (
    SELECT DISTINCT ON (t.msno)
        t.msno,
        t.tx_date       AS first_date,
        t.is_free       AS started_free,
        t.is_auto_renew AS started_auto_renew
    FROM tx_daily t
    JOIN vw_members m USING (msno)
    WHERE m.registered_at >= DATE '2015-01-01'
    ORDER BY t.msno, t.tx_date
),
windowed AS (
    SELECT
        p.msno,
        p.started_free,
        p.started_auto_renew,
        SUM(t.amount_paid)                    AS revenue_180d,
        COUNT(*) FILTER (WHERE NOT t.is_free) AS paid_days_180d
    FROM first_tx p
    JOIN tx_daily t
      ON  t.msno = p.msno
      AND t.tx_date < p.first_date + 180
    WHERE p.first_date <= DATE '2016-09-30'
    GROUP BY p.msno, p.started_free, p.started_auto_renew
)
SELECT
    started_free,
    started_auto_renew,
    COUNT(*)                                                                 AS users,
    ROUND(100.0 * COUNT(*) FILTER (WHERE paid_days_180d >= 1) / COUNT(*), 1) AS pct_paid_at_least_once,
    ROUND(100.0 * COUNT(*) FILTER (WHERE paid_days_180d >= 2) / COUNT(*), 1) AS pct_paid_twice_or_more,
    ROUND(AVG(revenue_180d), 0)                                              AS avg_revenue_180d,
    ROUND(AVG(revenue_180d) FILTER (WHERE paid_days_180d >= 1), 0)           AS avg_revenue_of_payers
FROM windowed
GROUP BY started_free, started_auto_renew
ORDER BY started_free, started_auto_renew;
