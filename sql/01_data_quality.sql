-- =====================================================================
-- 01_data_quality.sql  |  Audit before any analysis
--
-- Goal: find out whether the data can be trusted and which filters and
--       design decisions are needed BEFORE answering business questions.
--       Nothing here changes data; every block is a single SELECT.
-- How to run: one block at a time. Each block returns one result set.
-- The decisions that came out of this audit are applied in
-- 02_base_tables.sql and summarised in the README.
-- =====================================================================


-- ---------------------------------------------------------------------
-- A1. members: nulls and invalid values
-- Why: decides which attributes are usable for segmentation.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                                 AS total,
    COUNT(*) FILTER (WHERE city IS NULL)                                     AS city_null,
    COUNT(*) FILTER (WHERE registered_via IS NULL)                           AS via_null,
    COUNT(*) FILTER (WHERE registration_init_time IS NULL)                   AS registration_null,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gender IS NULL) / COUNT(*), 1)      AS pct_gender_null,
    ROUND(100.0 * COUNT(*) FILTER (WHERE bd <= 0 OR bd > 100) / COUNT(*), 1) AS pct_age_invalid,
    ROUND(100.0 * COUNT(*) FILTER (WHERE city = 1) / COUNT(*), 1)            AS pct_city_1,
    MIN(registration_init_time)                                              AS first_registration,
    MAX(registration_init_time)                                              AS last_registration
FROM members;


-- ---------------------------------------------------------------------
-- A2. members: registration channel
-- Why: registered_via is the only acquisition dimension available.
--      Tiny channels should be grouped as 'other'.
-- ---------------------------------------------------------------------
SELECT
    registered_via,
    COUNT(*)                                             AS members,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct
FROM members
GROUP BY registered_via
ORDER BY members DESC;


-- ---------------------------------------------------------------------
-- A3. members: registrations per year
-- Why: shows which period the registration cohorts refer to.
-- ---------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM registration_init_time)::INT AS year,
    COUNT(*)                                       AS registrations
FROM members
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- B1. train: churn rate and coverage in the other tables
-- Why: any join with members / transactions / logs only holds for the
--      share of train that exists in those tables.
-- Note: written with joins on DISTINCT sets. A first version used
--       EXISTS inside FILTER and did not finish in 10 minutes.
-- ---------------------------------------------------------------------
WITH v1 AS (SELECT DISTINCT msno FROM transactions_v1),
     v2 AS (SELECT DISTINCT msno FROM transactions_v2),
     lg AS (SELECT DISTINCT msno FROM user_logs)
SELECT
    COUNT(*)                                    AS users,
    SUM(t.is_churn)                             AS churners,
    ROUND(100.0 * AVG(t.is_churn), 2)           AS pct_churn,
    ROUND(100.0 * COUNT(m.msno)  / COUNT(*), 1) AS pct_in_members,
    ROUND(100.0 * COUNT(v1.msno) / COUNT(*), 1) AS pct_in_tx_v1,
    ROUND(100.0 * COUNT(v2.msno) / COUNT(*), 1) AS pct_in_tx_v2,
    ROUND(100.0 * COUNT(lg.msno) / COUNT(*), 1) AS pct_in_logs
FROM train t
LEFT JOIN members m USING (msno)
LEFT JOIN v1 USING (msno)
LEFT JOIN v2 USING (msno)
LEFT JOIN lg USING (msno);


-- ---------------------------------------------------------------------
-- B2. train: does churn differ between users with and without a
--     members record?
-- Why: if it does, analysing only users with a members record biases
--      the result.
-- ---------------------------------------------------------------------
SELECT
    (m.msno IS NOT NULL)              AS has_members_record,
    COUNT(*)                          AS users,
    ROUND(100.0 * AVG(t.is_churn), 2) AS pct_churn
FROM train t
LEFT JOIN members m USING (msno)
GROUP BY 1;


