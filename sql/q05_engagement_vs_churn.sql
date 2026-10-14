-- =====================================================================
-- q05_engagement_vs_churn.sql
--
-- Business question: do low-usage users leave more? Does recent usage
--                    work as an early warning of churn?
-- Why it matters:    if it does, there is room to act BEFORE expiry
--                    (a campaign, a reminder) instead of trying to win
--                    the user back afterwards.
-- The central care (time):
--   Logs are from March 2017 and the churn label (train) is for users
--   expiring in March 2017. Using the whole month would be circular: a
--   user who left on the 10th shows low usage BECAUSE they left. So:
--     * usage = active days from Mar 1 to Mar 7 (fixed 7-day window)
--     * users = only those expiring Mar 8 to Mar 31, i.e. after the
--               window. Measured usage always precedes expiry.
-- Other decisions:
--   * expiry date = effective_end of the last transaction before Mar 1
--     (the user's state at the start of the month)
--   * only users with a members record: the logs only cover that group,
--     so outside it "0 days" would mean "no data", not "no usage"
--   * split by auto-renew, which q01 showed to be the dominant factor.
--     Without the split, usage would take credit for it.
--   * churn = the official label in train (is_churn)
-- =====================================================================
WITH state AS (
    SELECT DISTINCT ON (t.msno)
        t.msno,
        t.effective_end,
        t.is_auto_renew
    FROM tx_daily t
    JOIN train      tr USING (msno)
    JOIN vw_members m  USING (msno)
    WHERE t.tx_date < DATE '2017-03-01'
    ORDER BY t.msno, t.tx_date DESC
),
eligible AS (
    SELECT s.msno, s.is_auto_renew, tr.is_churn
    FROM state s
    JOIN train tr USING (msno)
    WHERE s.effective_end BETWEEN DATE '2017-03-08' AND DATE '2017-03-31'
),
usage AS (
    SELECT msno, COUNT(*) AS active_days
    FROM vw_logs
    WHERE log_date BETWEEN DATE '2017-03-01' AND DATE '2017-03-07'
    GROUP BY msno
),
base AS (
    SELECT
        e.is_auto_renew,
        e.is_churn,
        CASE WHEN COALESCE(u.active_days, 0) = 0 THEN '1) 0 days'
             WHEN u.active_days <= 2             THEN '2) 1-2 days'
             WHEN u.active_days <= 5             THEN '3) 3-5 days'
             ELSE                                     '4) 6-7 days' END AS first_week_usage
    FROM eligible e
    LEFT JOIN usage u USING (msno)
)
SELECT
    is_auto_renew,
    first_week_usage,
    COUNT(*)                                                                     AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY is_auto_renew), 1) AS pct_of_group,
    SUM(is_churn)                                                                AS churners,
    ROUND(100.0 * AVG(is_churn), 2)                                              AS pct_churn
FROM base
GROUP BY is_auto_renew, first_week_usage
ORDER BY is_auto_renew, first_week_usage;


-- ---------------------------------------------------------------------
-- Check: in which month did the subscription of train users expire?
--
-- The analysis above assumes train labels users expiring in Mar 2017.
-- If the premise holds, almost all of them fall in 2017-03-01 here.
-- ---------------------------------------------------------------------
WITH state AS (
    SELECT DISTINCT ON (t.msno)
        t.msno,
        t.effective_end
    FROM tx_daily t
    JOIN train tr USING (msno)
    WHERE t.tx_date < DATE '2017-03-01'
    ORDER BY t.msno, t.tx_date DESC
)
SELECT
    DATE_TRUNC('month', effective_end)::DATE           AS expiry_month,
    COUNT(*)                                           AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM state
GROUP BY 1
ORDER BY users DESC
LIMIT 6;
