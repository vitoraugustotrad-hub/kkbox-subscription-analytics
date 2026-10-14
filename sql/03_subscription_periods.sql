-- =====================================================================
-- 03_subscription_periods.sql  |  Subscription state and periods
--
-- What this unlocks: "was this user a subscriber on day X?" and "when
--   did they churn?". Without it there is no cohort and no churn rate.
-- Why it is hard: tx is a log of EVENTS (paid, renewed, cancelled), not
--   of PERIODS. Each transaction resets the user's expiry date; a user
--   can renew before expiring, go unpaid for a while and return, or
--   cancel.
-- Approach (gaps-and-islands):
--   1. tx_daily: one row per user per transaction day, with the date of
--      the next transaction (LEAD) and the uncovered gap until it
--   2. subscriptions: groups consecutive transactions into one period
--      while the gap is <= 30 days (the churn definition in METRICS.md);
--      a longer gap closes the period
-- How to run: block by block, in order. Blocks 1 and 2 take minutes.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. tx_daily: the user's state after each transaction day
--
--   * Several transactions on one day (1.28% of user-days) become one
--     row: the LATEST expiry date wins; amounts are summed; the day only
--     counts as a cancellation if ALL its rows are cancellations.
--   * effective_end: until when that transaction covers the user. In a
--     cancellation the expiry can be earlier than the transaction; in
--     that case coverage ends on the cancellation day itself.
--   * gap_days: days without coverage until the next transaction.
--       <= 0  renewed before (or on) expiry
--       > 0   went that many days without a subscription, then returned
--       NULL  no later transaction in the data
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tx_daily;

CREATE TABLE tx_daily AS
WITH per_day AS (
    SELECT
        msno,
        transaction_date            AS tx_date,
        MAX(membership_expire_date) AS expire_date,
        SUM(actual_amount_paid)     AS amount_paid,
        BOOL_AND(is_cancel = 1)     AS is_cancel,
        BOOL_OR(is_auto_renew = 1)  AS is_auto_renew,
        BOOL_AND(is_free)           AS is_free,
        COUNT(*)                    AS n_tx
    FROM tx
    GROUP BY msno, transaction_date
),
with_end AS (
    SELECT *, GREATEST(expire_date, tx_date) AS effective_end
    FROM per_day
)
SELECT
    *,
    LEAD(tx_date) OVER w                 AS next_tx_date,
    LEAD(tx_date) OVER w - effective_end AS gap_days
FROM with_end
WINDOW w AS (PARTITION BY msno ORDER BY tx_date);

CREATE INDEX tx_daily_msno_date_idx ON tx_daily (msno, tx_date);
ANALYZE tx_daily;


-- ---------------------------------------------------------------------
-- 2. subscriptions: continuous subscription periods (30-day window)
--
--   * new_period = 1 on the user's first transaction and whenever they
--     return after more than 30 days without coverage.
--   * The running sum of new_period numbers the periods (period_no).
--   * status:
--       'churned'  the period ended and more than 30 days passed with
--                  no new transaction (observable in the data)
--       'open'     cannot be known yet: the period ends less than 30
--                  days before the end of the data (2017-03-31) or
--                  after it. This is right-censoring.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS subscriptions;

CREATE TABLE subscriptions AS
WITH flagged AS (
    SELECT
        *,
        CASE WHEN LAG(effective_end) OVER w IS NULL
               OR tx_date - LAG(effective_end) OVER w > 30
             THEN 1 ELSE 0 END AS new_period
    FROM tx_daily
    WINDOW w AS (PARTITION BY msno ORDER BY tx_date)
),
numbered AS (
    SELECT
        *,
        SUM(new_period) OVER (PARTITION BY msno ORDER BY tx_date) AS period_no
    FROM flagged
),
periods AS (
    SELECT
        msno,
        period_no,
        MIN(tx_date)                                        AS start_date,
        (ARRAY_AGG(effective_end ORDER BY tx_date DESC))[1] AS end_date,
        (ARRAY_AGG(is_cancel     ORDER BY tx_date DESC))[1] AS ended_with_cancel,
        (ARRAY_AGG(is_auto_renew ORDER BY tx_date DESC))[1] AS last_auto_renew,
        COUNT(*)                                            AS n_tx_days,
        SUM(amount_paid)                                    AS revenue
    FROM numbered
    GROUP BY msno, period_no
)
SELECT
    *,
    end_date - start_date AS duration_days,
    CASE WHEN end_date + 30 <= DATE '2017-03-31' THEN 'churned' ELSE 'open' END AS status
FROM periods;

CREATE INDEX subscriptions_msno_idx ON subscriptions (msno);
ANALYZE subscriptions;


-- ---------------------------------------------------------------------
-- 3. Check A: sizes
--    total_revenue must equal the total in tx (02_base_tables.sql);
--    if it does not, rows were lost along the way.
-- ---------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM tx_daily)                               AS tx_daily_rows,
    (SELECT COUNT(*) FROM subscriptions)                          AS periods,
    (SELECT COUNT(DISTINCT msno) FROM subscriptions)              AS users,
    (SELECT COUNT(*) FROM subscriptions WHERE status = 'churned') AS periods_churned,
    (SELECT COUNT(*) FROM subscriptions WHERE status = 'open')    AS periods_open,
    (SELECT COUNT(*) FROM subscriptions WHERE period_no >= 2)     AS returns,
    (SELECT ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_days)::NUMERIC, 0)
       FROM subscriptions WHERE status = 'churned')               AS median_days_churned,
    (SELECT SUM(revenue) FROM subscriptions)                      AS total_revenue;


-- ---------------------------------------------------------------------
-- 4. Check B: how many periods each user had
-- ---------------------------------------------------------------------
SELECT
    LEAST(n, 5)                                        AS periods_per_user,  -- 5 = 5 or more
    COUNT(*)                                           AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM (SELECT msno, COUNT(*) AS n FROM subscriptions GROUP BY msno) x
GROUP BY 1
ORDER BY 1;
