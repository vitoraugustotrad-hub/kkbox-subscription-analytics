-- =====================================================================
-- q02_cohort_retention.sql
--
-- Business question: out of every 100 people who start paying in a
--                    month, how many are still subscribers 1, 3, 6 and
--                    12 months later? Do recent cohorts retain better?
-- Why it matters:    this is the central health measure of a
--                    subscription business. A monthly churn rate mixes
--                    new and old customers; a cohort separates them.
-- Definitions (METRICS.md):
--   * cohort = month of first transaction, only for users registered
--              since Jan 2015 (before that, the first visible
--              transaction may not be the real first one)
--   * retained in month k = active subscriber on the LAST DAY of month k
--   * active subscriber on day d = the latest transaction up to d still
--              covers d (tx_date <= d < effective_end, and no later
--              transaction exists up to d)
-- Approach:
--   1. active_eom: for each month end, who was an active subscriber
--   2. cohorts:    month of first transaction per eligible user
--   3. matrix:     % of the cohort active at k = 0, 1, 2, 3, 6, 12, 18, 24
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. active_eom: active subscribers at each month end
--    (a table, because later questions reuse it; takes minutes)
--
-- Each tx_daily row "holds" from tx_date until the next transaction and
-- covers the user until effective_end. The month end must fall inside
-- both limits, which guarantees at most one row per user per month.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS active_eom;

CREATE TABLE active_eom AS
WITH month_ends AS (
    SELECT (m + INTERVAL '1 month' - INTERVAL '1 day')::DATE AS month_end
    FROM generate_series(DATE '2015-01-01', DATE '2017-03-01', INTERVAL '1 month') AS m
)
SELECT
    t.msno,
    f.month_end,
    t.is_free,
    t.is_auto_renew
FROM tx_daily t
JOIN month_ends f
  ON  t.tx_date <= f.month_end
  AND f.month_end < t.effective_end
  AND (t.next_tx_date IS NULL OR f.month_end < t.next_tx_date);

CREATE INDEX active_eom_msno_idx ON active_eom (msno);
ANALYZE active_eom;


-- ---------------------------------------------------------------------
-- 2. Check: active subscribers per month end
--    (distinct_users must equal n_rows)
-- ---------------------------------------------------------------------
SELECT
    month_end,
    COUNT(*)                                                           AS n_rows,
    COUNT(DISTINCT msno)                                               AS distinct_users,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_auto_renew) / COUNT(*), 1) AS pct_auto_renew
FROM active_eom
GROUP BY month_end
ORDER BY month_end;


-- ---------------------------------------------------------------------
-- 3. Cohort retention matrix
--    NULL = month k has not happened yet in the data (right-censoring)
--    0    = month k was observed and nobody was active
-- ---------------------------------------------------------------------
WITH cohorts AS (
    SELECT
        t.msno,
        DATE_TRUNC('month', MIN(t.tx_date))::DATE AS cohort_month
    FROM tx_daily t
    JOIN vw_members m USING (msno)
    WHERE m.registered_at >= DATE '2015-01-01'
    GROUP BY t.msno
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohorts
    GROUP BY cohort_month
),
retained AS (
    SELECT
        c.cohort_month,
        (EXTRACT(YEAR  FROM AGE(DATE_TRUNC('month', a.month_end), c.cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', a.month_end), c.cohort_month)))::INT AS k,
        COUNT(*) AS active
    FROM cohorts c
    JOIN active_eom a USING (msno)
    GROUP BY 1, 2
),
pct AS (
    SELECT
        s.cohort_month,
        s.cohort_size,
        r.k,
        ROUND(100.0 * r.active / s.cohort_size, 1) AS pct
    FROM sizes s
    JOIN retained r USING (cohort_month)
)
SELECT
    cohort_month,
    cohort_size,
    CASE WHEN cohort_month + INTERVAL '0 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 0), 0) END  AS m0,
    CASE WHEN cohort_month + INTERVAL '1 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 1), 0) END  AS m1,
    CASE WHEN cohort_month + INTERVAL '2 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 2), 0) END  AS m2,
    CASE WHEN cohort_month + INTERVAL '3 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 3), 0) END  AS m3,
    CASE WHEN cohort_month + INTERVAL '6 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 6), 0) END  AS m6,
    CASE WHEN cohort_month + INTERVAL '12 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 12), 0) END AS m12,
    CASE WHEN cohort_month + INTERVAL '18 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 18), 0) END AS m18,
    CASE WHEN cohort_month + INTERVAL '24 months' <= DATE '2017-03-01'
         THEN COALESCE(MAX(pct) FILTER (WHERE k = 24), 0) END AS m24
FROM pct
GROUP BY cohort_month, cohort_size
ORDER BY cohort_month;