-- ---------------------------------------------------------------------
-- C1. transactions: overview of v1 and v2
-- Why: confirms the period of each file and counts suspicious values.
-- ---------------------------------------------------------------------
WITH tx AS (
    SELECT 'v1' AS source, * FROM transactions_v1
    UNION ALL
    SELECT 'v2' AS source, * FROM transactions_v2
)
SELECT
    source,
    COUNT(*)                                                           AS n_rows,
    COUNT(DISTINCT msno)                                               AS users,
    MIN(transaction_date)                                              AS tx_min,
    MAX(transaction_date)                                              AS tx_max,
    MIN(membership_expire_date)                                        AS expire_min,
    MAX(membership_expire_date)                                        AS expire_max,
    COUNT(*) FILTER (WHERE membership_expire_date < transaction_date)  AS expire_before_tx,
    COUNT(*) FILTER (WHERE membership_expire_date > DATE '2018-12-31') AS expire_after_2018,
    COUNT(*) FILTER (WHERE payment_plan_days = 0)                      AS plan_0_days,
    COUNT(*) FILTER (WHERE plan_list_price = 0)                        AS list_price_0,
    COUNT(*) FILTER (WHERE actual_amount_paid = 0)                     AS paid_0,
    COUNT(*) FILTER (WHERE actual_amount_paid < plan_list_price)       AS paid_less_than_list,
    COUNT(*) FILTER (WHERE actual_amount_paid > plan_list_price)       AS paid_more_than_list
FROM tx
GROUP BY source
ORDER BY source;


-- ---------------------------------------------------------------------
-- C2. transactions per month (v1 and v2 side by side)
-- Why: shows where v1 ends, where v2 concentrates and whether the two
--      overlap in time.
-- ---------------------------------------------------------------------
WITH tx AS (
    SELECT 'v1' AS source, transaction_date FROM transactions_v1
    UNION ALL
    SELECT 'v2' AS source, transaction_date FROM transactions_v2
)
SELECT
    DATE_TRUNC('month', transaction_date)::DATE AS month,
    COUNT(*) FILTER (WHERE source = 'v1')       AS rows_v1,
    COUNT(*) FILTER (WHERE source = 'v2')       AS rows_v2
FROM tx
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- C3. transactions: exact duplicates inside each file
-- Why: a fully repeated row double-counts revenue and renewals.
-- ---------------------------------------------------------------------
WITH tx AS (
    SELECT 'v1' AS source, * FROM transactions_v1
    UNION ALL
    SELECT 'v2' AS source, * FROM transactions_v2
),
grouped AS (
    SELECT source, COUNT(*) AS n
    FROM tx
    GROUP BY source, msno, payment_method_id, payment_plan_days, plan_list_price,
             actual_amount_paid, is_auto_renew, transaction_date,
             membership_expire_date, is_cancel
)
SELECT
    source,
    SUM(n)            AS n_rows,
    COUNT(*)          AS distinct_rows,
    SUM(n) - COUNT(*) AS duplicate_rows
FROM grouped
GROUP BY source
ORDER BY source;


-- ---------------------------------------------------------------------
-- C4. transactions: identical rows across v1 and v2
-- Why: decides how to combine the two files.
-- ---------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM transactions_v2) d)          AS v2_distinct_rows,
    (SELECT COUNT(*) FROM (
        SELECT * FROM transactions_v2
        INTERSECT
        SELECT * FROM transactions_v1) i)                                      AS identical_in_both,
    (SELECT COUNT(DISTINCT msno) FROM transactions_v2 v2
      WHERE EXISTS (SELECT 1 FROM transactions_v1 v1 WHERE v1.msno = v2.msno)) AS users_in_both;


