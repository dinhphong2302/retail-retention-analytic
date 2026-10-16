-- RFM segmentation as of 2011-12-10, over the last 12 months of activity.
-- R, F and M are 1-5 quintile scores (5 = best) computed with NTILE.
WITH orders AS (
  SELECT customer_key, invoice_no, MIN(invoice_ts) AS order_ts, SUM(revenue) AS order_value
  FROM fact_sales
  WHERE is_non_product = 0 AND customer_key IS NOT NULL
    AND invoice_ts >= '2010-12-10'
  GROUP BY customer_key, invoice_no
),
per_customer AS (
  SELECT
    customer_key,
    julianday('2011-12-10') - julianday(MAX(CASE WHEN order_value > 0 THEN order_ts END)) AS recency_days,
    SUM(CASE WHEN order_value > 0 THEN 1 ELSE 0 END)                                       AS frequency,
    SUM(order_value)                                                                       AS monetary
  FROM orders
  GROUP BY customer_key
  HAVING frequency > 0 AND monetary > 0
),
scored AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r,
    NTILE(5) OVER (ORDER BY frequency)         AS f,
    NTILE(5) OVER (ORDER BY monetary)          AS m
  FROM per_customer
),
segmented AS (
  SELECT
    *,
    CASE
      WHEN r >= 4 AND f >= 4                THEN 'Champions'
      WHEN r >= 3 AND f >= 3                THEN 'Loyal'
      WHEN r >= 4 AND f <= 2                THEN 'New / Promising'
      WHEN r <= 2 AND f >= 3                THEN 'At risk'
      WHEN r = 3 AND f <= 2                 THEN 'Needs attention'
      ELSE 'Hibernating'
    END AS segment
  FROM scored
)
SELECT
  segment,
  COUNT(*)                                                       AS customers,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS pct_customers,
  ROUND(SUM(monetary), 0)                                        AS revenue_12m,
  ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)   AS pct_revenue,
  ROUND(AVG(recency_days), 0)                                    AS avg_recency_days,
  ROUND(AVG(frequency), 1)                                       AS avg_orders,
  ROUND(AVG(monetary), 0)                                        AS avg_revenue
FROM segmented
GROUP BY segment
ORDER BY revenue_12m DESC;
