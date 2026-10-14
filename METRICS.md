# Metric dictionary

The definitions below were fixed **after the data quality audit and before any business question was run**, so that none could be chosen for giving the most favourable number. Where more than one definition was defensible, the rejected alternative and the reason are recorded.

Two kinds of numbers appear in this document, and neither is a result of the analysis: limits found in the data quality audit (`sql/01_data_quality.sql`), which shaped the definitions, and validation checks added afterwards, marked **Validity check**, which confirm that a metric can be measured at all.

Every metric reads from the clean tables (`tx`, `tx_daily`, `subscriptions`, `active_eom`, `vw_members`, `vw_logs`), never from the raw ones.

## Limits imposed by the data

| Limit | Consequence |
|---|---|
| Transactions cover 2015-01-01 to 2017-03-31 | For users registered before 2015, the first visible transaction may not be the real first one. Cohorts only use registrations from January 2015. |
| Usage logs cover March 2017 only | Engagement and activation are measured in a single month. There is no DAU/MAU history and no usage-based retention matrix. |
| 18% of paying users have no `members` record | They are left out of any metric that depends on registration date or channel. Their churn is lower (5.35% vs 9.46%), so results by channel overstate overall churn. |
| Age is invalid for 67% of members and gender is null for 65% | Not used as segments. |
| The data ends on 2017-03-31 | A period expiring close to that date cannot yet be classified as churned (right-censoring). |

## Engagement

### Active user (day)
- **Definition:** a user with a row in `vw_logs` on that day.
- **Why:** every log row has at least one song played (checked in the data quality audit), so a row already means real usage.
- **Rejected alternative:** requiring at least one song played to the end (`songs_completed >= 1`). It is stricter, but penalises users who browse and skip, which is still product usage. Reported as a sensitivity check.

### DAU, MAU and stickiness
- **DAU:** distinct active users on a day. The log has one row per user per day, so it is `COUNT(*)` per day.
- **MAU:** distinct active users in March 2017.
- **Stickiness:** average DAU of the month divided by MAU.
- **Required companion:** the distribution of active days per user. The ratio alone hides whether the base is one homogeneous group or a mix of daily and occasional users.

### Activation
- **Definition:** a user registered in March 2017 with at least 3 active days in the first 7 days (registration day plus the next 6).
- **Population:** registrations from March 1 to March 24, 2017, so the 7 days fit entirely in the log.
- **Why:** a single day of usage does not separate someone who tried and left from someone who adopted the product.
- **Sensitivity:** the threshold is arbitrary; 1 and 5 days are reported alongside.
- **Validity check:** the logs must cover registrants who have not paid, otherwise activation would only mirror payment. About 90% of non-paying registrants appear in the logs in their first week, so the metric is measurable.

## Monetisation

### Revenue
- **Definition:** `SUM(actual_amount_paid)`.
- **Rejected alternative:** list price (`plan_list_price`), which is zero between March and October 2015 because of a logging failure.

### Discount
- **Definition:** `1 - actual_amount_paid / plan_list_price`, computed only where `has_list_price` is true.

### Conversion to paid
- **Definition:** share of registrants (from January 2015) whose first **paid** transaction happens within 30 days of registration.
- **Rejected alternative:** counting any transaction. Free transactions (`is_free`) are promotions and would inflate conversion.

## Retention and churn

### Active subscriber (day)
- **Definition:** on day *d*, the user's most recent transaction (with `tx_date <= d`) has `effective_end > d`.
- **Why:** each transaction resets the expiry date; the user's state is given by the latest one.
- **Rejected alternative:** "paid something that month". It fails for 90-, 180- and 410-day plans, which do not generate a transaction every month.
- **Free transactions count** as an active subscription. Paid retention is reported separately.

### Subscription period
- **Definition:** a sequence of transactions in which the uncovered gap between one and the next never exceeds 30 days. A longer gap closes the period; a later return opens a new one.

### Churn
- **Definition:** a period ends in churn when more than 30 days pass after the end of coverage with no new transaction. This is KKBox's own definition.
- **Sensitivity:** also reported with 15- and 60-day windows.
- **Censoring:** periods ending after 2017-03-01 stay `open`, because the 30-day window does not fit in the data.

### Cancellation is not churn
`is_cancel = 1` switches off auto-renewal. The user may keep access until expiry and pay again within the window. Cancellation is a **signal** of churn, not the event.

### Cohort retention
- **Cohort:** month of first transaction, for users registered from January 2015.
- **Retained in month *k*:** active subscriber on the last day of month *k* after the cohort month.
- **Type:** subscription (revenue) retention. Usage retention cannot be measured with one month of logs.
- **Reading note:** this is unbounded retention. A user who leaves and returns counts as retained again, so a later month can be higher than an earlier one.

## Treatment rules that affect the metrics

| Rule | Applied in |
|---|---|
| Exact duplicates removed | `tx` |
| Expiry on 1970-01-01 removed | `tx` |
| Expiry before the transaction, when not a cancellation, removed | `tx` |
| Several transactions on one day: latest expiry wins, amounts summed | `tx_daily` |
| In a cancellation whose expiry precedes the transaction, coverage ends on the cancellation day | `tx_daily` (`effective_end`) |
| More than 24 hours of usage in a day removed | `vw_logs` |
| Duration always from `membership_expire_date`, never from `payment_plan_days` | all |
