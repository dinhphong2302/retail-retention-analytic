-- How long after the first order does the second one come? Same cohort window as the funnel.
-- Shows where the "second purchase" window closes, which is when a re-engagement nudge should fire.
WITH orders AS (
  SELECT customer_key, invoice_no, MIN(invoice_ts) AS order_ts
  FROM fact_sales
  WHERE is_cancellation = 0 AND is_non_product = 0 AND customer_key IS NOT NULL
  GROUP BY customer_key, invoice_no
),
seq AS (
  SELECT
    o.customer_key,
    o.order_ts,
    ROW_NUMBER() OVER (PARTITION BY o.customer_key ORDER BY o.order_ts, o.invoice_no) AS order_number,
    FIRST_VALUE(o.order_ts) OVER (PARTITION BY o.customer_key ORDER BY o.order_ts, o.invoice_no) AS first_ts
  FROM orders o
  JOIN dim_customer c USING (customer_key)
  WHERE c.cohort_month BETWEEN '2010-01' AND '2011-06'
),
second AS (
  SELECT customer_key, julianday(order_ts) - julianday(first_ts) AS days_to_second
  FROM seq
  WHERE order_number = 2
),
bucketed AS (
  SELECT
    CASE
      WHEN days_to_second <= 30  THEN 1
      WHEN days_to_second <= 60  THEN 2
      WHEN days_to_second <= 90  THEN 3
      WHEN days_to_second <= 180 THEN 4
      ELSE 5
    END AS bucket_order,
    CASE
      WHEN days_to_second <= 30  THEN '0-30 days'
      WHEN days_to_second <= 60  THEN '31-60 days'
      WHEN days_to_second <= 90  THEN '61-90 days'
      WHEN days_to_second <= 180 THEN '91-180 days'
      ELSE '180+ days'
    END AS bucket
  FROM second
)
SELECT
  bucket,
  COUNT(*)                                                                         AS customers,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                               AS pct,
  ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY bucket_order) / SUM(COUNT(*)) OVER (), 1) AS cumulative_pct
FROM bucketed
GROUP BY bucket_order, bucket
ORDER BY bucket_order;
