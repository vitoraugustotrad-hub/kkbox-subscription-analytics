-- =====================================================================
-- 00_schema.sql  |  Raw tables and import notes
--
-- Create the tables first, then import each CSV (pgAdmin Import/Export
-- with Header = on and delimiter = comma, or psql \copy).
--
-- Notes:
--   * Dates arrive as YYYYMMDD (e.g. 20170131). PostgreSQL parses that
--     format directly into a DATE column, so no conversion is needed.
--   * transactions.csv (v1) and transactions_v2.csv are loaded into
--     separate tables on purpose. Whether they overlap is checked in
--     01_data_quality.sql before they are combined.
--   * Create the indexes AFTER the import; loading is much slower with
--     indexes in place.
-- =====================================================================

CREATE TABLE members (
    msno                   TEXT PRIMARY KEY,
    city                   INTEGER,
    bd                     INTEGER,
    gender                 TEXT,
    registered_via         INTEGER,
    registration_init_time DATE
);

CREATE TABLE train (
    msno     TEXT PRIMARY KEY,
    is_churn SMALLINT
);

CREATE TABLE transactions_v1 (
    msno                   TEXT,
    payment_method_id      INTEGER,
    payment_plan_days      INTEGER,
    plan_list_price        INTEGER,
    actual_amount_paid     INTEGER,
    is_auto_renew          SMALLINT,
    transaction_date       DATE,
    membership_expire_date DATE,
    is_cancel              SMALLINT
);

CREATE TABLE transactions_v2 (LIKE transactions_v1);

CREATE TABLE user_logs (
    msno       TEXT,
    date       DATE,
    num_25     INTEGER,
    num_50     INTEGER,
    num_75     INTEGER,
    num_985    INTEGER,
    num_100    INTEGER,
    num_unq    INTEGER,
    total_secs NUMERIC
);

-- File -> table
--   members_v3.csv      -> members
--   train_v2.csv        -> train
--   transactions.csv    -> transactions_v1
--   transactions_v2.csv -> transactions_v2
--   user_logs_v2.csv    -> user_logs

-- Run after all five imports have finished:
CREATE INDEX ON transactions_v1 (msno);
CREATE INDEX ON transactions_v2 (msno);
CREATE INDEX ON user_logs (msno, date);
ANALYZE;

-- Expected row counts
--   members          6,769,473
--   train              970,960
--   transactions_v1 21,547,746
--   transactions_v2  1,431,009
--   user_logs       18,396,362
