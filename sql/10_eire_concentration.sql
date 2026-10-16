-- Drill-down for the EIRE decline: is it broad-based or a few accounts?
-- Jan-Nov revenue per EIRE customer in 2010 vs 2011, and each account's share of the market's change.
WITH eire AS (
  SELECT
    COALESCE(CAST(f.customer_key AS TEXT), 'guest') AS customer,
    SUM(CASE WHEN d.year = 2010 THEN f.revenue ELSE 0 END) AS rev_2010,
    SUM(CASE WHEN d.year = 2011 THEN f.revenue ELSE 0 END) AS rev_2011
  FROM fact_sales f
  JOIN dim_date d USING (date_key)
  WHERE f.country = 'EIRE' AND f.is_cancellation = 0 AND f.is_non_product = 0
    AND d.month BETWEEN 1 AND 11 AND d.year IN (2010, 2011)
  GROUP BY 1
)
SELECT
  customer,
  ROUND(rev_2010, 0) AS revenue_2010,
  ROUND(rev_2011, 0) AS revenue_2011,
  ROUND(rev_2011 - rev_2010, 0) AS change,
  ROUND(100.0 * (rev_2011 - rev_2010) / SUM(rev_2011 - rev_2010) OVER (), 1) AS share_of_market_change_pct,
  ROUND(100.0 * rev_2010 / SUM(rev_2010) OVER (), 1) AS share_of_2010_revenue_pct
FROM eire
ORDER BY rev_2010 DESC;