-- ---------------------------------------------------------------------
-- C5. transactions: do the pre-March-2017 rows in v2 repeat v1
--     transactions (same user + date) or are they new?
-- Why: C4 found no identical rows, but v2 holds 361k rows dated before
--      March 2017. If they shared user + date with v1 they would be a
--      second version of the same transactions, and one would have to
--      be chosen. If not, the files are complementary and can be stacked.
-- ---------------------------------------------------------------------
WITH old_v2 AS (
    SELECT msno, transaction_date
    FROM transactions_v2
    WHERE transaction_date < DATE '2017-03-01'
),
v1_keys AS (
    SELECT DISTINCT v1.msno, v1.transaction_date
    FROM transactions_v1 v1
    WHERE v1.msno IN (SELECT msno FROM old_v2)
),
v1_users AS (SELECT DISTINCT msno FROM v1_keys)
SELECT
    COUNT(*)      AS v2_rows_before_mar17,
    COUNT(k.msno) AS same_user_and_date_in_v1,
    COUNT(u.msno) AS user_exists_in_v1
FROM old_v2 a
LEFT JOIN v1_keys  k ON k.msno = a.msno AND k.transaction_date = a.transaction_date
LEFT JOIN v1_users u ON u.msno = a.msno;


-- ---------------------------------------------------------------------
-- C6. transactions: is_cancel x is_auto_renew
-- Why: cancelling auto-renewal is NOT the definition of churn. This
--      cross-tab is the starting point for that discussion.
-- ---------------------------------------------------------------------
WITH tx AS (
    SELECT 'v1' AS source, is_auto_renew, is_cancel FROM transactions_v1
    UNION ALL
    SELECT 'v2' AS source, is_auto_renew, is_cancel FROM transactions_v2
)
SELECT
    source, is_auto_renew, is_cancel,
    COUNT(*)                                                              AS n_rows,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY source), 2) AS pct
FROM tx
GROUP BY source, is_auto_renew, is_cancel
ORDER BY source, is_auto_renew, is_cancel;


-- ---------------------------------------------------------------------
-- C7. transactions: plan length
-- Why: is "monthly" nearly everything? Long plans change what "renewal"
--      means.
-- ---------------------------------------------------------------------
WITH tx AS (
    SELECT payment_plan_days FROM transactions_v1
    UNION ALL
    SELECT payment_plan_days FROM transactions_v2
)
SELECT
    payment_plan_days,
    COUNT(*)                                           AS n_rows,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM tx
GROUP BY payment_plan_days
ORDER BY n_rows DESC
LIMIT 15;


-- ---------------------------------------------------------------------
-- C8. transactions: several transactions by one user on the same day
-- Why: this is what complicates building subscription periods (which
--      row counts?). The size of the problem needs to be known.
-- ---------------------------------------------------------------------
WITH tx AS (
    SELECT msno, transaction_date FROM transactions_v1
    UNION ALL
    SELECT msno, transaction_date FROM transactions_v2
),
per_day AS (
    SELECT msno, transaction_date, COUNT(*) AS n
    FROM tx
    GROUP BY msno, transaction_date
)
SELECT
    COUNT(*)                                                   AS user_days,
    COUNT(*) FILTER (WHERE n > 1)                              AS with_more_than_one,
    ROUND(100.0 * COUNT(*) FILTER (WHERE n > 1) / COUNT(*), 2) AS pct,
    MAX(n)                                                     AS max_on_one_day
FROM per_day;


-- ---------------------------------------------------------------------
-- C9. transactions: paying users with no members record
-- Why: measures how much of the paying base is left out of analyses by
--      channel.
-- ---------------------------------------------------------------------
WITH payers AS (
    SELECT msno FROM transactions_v1
    UNION
    SELECT msno FROM transactions_v2
)
SELECT
    COUNT(*)                                                            AS payers,
    COUNT(*) FILTER (WHERE m.msno IS NULL)                              AS no_members_record,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m.msno IS NULL) / COUNT(*), 1) AS pct_no_members_record
FROM payers p
LEFT JOIN members m USING (msno);


