-- Monthly acquisition cohorts: % of each cohort that buys again N months after its first purchase.
-- The 2009-12 cohort is left-censored: it holds every customer who already existed before the data starts,
-- so its retention is inflated. Read it as "existing base", not as a true cohort.
WITH active_months AS (
  SELECT DISTINCT f.customer_key, d.year_month
  FROM fact_sales f
  JOIN dim_date d USING (date_key)
  WHERE f.is_cancellation = 0 AND f.is_non_product = 0 AND f.customer_key IS NOT NULL
),
cohort_activity AS (
  SELECT
    c.cohort_month,
    a.customer_key,
    (CAST(substr(a.year_month, 1, 4) AS INTEGER) * 12 + CAST(substr(a.year_month, 6, 2) AS INTEGER))
      - (CAST(substr(c.cohort_month, 1, 4) AS INTEGER) * 12 + CAST(substr(c.cohort_month, 6, 2) AS INTEGER))
      AS month_number
  FROM active_months a
  JOIN dim_customer c USING (customer_key)
),
cohort_size AS (
  SELECT cohort_month, COUNT(*) AS cohort_size
  FROM dim_customer
  WHERE cohort_month IS NOT NULL
  GROUP BY cohort_month
)
SELECT
  ca.cohort_month,
  s.cohort_size,
  ca.month_number,
  COUNT(DISTINCT ca.customer_key)                                    AS active_customers,
  ROUND(100.0 * COUNT(DISTINCT ca.customer_key) / s.cohort_size, 1)  AS retention_pct
FROM cohort_activity ca
JOIN cohort_size s USING (cohort_month)
GROUP BY ca.cohort_month, s.cohort_size, ca.month_number
ORDER BY ca.cohort_month, ca.month_number;
