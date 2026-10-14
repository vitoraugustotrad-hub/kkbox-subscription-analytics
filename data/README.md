# Data

The data is not stored in this repository (it is several gigabytes and belongs to the competition).

## Source

[WSDM - KKBox's Churn Prediction Challenge](https://www.kaggle.com/c/kkbox-churn-prediction-challenge) on Kaggle. Downloading requires a Kaggle account and accepting the competition rules.

## Files used

| File | Loaded into | Rows |
|---|---|---|
| `members_v3.csv` | `members` | 6,769,473 |
| `train_v2.csv` | `train` | 970,960 |
| `transactions.csv` | `transactions_v1` | 21,547,746 |
| `transactions_v2.csv` | `transactions_v2` | 1,431,009 |
| `user_logs_v2.csv` | `user_logs` | 18,396,362 |

Not used: `user_logs.csv` (the full usage history, about 30 GB), `train.csv` and `sample_submission_*.csv`.

## Loading

1. Extract the `.7z` archives.
2. Run the `CREATE TABLE` statements in [`sql/00_schema.sql`](../sql/00_schema.sql).
3. Import each CSV into its table, with header on and comma as the delimiter (pgAdmin Import/Export, or `\copy` in psql).
4. Run the `CREATE INDEX` statements at the end of `00_schema.sql`.

Dates in the files are written as `YYYYMMDD`; PostgreSQL reads that format directly into a `DATE` column.

## Notes on the fields

- `msno` is an anonymised user id.
- `membership_expire_date` is the user's expiry date after that transaction. It is the reliable source for subscription length; `payment_plan_days` is zero for part of 2015.
- `is_cancel = 1` marks a cancellation of auto-renewal. It often moves the expiry date earlier than the transaction date.
- `plan_list_price` and `actual_amount_paid` are in New Taiwan dollars.
- KKBox's churn definition, used throughout: no new valid subscription within 30 days after the current membership expires.
