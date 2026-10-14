-- =====================================================================
-- q04_engagement.sql
--
-- Business question: how often do users use the app? Is the base one
--                    homogeneous group, or a mix of daily users and
--                    people who barely use it?
-- Why it matters:    a DAU/MAU ratio looks great or poor on its own,
--                    but an average hides the distribution. If there is
--                    a large low-usage group, that is where churn risk
--                    would sit.
-- Period:            March 2017 (the only month with usage logs).
-- Definitions (METRICS.md):
--   * active day  = one row in vw_logs
--   * sensitivity = a day with at least one song played to the end
-- =====================================================================


-- ---------------------------------------------------------------------
-- A. Stickiness under both definitions of "active"
-- ---------------------------------------------------------------------
SELECT
    COUNT(DISTINCT msno)                                          AS mau,
    ROUND(COUNT(*) / 31.0, 0)                                     AS avg_dau,
    ROUND(100.0 * (COUNT(*) / 31.0) / COUNT(DISTINCT msno), 1)    AS stickiness_pct,
    COUNT(DISTINCT msno) FILTER (WHERE songs_completed >= 1)      AS mau_strict,
    ROUND(COUNT(*) FILTER (WHERE songs_completed >= 1) / 31.0, 0) AS avg_dau_strict,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE songs_completed >= 1) / 31.0)
          / COUNT(DISTINCT msno) FILTER (WHERE songs_completed >= 1), 1) AS stickiness_strict_pct
FROM vw_logs;


-- ---------------------------------------------------------------------
-- B. Distribution of active days in the month
--
--   * pct_of_users:        share of the base in each band
--   * pct_of_usage_days:   share of all usage (user-days) from that band
--   * min_per_active_day:  intensity on the days they do use it (median)
--   * pct_subscribers:     share with an active subscription on
--                          2017-03-31 (answers whether the logs include
--                          non-subscribers)
-- ---------------------------------------------------------------------
WITH per_user AS (
    SELECT
        msno,
        COUNT(*)                   AS active_days,
        SUM(total_secs) / COUNT(*) AS secs_per_active_day
    FROM vw_logs
    GROUP BY msno
),
banded AS (
    SELECT
        p.*,
        CASE WHEN active_days = 1   THEN '1) 1 day'
             WHEN active_days <= 5  THEN '2) 2-5 days'
             WHEN active_days <= 10 THEN '3) 6-10 days'
             WHEN active_days <= 20 THEN '4) 11-20 days'
             WHEN active_days <= 27 THEN '5) 21-27 days'
             ELSE                        '6) 28-31 days' END AS band,
        (a.msno IS NOT NULL) AS is_subscriber
    FROM per_user p
    LEFT JOIN active_eom a
           ON a.msno = p.msno AND a.month_end = DATE '2017-03-31'
)
SELECT
    band,
    COUNT(*)                                                           AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                 AS pct_of_users,
    ROUND(100.0 * SUM(active_days) / SUM(SUM(active_days)) OVER (), 1) AS pct_of_usage_days,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY secs_per_active_day) / 60)::NUMERIC, 0)
                                                                       AS min_per_active_day,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_subscriber) / COUNT(*), 1) AS pct_subscribers
FROM banded
GROUP BY band
ORDER BY band;
