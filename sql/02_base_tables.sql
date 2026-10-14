-- =====================================================================
-- 02_base_tables.sql  |  Clean base for every analysis
--
-- Applies, once, the decisions that came out of 01_data_quality.sql.
-- Every business question reads from here, never from the raw tables.
--
-- Why a TABLE and not a VIEW for transactions: about 23 million rows
-- and an expensive de-duplication. A view would redo that work on every
-- query; the table is built once and indexed.
-- How to run: block by block, in order. Block 1 takes a few minutes.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. tx: v1 + v2 transactions, de-duplicated and filtered
--
-- Decisions (with the evidence from 01_data_quality.sql):
--   * v1 and v2 are complementary: no identical row across them (C4),
--     and only 2.8% of the old v2 rows share user + date with v1 (C5).
--     Stacking them is correct.
--   * UNION (not UNION ALL) removes the 3,339 exact duplicates in v1 (C3).
--   * Dropped: expiry on 1970-01-01 (invalid date).
--   * Dropped: expiry before the transaction when it is NOT a
--     cancellation. 95.8% of "expiry before transaction" rows are
--     cancellations, which shorten the expiry and are legitimate (C11);
--     the rest are anomalies.
--   * Kept and flagged, not dropped:
--       - is_free:        amount paid = 0 (counts for retention, not revenue)
--       - has_list_price: list price > 0 (discount can only be measured
--                         there; Mar-Oct 2015 has list price zeroed by a
--                         logging failure, see C10)
--       - long_expiry:    expires more than 2 years after the transaction
--   * payment_plan_days stays in the table but must NOT be used for
--     duration: it is zero in Mar-Oct 2015. Use membership_expire_date.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tx;

CREATE TABLE tx AS
WITH stacked AS (
    SELECT * FROM transactions_v1
    UNION
    SELECT * FROM transactions_v2
)
SELECT
    msno,
    transaction_date,
    membership_expire_date,
    payment_method_id,
    payment_plan_days,
    plan_list_price,
    actual_amount_paid,
    is_auto_renew,
    is_cancel,
    (actual_amount_paid = 0)                                         AS is_free,
    (plan_list_price > 0)                                            AS has_list_price,
    (membership_expire_date > transaction_date + INTERVAL '2 years') AS long_expiry
FROM stacked
WHERE membership_expire_date <> DATE '1970-01-01'
  AND NOT (membership_expire_date < transaction_date AND is_cancel = 0);

CREATE INDEX tx_msno_date_idx ON tx (msno, transaction_date);
ANALYZE tx;


-- ---------------------------------------------------------------------
-- 2. vw_members: registration data with the unreliable fields removed
--
--   * age: bd outside 1-100 becomes NULL (67% of the base).
--   * channel: the 4 large channels (99.3% of registrations) stay
--     separate; the other 14 become 'other'.
--   * city and gender are left out on purpose: city = 1 holds 71% of
--     the base (looks like a default value) and gender is 65% null.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_members AS
SELECT
    msno,
    registration_init_time                            AS registered_at,
    DATE_TRUNC('month', registration_init_time)::DATE AS registered_month,
    CASE WHEN registered_via IN (3, 4, 7, 9)
         THEN registered_via::TEXT ELSE 'other' END   AS channel,
    CASE WHEN bd BETWEEN 1 AND 100 THEN bd END        AS age
FROM members;


-- ---------------------------------------------------------------------
-- 3. vw_logs: daily usage without the impossible records
--
--   * Dropped: total_secs > 86,400 (more than 24h in a day; 4,200 rows).
--   * songs_played = tracks listened to in any proportion.
--   * Already one row per user/day (D2), so COUNT(*) per day = DAU.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_logs AS
SELECT
    msno,
    date                                         AS log_date,
    num_25 + num_50 + num_75 + num_985 + num_100 AS songs_played,
    num_100                                      AS songs_completed,
    num_unq                                      AS unique_songs,
    total_secs
FROM user_logs
WHERE total_secs <= 86400;


-- ---------------------------------------------------------------------
-- 4. Check
-- ---------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM tx)                               AS tx_rows,
    (SELECT COUNT(DISTINCT msno) FROM tx)                   AS tx_users,
    (SELECT COUNT(*) FROM tx WHERE is_free)                 AS tx_free,
    (SELECT COUNT(*) FROM tx WHERE NOT has_list_price)      AS tx_no_list_price,
    (SELECT COUNT(*) FROM tx WHERE long_expiry)             AS tx_long_expiry,
    (SELECT SUM(actual_amount_paid) FROM tx)                AS total_revenue,
    (SELECT COUNT(*) FROM vw_logs)                          AS log_rows,
    (SELECT COUNT(*) FROM vw_members WHERE age IS NOT NULL) AS members_with_age;
