                    -----1. Data Cleansing Steps
SELECT 
    TRY_CONVERT(date, week_date, 3) AS week_date
    ,(DATEPART(WEEK, TRY_CONVERT(date, week_date, 3))) AS week_number
    ,MONTH(TRY_CONVERT(date, week_date, 3)) AS month_number
    ,YEAR (TRY_CONVERT(date, week_date, 3)) AS calendar_year
    ,region
    ,platform
    ,CASE
        WHEN RIGHT(segment,1) = '1' THEN 'Young Adults'
        WHEN RIGHT(segment,1) = '2' THEN 'Middle Aged'
        WHEN RIGHT(segment,1) IN ('3','4') THEN 'Retirees' 
        ELSE 'Unknown'
        END AS age_band
    ,CASE 
        WHEN LEFT(segment,1) = 'C' THEN 'Couples'
        WHEN LEFT(segment,1) = 'F' THEN 'Families'
        ELSE 'unknown'
    END AS demographic
    ,CASE
        WHEN segment = 'null' THEN 'unknown'
        ELSE segment
    END AS segment
    ,customer_type
    ,transactions
    ,sales
    ,ROUND(
        CASE 
            WHEN transactions IS NOT NULL AND transactions <> 0 THEN sales/transactions 
            ELSE NULL 
            END, 2 ) AS avg_transactions
INTO clean_weekly_sales
FROM Data_mart

DROP TABLE clean_weekly_sales;

SELECT *
FROM clean_weekly_sales

                    ---2. Data Exploration 
---What day of the week is used for each week_date value? 
SELECT 
    DISTINCT( DATENAME(WEEKDAY, week_date)) AS day_name
FROM clean_weekly_sales

---What range of week numbers are missing from the dataset? 

WITH seq AS (
    SELECT TOP 53 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS value_num
    FROM sys.all_objects
)
SELECT value_num AS missing_week_num
FROM seq 
WHERE value_num NOT IN ( 
    SELECT DISTINCT DATEPART(WEEK, TRY_CONVERT(date, week_date, 3))  AS week_number
    FROM clean_weekly_sales
)


---How many total transactions were there for each year in the dataset? 
SELECT  
    calendar_year
    ,SUM (transactions) AS total_transactions
FROM clean_weekly_sales
GROUP BY calendar_year
ORDER BY calendar_year


---What is the total sales for each region for each month?
SELECT 
    month_number
    ,region 
    ,SUM(CAST(sales AS BIGINT)) AS total_sales_region_month
FROM clean_weekly_sales
GROUP BY 
    month_number
    ,region 
ORDER BY 
    month_number

---What is the total count of transactions for each platform 
SELECT 
    platform 
    ,SUM(transactions) AS total_count_of_transaction
FROM clean_weekly_sales
GROUP BY 
    platform 


---What is the percentage of sales for Retail vs Shopify for each month?
WITH sales AS (
    SELECT 
        calendar_year
        ,month_number
        ,platform,
        SUM(CAST(sales AS BIGINT)) AS monthly_sales
    FROM clean_weekly_sales
    GROUP BY
        calendar_year
        ,month_number 
        ,platform
)
SELECT 
    calendar_year, month_number
    ,CAST(ROUND(100.0 * MAX(CASE WHEN platform = 'Retail' THEN monthly_sales END) 
        / SUM(monthly_sales), 2) AS DECIMAL (5,2)) AS retail
    ,CAST(ROUND(100.0 * MAX(CASE WHEN platform = 'Shopify' THEN monthly_sales END) 
        / SUM(monthly_sales), 2) AS DECIMAL (5,2))  AS shopify
FROM sales
GROUP BY 
    calendar_year
    ,month_number
ORDER BY 
    calendar_year
    ,month_number;


---What is the percentage of sales by demographic for each year in the dataset? 

---- demographic
WITH sales_by_demo AS (
    SELECT 
        calendar_year
        ,demographic
        ,SUM(CAST(sales AS BIGINT)) AS yearly_sales
    FROM clean_weekly_sales
    GROUP BY 
        calendar_year
        ,demographic

)
SELECT 
    calendar_year
    ,age_band
    ,CAST(ROUND(100.0 * MAX (CASE WHEN demographic = 'families' THEN yearly_sales ELSE NULL END)/ SUM(yearly_sales) ,2 ) AS DECIMAL(10,2)) AS sales_families
    ,CAST(ROUND(100.0 * MAX (CASE WHEN demographic = 'couples' THEN yearly_sales ELSE NULL END)/ SUM(yearly_sales) ,2 ) AS DECIMAL(10,2)) AS sales_couples
    ,CAST(ROUND(100.0 * MAX (CASE WHEN demographic = 'unknown' THEN yearly_sales ELSE NULL END) /SUM(yearly_sales),2 ) AS DECIMAL(10,2)) AS sales_unknown
FROM sales_by_demo
GROUP BY calendar_year

