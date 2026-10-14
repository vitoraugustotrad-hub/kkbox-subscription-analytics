-- =====================================================================
-- q06_conversion_by_channel.sql
--
-- Business question: which registration channels bring users who become
--                    payers, and how fast?
-- Why it matters:    registration volume does not pay the bills. If a
--                    channel brings many people who never pay, the
--                    investment in it should be reviewed.
-- Definitions (METRICS.md):
--   * population = registered 2015-01-01 to 2017-02-28 (the 30 days
--                  after registration fit entirely in the data)
--   * conversion = first PAID transaction within 30 days of registration
--   * channel    = registered_via grouped (3, 4, 7, 9 and 'other')
-- Extra columns:
--   * pct_ever_paid: conversion with no time limit. Favours older
--     cohorts, which had more time; context only.
--   * pct_paid_before_registering: a paid transaction dated before the
--     registration date. Should not exist; measures inconsistency
--     between the two tables.
-- =====================================================================
WITH first_paid AS (
    SELECT msno, MIN(tx_date) AS first_paid_date
    FROM tx_daily
    WHERE NOT is_free
    GROUP BY msno
),
base AS (
    SELECT
        m.channel,
        m.registered_at,
        p.first_paid_date
    FROM vw_members m
    LEFT JOIN first_paid p USING (msno)
    WHERE m.registered_at BETWEEN DATE '2015-01-01' AND DATE '2017-02-28'
)
SELECT
    channel,
    COUNT(*)                                            AS registrations,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_registrations,
    ROUND(100.0 * COUNT(*) FILTER (WHERE first_paid_date BETWEEN registered_at
                                                             AND registered_at + 30)
          / COUNT(*), 2)                                AS pct_converted_30d,
    ROUND(100.0 * COUNT(first_paid_date) / COUNT(*), 2) AS pct_ever_paid,
    ROUND(100.0 * COUNT(*) FILTER (WHERE first_paid_date < registered_at)
          / COUNT(*), 2)                                AS pct_paid_before_registering,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY first_paid_date - registered_at)
        FILTER (WHERE first_paid_date >= registered_at) AS median_days_to_pay
FROM base
GROUP BY channel
ORDER BY registrations DESC;
