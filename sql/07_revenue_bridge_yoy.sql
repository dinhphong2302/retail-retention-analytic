-- Root-cause bridge: why did revenue from identified customers change year over year?
-- Revenue = active customers x orders per customer x average order value.
-- The change is split into three additive effects (they sum exactly to the total change):
--   customer effect  = (C1 - C0) * F0 * A0
--   frequency effect = C1 * (F1 - F0) * A0
--   AOV effect       = C1 * F1 * (A1 - A0)
WITH monthly AS (
  SELECT
    d.year_month,
    COUNT(DISTINCT f.customer_key) AS c,
    COUNT(DISTINCT f.invoice_no)   AS o,
    SUM(f.revenue)                 AS rev
  FROM fact_sales f
  JOIN dim_date d USING (date_key)
  WHERE f.is_cancellation = 0 AND f.is_non_product = 0 AND f.customer_key IS NOT NULL
  GROUP BY d.year_month
),
paired AS (
  SELECT
    cur.year_month,
    prev.c AS c0, cur.c AS c1,
    1.0 * prev.o / prev.c AS f0, 1.0 * cur.o / cur.c AS f1,
    prev.rev / prev.o AS a0, cur.rev / cur.o AS a1,
    prev.rev AS rev0, cur.rev AS rev1
  FROM monthly cur
  JOIN monthly prev
    ON CAST(substr(prev.year_month, 1, 4) AS INTEGER) = CAST(substr(cur.year_month, 1, 4) AS INTEGER) - 1
   AND substr(prev.year_month, 6, 2) = substr(cur.year_month, 6, 2)
  WHERE cur.year_month <> '2011-12'
)
SELECT
  year_month,
  ROUND(rev0, 0)                       AS revenue_last_year,
  ROUND(rev1, 0)                       AS revenue,
  ROUND(rev1 - rev0, 0)                AS change,
  ROUND(100.0 * (rev1 - rev0) / rev0, 1) AS change_pct,
  ROUND((c1 - c0) * f0 * a0, 0)        AS customer_effect,
  ROUND(c1 * (f1 - f0) * a0, 0)        AS frequency_effect,
  ROUND(c1 * f1 * (a1 - a0), 0)        AS aov_effect,
  c0 AS customers_last_year, c1 AS customers,
  ROUND(f0, 2) AS orders_per_customer_last_year, ROUND(f1, 2) AS orders_per_customer,
  ROUND(a0, 0) AS aov_last_year, ROUND(a1, 0) AS aov
FROM paired
ORDER BY year_month;
