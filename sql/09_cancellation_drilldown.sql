-- Drill-down for the cancellation-rate spikes in 2011-01 and 2011-12:
-- the largest cancelled invoice lines, with their share of that month's cancelled revenue.
WITH cancels AS (
  SELECT d.year_month, f.invoice_no, f.invoice_ts, f.customer_key, f.product_key, p.description,
         f.quantity, -f.revenue AS cancelled_value
  FROM fact_sales f
  JOIN dim_date d USING (date_key)
  JOIN dim_product p ON p.product_key = f.product_key
  WHERE f.is_cancellation = 1 AND f.is_non_product = 0
),
ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY year_month ORDER BY cancelled_value DESC) AS rn,
         100.0 * cancelled_value / SUM(cancelled_value) OVER (PARTITION BY year_month) AS share_pct
  FROM cancels
)
SELECT year_month, rn, invoice_ts, customer_key, product_key, description, quantity,
       ROUND(cancelled_value, 0) AS cancelled_value, ROUND(share_pct, 1) AS share_of_month_cancellations_pct
FROM ranked
WHERE rn <= 3 AND year_month IN ('2011-01', '2011-12', '2010-05', '2011-04')
ORDER BY year_month, rn;