---Which age_band and demographic values contribute the most to Retail sales? 
SELECT 
    age_band
    ,demographic
    ,SUM(CAST(sales AS BIGINT)) AS total_sales
    ,CAST (ROUND(100.0 * SUM(CAST(sales AS BIGINT)) / SUM (SUM(CAST(sales AS BIGINT))) OVER (),1) AS DECIMAL(10,2)) AS percent_contributions
FROM clean_weekly_sales
WHERE platform = 'retail'
GROUP BY 
    age_band
    ,demographic
ORDER BY total_sales DESC


---Can we use the avg_transaction column to find the average transaction size for each year for Retail vs Shopify? If not - how would you calculate it instead
SELECT 
    calendar_year 
    ,CAST(ROUND (1.0 * AVG(avg_transactions),2) AS DECIMAL(10,2)) AS incorrect_avg_method
    ,CAST(ROUND (1.0 * SUM(CAST(sales AS BIGINT))/ SUM (transactions) , 2) AS DECIMAL(10,2)) AS avg_txn
FROM clean_weekly_sales
GROUP BY calendar_year

                                    ------3. Before & After Analysis------
/*We would include all week_date values for 2020-06-15 as the start of the period 
after the change and the previous week_date values would be before
Using this analysis approach - answer the following questions:*/
 
SELECT DISTINCT week_number
FROM clean_weekly_sales
WHERE 
    week_date = '2020-06-15'
    AND calendar_year = '2020' 

----1. What is the total sales for the 4 weeks before and after 2020-06-15? What is the growth or reduction rate in actual values and percentage of sales?
WITH tot_sales_4_weeks AS (
    SELECT 
        week_date 
        ,week_number
        ,SUM(CAST(sales AS BIGINT)) AS total_sales
    FROM clean_weekly_sales
    WHERE week_number BETWEEN 21 AND 28
    GROUP BY 
        week_date 
        ,week_number
)

,sales_comparison AS (
    SELECT 
        SUM (CASE WHEN week_number BETWEEN 21 AND 24 THEN total_sales END) AS sales_before
        ,SUM (CASE WHEN week_number BETWEEN 25 AND 28 THEN total_sales END) AS sales_after
    FROM tot_sales_4_weeks 
)

SELECT 
    ,sales_before
    ,sales_after
    ,sales_after - sales_before AS sales_diff
    ,CAST (ROUND (100.0 * (sales_after - sales_before ) /  NULLIF(sales_before, 0), 1) AS DECIMAL(10,2)) AS percent_diff
FROM sales_comparison


----2. What about the entire 12 weeks before and after?
WITH tot_sales_12_weeks AS (
    SELECT 
        week_date
        ,week_number
        ,SUM(CAST (sales AS BIGINT)) AS total_sales
    FROM clean_weekly_sales
    WHERE 
        week_number BETWEEN 13 AND 37 
        AND calendar_year = 2020
    GROUP BY 
        week_date
        ,week_number
)

, sales_change_12w AS (
    SELECT 
        SUM (CASE WHEN week_number BETWEEN 13 AND 24 THEN total_sales END) AS sales_before
        ,SUM (CASE WHEN week_number BETWEEN 25 AND 37 THEN total_sales END) AS sales_after 
    FROM tot_sales_12_weeks
)

SELECT 
    sales_before
    ,sales_after
    ,sales_after -sales_before AS sales_diff_12w
    ,CAST (ROUND (100.0 * (sales_after -sales_before) /  NULLIF(sales_before, 0), 1) AS DECIMAL (10,2)) AS percent_diff_12w
FROM sales_change_12w

----3. How do the sale metrics for these 2 periods before and after compare with the previous years in 2018 and 2019?

----4_week
WITH sales_change AS(
    SELECT 
        calendar_year
        ,SUM(CAST(CASE WHEN week_number BETWEEN 21 AND 24 THEN sales END AS BIGINT)) AS sales_before
        ,SUM(CAST(CASE WHEN week_number BETWEEN 25 AND 28 THEN sales END AS BIGINT)) AS sales_after
    FROM clean_weekly_sales
    GROUP BY calendar_year
)

SELECT 
    *
    ,sales_after -sales_before AS sales_diff_year
    ,CAST (ROUND (100.0 * (sales_after -sales_before) /  NULLIF(sales_before, 0), 1) AS DECIMAL (10,2)) AS percent_diff_12w
FROM sales_change
ORDER BY calendar_year

----12w_3y
WITH sales_change AS(
    SELECT 
        calendar_year
        ,SUM(CAST(CASE WHEN week_number BETWEEN 13 AND 24 THEN sales END AS BIGINT)) AS sales_before
        ,SUM(CAST(CASE WHEN week_number BETWEEN 25 AND 37 THEN sales END AS BIGINT)) AS sales_after
    FROM clean_weekly_sales
    GROUP BY calendar_year
)

SELECT 
    *
    ,sales_after -sales_before AS sales_diff_year
    ,CAST (ROUND (100.0 * (sales_after -sales_before) /  NULLIF(sales_before, 0), 1) AS DECIMAL (10,2)) AS percent_diff_12w
FROM sales_change
ORDER BY calendar_year


