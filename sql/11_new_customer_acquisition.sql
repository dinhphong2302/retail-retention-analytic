-- New-customer acquisition, H2 2010 vs H2 2011 (Jul-Nov).
-- H1 2010 is left out on purpose: the data starts 2009-12, so in early 2010 many long-standing customers
-- show up as "new" the first time they appear. By mid-2010 that effect has mostly washed out.
WITH new_by_month AS (
  SELECT cohort_month, COUNT(*) AS new_customers
  FROM dim_customer
  WHERE cohort_month IS NOT NULL
  GROUP BY cohort_month
)
SELECT
  substr(cohort_month, 1, 4)                    AS year,
  SUM(new_customers)                            AS new_customers_jul_nov,
  ROUND(AVG(new_customers), 0)                  AS avg_new_per_month
FROM new_by_month
WHERE substr(cohort_month, 6, 2) BETWEEN '07' AND '11'
GROUP BY 1
ORDER BY 1;
