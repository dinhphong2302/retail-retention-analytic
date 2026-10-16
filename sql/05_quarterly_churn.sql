-- Quarterly churn: share of customers who bought in quarter Q and did not buy in quarter Q+1,
-- split by whether Q was their first quarter (new) or not (returning).
-- 2011-Q4 is partial (data ends 2011-12-09), so the last measurable quarter is 2011-Q3.
WITH active_q AS (
  SELECT DISTINCT
    f.customer_key,
    d.year * 4 + d.quarter                 AS q_index,
    d.year || '-Q' || d.quarter            AS quarter
  FROM fact_sales f
  JOIN dim_date d USING (date_key)
  WHERE f.is_cancellation = 0 AND f.is_non_product = 0 AND f.customer_key IS NOT NULL
),
first_q AS (
  SELECT customer_key, MIN(q_index) AS first_q_index
  FROM active_q
  GROUP BY customer_key
),
labelled AS (
  SELECT
    a.quarter,
    a.q_index,
    a.customer_key,
    CASE WHEN a.q_index = fq.first_q_index THEN 'new' ELSE 'returning' END AS customer_type,
    CASE WHEN nxt.customer_key IS NULL THEN 1 ELSE 0 END                   AS churned
  FROM active_q a
  JOIN first_q fq USING (customer_key)
  LEFT JOIN active_q nxt
    ON nxt.customer_key = a.customer_key AND nxt.q_index = a.q_index + 1
  WHERE a.q_index BETWEEN 2010 * 4 + 1 AND 2011 * 4 + 3
)
SELECT
  quarter,
  customer_type,
  COUNT(*)                              AS active_customers,
  SUM(churned)                          AS churned_next_quarter,
  ROUND(100.0 * SUM(churned) / COUNT(*), 1) AS churn_rate_pct
FROM labelled
GROUP BY quarter, q_index, customer_type
ORDER BY q_index, customer_type;
