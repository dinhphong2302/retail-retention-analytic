-- Repeat-purchase funnel: 1st order -> 2nd -> 3rd -> 5th -> 10th.
-- Only customers acquired 2010-01 .. 2011-06 are included, so everyone had at least ~5 months to come back
-- (2009-12 is excluded because it mixes in pre-existing customers).
WITH orders AS (
  SELECT customer_key, invoice_no, MIN(invoice_ts) AS order_ts
  FROM fact_sales
  WHERE is_cancellation = 0 AND is_non_product = 0 AND customer_key IS NOT NULL
  GROUP BY customer_key, invoice_no
),
numbered AS (
  SELECT
    o.customer_key,
    ROW_NUMBER() OVER (PARTITION BY o.customer_key ORDER BY o.order_ts, o.invoice_no) AS order_number
  FROM orders o
  JOIN dim_customer c USING (customer_key)
  WHERE c.cohort_month BETWEEN '2010-01' AND '2011-06'
),
per_customer AS (
  SELECT customer_key, MAX(order_number) AS n_orders
  FROM numbered
  GROUP BY customer_key
),
steps AS (
  SELECT 1 AS step, '1st order' AS stage UNION ALL
  SELECT 2, '2nd order' UNION ALL
  SELECT 3, '3rd order' UNION ALL
  SELECT 5, '5th order' UNION ALL
  SELECT 10, '10th order'
),
funnel AS (
  SELECT s.step, s.stage, COUNT(p.customer_key) AS customers
  FROM steps s
  LEFT JOIN per_customer p ON p.n_orders >= s.step
  GROUP BY s.step, s.stage
)
SELECT
  step,
  stage,
  customers,
  ROUND(100.0 * customers / FIRST_VALUE(customers) OVER (ORDER BY step), 1) AS pct_of_first_order,
  ROUND(100.0 * customers / LAG(customers) OVER (ORDER BY step), 1)          AS conversion_from_prev_pct
FROM funnel
ORDER BY step;
