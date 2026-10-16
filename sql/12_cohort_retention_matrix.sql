-- Cohort retention as a matrix (one row per cohort, M1..M12 columns) for the dashboard heatmap.
-- Built with conditional aggregation on top of the long-format cohort query.
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
      AS m
  FROM active_months a
  JOIN dim_customer c USING (customer_key)
  WHERE c.cohort_month BETWEEN '2010-01' AND '2011-11'
),
sizes AS (
  SELECT cohort_month, COUNT(DISTINCT customer_key) AS n
  FROM cohort_activity
  WHERE m = 0
  GROUP BY cohort_month
),
counts AS (
  SELECT cohort_month, m, COUNT(DISTINCT customer_key) AS active
  FROM cohort_activity
  GROUP BY cohort_month, m
)
SELECT
  s.cohort_month AS "Cohort",
  s.n AS "New customers",
  ROUND(100.0 * MAX(CASE WHEN m = 1  THEN active END) / s.n, 1) AS "M1",
  ROUND(100.0 * MAX(CASE WHEN m = 2  THEN active END) / s.n, 1) AS "M2",
  ROUND(100.0 * MAX(CASE WHEN m = 3  THEN active END) / s.n, 1) AS "M3",
  ROUND(100.0 * MAX(CASE WHEN m = 4  THEN active END) / s.n, 1) AS "M4",
  ROUND(100.0 * MAX(CASE WHEN m = 5  THEN active END) / s.n, 1) AS "M5",
  ROUND(100.0 * MAX(CASE WHEN m = 6  THEN active END) / s.n, 1) AS "M6",
  ROUND(100.0 * MAX(CASE WHEN m = 9  THEN active END) / s.n, 1) AS "M9",
  ROUND(100.0 * MAX(CASE WHEN m = 12 THEN active END) / s.n, 1) AS "M12"
FROM sizes s
JOIN counts c USING (cohort_month)
GROUP BY s.cohort_month, s.n
ORDER BY s.cohort_month;
