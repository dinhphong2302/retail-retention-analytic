-- Monthly KPI table: revenue, orders, active customers, new vs returning, AOV, cancellation rate.
-- Month-over-month change uses LAG. December 2011 has data only up to the 9th, so it is flagged partial.
WITH lines AS (
  SELECT f.*, d.year_month
  FROM fact_sales f
  JOIN dim_date d USING (date_key)
  WHERE f.is_non_product = 0
),
monthly AS (
  SELECT
    l.year_month,
    SUM(CASE WHEN l.is_cancellation = 0 THEN l.revenue ELSE 0 END)                       AS gross_revenue,
    -SUM(CASE WHEN l.is_cancellation = 1 THEN l.revenue ELSE 0 END)                      AS cancelled_revenue,
    COUNT(DISTINCT CASE WHEN l.is_cancellation = 0 THEN l.invoice_no END)                AS orders,
    COUNT(DISTINCT CASE WHEN l.is_cancellation = 0 AND l.customer_key IS NULL
                        THEN l.invoice_no END)                                           AS guest_orders,
    COUNT(DISTINCT CASE WHEN l.is_cancellation = 0 THEN l.customer_key END)              AS active_customers,
    COUNT(DISTINCT CASE WHEN l.is_cancellation = 0 AND c.cohort_month = l.year_month
                        THEN l.customer_key END)                                         AS new_customers
  FROM lines l
  LEFT JOIN dim_customer c ON c.customer_key = l.customer_key
  GROUP BY l.year_month
)
SELECT
  year_month,
  CASE WHEN year_month = '2011-12' THEN 1 ELSE 0 END                         AS is_partial_month,
  ROUND(gross_revenue, 0)                                                    AS gross_revenue,
  ROUND(gross_revenue - cancelled_revenue, 0)                                AS net_revenue,
  orders,
  active_customers,
  new_customers,
  active_customers - new_customers                                           AS returning_customers,
  ROUND(100.0 * new_customers / active_customers, 1)                         AS new_customer_pct,
  ROUND(gross_revenue / orders, 1)                                           AS aov,
  ROUND(100.0 * cancelled_revenue / gross_revenue, 2)                        AS cancel_rate_pct,
  ROUND(100.0 * guest_orders / orders, 1)                                    AS guest_order_pct,
  ROUND(100.0 * (gross_revenue - LAG(gross_revenue) OVER w) / LAG(gross_revenue) OVER w, 1) AS revenue_mom_pct,
  ROUND(100.0 * (gross_revenue - LAG(gross_revenue, 12) OVER w) / LAG(gross_revenue, 12) OVER w, 1) AS revenue_yoy_pct
FROM monthly
WINDOW w AS (ORDER BY year_month)
ORDER BY year_month;
