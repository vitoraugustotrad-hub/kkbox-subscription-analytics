-- =====================================================================
-- q08_activation.sql
--
-- Business question: how many new registrants actually start using the
--                    app in their first week, and does that differ by
--                    channel?
-- Why it matters:    q02 showed the first month is where subscribers
--                    are lost. Activation is the earliest point where
--                    that loss could be seen coming.
-- Definitions (METRICS.md):
--   * population = registered 2017-03-01 to 2017-03-24, so the 7 days
--                  after registration fit in the usage logs (March 2017)
--   * first week = registration day plus the next 6 days
--   * activated  = at least 3 active days in the first week; 1 and 5
--                  days are reported as sensitivity
-- Validity check built into the query: do the logs cover registrants
--   who have not paid? If pct_active_1d_among_non_payers were near zero,
--   the logs would be subscriber-only and "activation" would only mirror
--   payment. It is about 90%, so activation is measurable here.
-- Reading note: pct_paid_in_march runs to the end of the data, so users
--   registered late in the month had less time to pay. It is context,
--   not the 30-day conversion of q06.
-- =====================================================================
WITH new_users AS (
    SELECT msno, channel, registered_at
    FROM vw_members
    WHERE registered_at BETWEEN DATE '2017-03-01' AND DATE '2017-03-24'
),
first_week AS (
    SELECT
        n.msno,
        COUNT(l.msno) AS active_days
    FROM new_users n
    LEFT JOIN vw_logs l
           ON  l.msno = n.msno
           AND l.log_date BETWEEN n.registered_at AND n.registered_at + 6
    GROUP BY n.msno
),
paid AS (
    SELECT DISTINCT msno
    FROM tx_daily
    WHERE NOT is_free
      AND tx_date >= DATE '2017-03-01'
)
SELECT
    n.channel,
    COUNT(*)                                                             AS registrations,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.active_days >= 1) / COUNT(*), 1) AS pct_active_1d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.active_days >= 3) / COUNT(*), 1) AS pct_activated_3d,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.active_days >= 5) / COUNT(*), 1) AS pct_active_5d,
    ROUND(100.0 * COUNT(p.msno) / COUNT(*), 1)                           AS pct_paid_in_march,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.active_days >= 1 AND p.msno IS NULL)
          / NULLIF(COUNT(*) FILTER (WHERE p.msno IS NULL), 0), 1)        AS pct_active_1d_among_non_payers
FROM new_users n
JOIN first_week f USING (msno)
LEFT JOIN paid p USING (msno)
GROUP BY n.channel
ORDER BY registrations DESC;
