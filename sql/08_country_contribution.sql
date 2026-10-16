-- Which markets drove the change? Jan-Nov 2011 vs Jan-Nov 2010 gross revenue by country,
-- with each country's share of the total change. Countries outside the top 8 by revenue are grouped.
WITH by_country AS (
  SELECT
    f.country,
    SUM(CASE WHEN d.year = 2010 THEN f.revenue ELSE 0 END) AS rev_2010,
    SUM(CASE WHEN d.year = 2011 THEN f.revenue ELSE 0 END) AS rev_2011
  FROM fact_sales f
  JOIN dim_date d USING (date_key)
  WHERE f.is_cancellation = 0 AND f.is_non_product = 0
    AND d.month BETWEEN 1 AND 11 AND d.year IN (2010, 2011)
  GROUP BY f.country
),
ranked AS (
  SELECT *, RANK() OVER (ORDER BY rev_2011 DESC) AS rnk
  FROM by_country
),
grouped AS (
  SELECT
    CASE WHEN rnk <= 8 THEN country ELSE 'Other countries' END AS country,
    SUM(rev_2010) AS rev_2010,
    SUM(rev_2011) AS rev_2011
  FROM ranked
  GROUP BY 1
)
SELECT
  country,
  ROUND(rev_2010, 0)                                                         AS revenue_2010,
  ROUND(rev_2011, 0)                                                         AS revenue_2011,
  ROUND(rev_2011 - rev_2010, 0)                                              AS change,
  ROUND(100.0 * (rev_2011 - rev_2010) / rev_2010, 1)                         AS change_pct,
  ROUND(100.0 * (rev_2011 - rev_2010) / SUM(rev_2011 - rev_2010) OVER (), 1) AS share_of_total_change_pct
FROM grouped
ORDER BY revenue_2011 DESC;