-- ---------------------------------------------------------------------
-- C10. transactions (v1): are the zero values concentrated in a period?
-- Why: if they are, it is a logging failure of that period rather than
--      a real free or zero-length plan.
-- ---------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', transaction_date)::DATE                        AS month,
    COUNT(*)                                                           AS n_rows,
    COUNT(*) FILTER (WHERE payment_plan_days = 0)                      AS plan_0_days,
    COUNT(*) FILTER (WHERE plan_list_price = 0)                        AS list_price_0,
    COUNT(*) FILTER (WHERE actual_amount_paid = 0)                     AS paid_0,
    COUNT(*) FILTER (WHERE membership_expire_date < transaction_date)  AS expire_before_tx,
    COUNT(*) FILTER (WHERE membership_expire_date = DATE '1970-01-01') AS expire_1970
FROM transactions_v1
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- C11. transactions (v1): is "expiry before transaction" a cancellation?
-- Why: decides whether those rows are legitimate (a cancellation that
--      shortens the expiry date) or anomalies to drop.
-- ---------------------------------------------------------------------
SELECT
    is_cancel,
    COUNT(*)                                                          AS n_rows,
    COUNT(*) FILTER (WHERE membership_expire_date < transaction_date) AS expire_before_tx,
    ROUND(100.0 * COUNT(*) FILTER (WHERE membership_expire_date < transaction_date)
          / COUNT(*), 2)                                              AS pct
FROM transactions_v1
GROUP BY is_cancel
ORDER BY is_cancel;


-- ---------------------------------------------------------------------
-- D1. user_logs: overview and impossible values
-- Why: total_secs has known outliers (negative or above 24h = 86,400s)
--      that wreck any average.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                   AS n_rows,
    COUNT(DISTINCT msno)                       AS users,
    MIN(date)                                  AS day_min,
    MAX(date)                                  AS day_max,
    COUNT(DISTINCT date)                       AS distinct_days,
    COUNT(*) FILTER (WHERE total_secs < 0)     AS secs_negative,
    COUNT(*) FILTER (WHERE total_secs > 86400) AS secs_over_24h,
    COUNT(*) FILTER (WHERE total_secs = 0)     AS secs_zero,
    COUNT(*) FILTER (WHERE num_25 + num_50 + num_75 + num_985 + num_100 = 0)       AS no_songs,
    COUNT(*) FILTER (WHERE num_unq > num_25 + num_50 + num_75 + num_985 + num_100) AS unique_over_total,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY total_secs)::NUMERIC, 0)    AS secs_median,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_secs)::NUMERIC, 0)    AS secs_p99
FROM user_logs;


-- ---------------------------------------------------------------------
-- D2. user_logs: more than one row per user per day?
-- Why: if it is always one row per user/day, COUNT(*) per day is DAU.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                      AS user_days,
    COUNT(*) FILTER (WHERE n > 1) AS with_more_than_one_row
FROM (
    SELECT msno, date, COUNT(*) AS n
    FROM user_logs
    GROUP BY msno, date
) x;


-- ---------------------------------------------------------------------
-- D3. user_logs: active users per day
-- Why: a sharp one-day drop means a collection failure, not a drop in
--      usage. Also shows whether the month is complete.
-- ---------------------------------------------------------------------
SELECT
    date,
    TO_CHAR(date, 'Dy')  AS weekday,
    COUNT(DISTINCT msno) AS active_users
FROM user_logs
GROUP BY date
ORDER BY date;


-- ---------------------------------------------------------------------
-- D4. user_logs: do logged users exist in the other tables?
-- Why: tells for which population engagement can be joined to churn
--      (train) and to channel (members).
-- ---------------------------------------------------------------------
WITH active AS (SELECT DISTINCT msno FROM user_logs),
     tr     AS (SELECT msno FROM train),
     mb     AS (SELECT msno FROM members)
SELECT
    COUNT(*)                                    AS users_in_logs,
    ROUND(100.0 * COUNT(tr.msno) / COUNT(*), 1) AS pct_in_train,
    ROUND(100.0 * COUNT(mb.msno) / COUNT(*), 1) AS pct_in_members
FROM active a
LEFT JOIN tr USING (msno)
LEFT JOIN mb USING (msno);
