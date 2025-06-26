                --- 2. Digital Analysis
--- Using the available datasets - answer the following questions using a single query for each one:

--- 1.How many users are there?

SELECT COUNT(DISTINCT user_id) AS count_users
FROM users

--- 2.How many cookies does each user have on average?
SELECT
    CAST(
        ROUND( 1.0 * COUNT(DISTINCT cookie_id) / COUNT(DISTINCT user_id),0)
        AS INT)
     AS avg_cookies_per_user
FROM users

--- 3.What is the unique number of visits by all users per month?
SELECT 
    CONVERT(CHAR(7), event_time, 120) AS month,
    COUNT(DISTINCT visit_id) AS unique_visit_count
FROM events
GROUP BY CONVERT(CHAR(7), event_time, 120)
ORDER BY month;

--- 4.What is the number of events for each event type?
SELECT 
    event_type
    ,COUNT(*) AS event_count
FROM events
GROUP BY event_type
ORDER BY event_type

--- 5.What is the percentage of visits which have a purchase event?
SELECT 
    COUNT(DISTINCT e.visit_id) * 100 / 
    (SELECT COUNT(DISTINCT visit_id) FROM events) AS percentage_purchase
FROM events e
JOIN event_identifier ei ON e.event_type = ei.event_type
WHERE ei.event_name = 'Purchase'


--- 6.What is the percentage of visits which view the checkout page but do not have a purchase event?
WITH checkout_purchase AS (
      SELECT 
        visit_id 
        ,MAX (CASE WHEN event_type = 1 AND page_id = 12 THEN 1 ELSE 0 END) AS checkout
        ,MAX (CASE WHEN event_type = 3 THEN 1 ELSE 0 END) AS purchase
    FROM events
    GROUP BY visit_id 
)

SELECT
    ROUND( 
        100.0*(1-CAST(SUM(purchase) AS FLOAT)/NULLIF (SUM(checkout),0))
    ,2) AS percentage_checkout_view_with_no_purchase
FROM checkout_purchase


--- 7.What are the top 3 pages by number of views?
SELECT TOP 3
    ph.page_name 
    ,COUNT(*) AS page_view
FROM page_hierarchy ph 
JOIN events e
    ON e.page_id = ph.page_id
WHERE e.event_type = 1 
GROUP BY  ph.page_name 
ORDER BY page_view DESC

--- 8.What is the number of views and cart adds for each product category?
SELECT
    ph.product_category
    ,COUNT(CASE WHEN event_type = 2 THEN 1 END ) AS cart_add_count
    ,COUNT(CASE WHEN event_type = 1 THEN 1 END ) AS view_count
FROM events e 
JOIN page_hierarchy ph 
    ON e.page_id = ph.page_id
WHERE ph.product_category IS NOT NULL
GROUP BY ph.product_category
ORDER BY ph.product_category

--- 9.What are the top 3 products by purchases?
WITH purchase_visit AS (
    SELECT DISTINCT visit_id AS purchase_id
    FROM events
    WHERE event_type = 3
)
, card_add AS (
    SELECT 
        ph.page_name
        ,e.visit_id
    FROM events e
    JOIN page_hierarchy ph 
        ON ph.page_id = e.page_id
    WHERE 
        ph.product_id IS NOT NULL
        AND event_type	= 2
)

SELECT TOP 3
  ca.page_name AS Product,
  COUNT(*) AS Quantity_purchased
FROM purchase_visit pv
LEFT JOIN card_add ca ON pv.purchase_id = ca.visit_id
GROUP BY ca.page_name
ORDER BY COUNT(*) DESC;

---3. Product Funnel Analysis
---Using a single SQL query - create a new output table which has the following details:
---•	How many times was each product viewed?
---•	How many times was each product added to cart?
---•	How many times was each product added to a cart but not purchased (abandoned)?
---•	How many times was each product purchased?

WITH product_page_events AS ( -- Note 1
       SELECT 
        e.visit_id
        ,ph.product_id
        ,ph.page_name AS product_name
        ,ph.product_category
        ,SUM(CASE WHEN event_type = 1 THEN 1 ELSE 0 END) AS page_view
        ,SUM(CASE WHEN event_type = 2 THEN 1 ELSE 0 END) AS cart_add
    FROM events e 
    JOIN page_hierarchy ph 
        ON e.page_id = ph.page_id
    WHERE ph.product_id IS NOT NULL
    GROUP BY e.visit_id ,ph.product_id ,ph.page_name  ,ph.product_category
)
,purchase_events AS ( -- Note 2
    SELECT DISTINCT visit_id 
    FROM events 
    WHERE event_type = 3
)
,combined_table AS( -- Note 3
    SELECT ppe.*
        ,CASE WHEN pe.visit_id IS NOT NULL THEN 1 ELSE 0 END AS purchase
    FROM product_page_events ppe
    LEFT JOIN purchase_events pe
        ON ppe.visit_id = pe.visit_id
)
,product_info AS (
SELECT
    product_id
    ,product_name 
    ,product_category
    ,SUM(page_view) AS views
    ,SUM(cart_add) AS cart_add
    ,SUM(CASE WHEN cart_add = 1 AND purchase = 0 THEN 1 ELSE 0 END) AS abandoned
    ,SUM(CASE WHEN cart_add = 1 AND purchase = 1 THEN 1 ELSE 0 END) AS purchases
FROM combined_table
GROUP BY product_id ,product_name  ,product_category
)
SELECT *
INTO product_info
FROM product_info;


---Additionally, create another table which further aggregates the data for the above points but this time for each product category instead of individual products.
---Use your 2 new output tables - answer the following questions:
---1.	Which product had the most views, cart adds and purchases?
SELECT 
    'Most Views' AS metric
    ,product_name
    ,views AS value
FROM product_info
WHERE views = (SELECT MAX(views) FROM product_info)

UNION ALL
SELECT 
    'Most Add to Cart' AS metric
    ,product_name
    ,cart_add AS value
FROM product_info
WHERE cart_add = (SELECT MAX(cart_add) FROM product_info)

UNION ALL
SELECT 
    'Most Purchased' AS metric
    ,product_name
    ,cart_add AS value
FROM product_info
WHERE purchases = (SELECT MAX(purchases) FROM product_info)


---2.	Which product was most likely to be abandoned?
SELECT TOP 1
    product_name
    ,product_category
    ,abandoned
    ,cart_add
    ,ROUND(CAST(abandoned AS FLOAT) / NULLIF(cart_add,0),2) AS abandoned_rate
FROM product_info
ORDER BY abandoned_rate DESC
---3.	Which product had the highest view to purchase percentage?
SELECT TOP 1
    product_name
    ,product_category
    ,abandoned
    ,cart_add
    ,ROUND(CAST(purchases AS FLOAT) / NULLIF(views,0),2) AS view_to_purchase_rate
FROM product_info
ORDER BY view_to_purchase_rate ASC

---4.	What is the average conversion rate from view to cart add?

SELECT 
    ROUND(AVG(CAST(cart_add AS FLOAT)/ NULLIF(views,0)),4) AS avg_view_to_cart_conversion
FROM product_info

---5.	What is the average conversion rate from cart add to purchase?

SELECT 
    ROUND(AVG(CAST(purchases AS FLOAT)/ NULLIF(cart_add,0)),4) AS avg_view_to_cart_conversion
FROM product_info

                                ---3. Campaigns Analysis
/* Generate a table that has 1 single row for every unique visit_id record and has the following columns:*/
WITH visit_summary AS (
    SELECT 
        u.user_id
        ,e.visit_id
        ,MIN(e.event_time) AS visit_start_time
        ,COUNT(CASE WHEN e.event_type = 1 THEN 1 END) AS page_views
        ,COUNT(CASE WHEN e.event_type = 2 THEN 1 END) AS cart_adds
        ,MAX(CASE WHEN e.event_type = 3 THEN 1 ELSE 0 END) AS purchase
        ,COUNT(CASE WHEN e.event_type = 4 THEN 1 END) AS impression
        ,COUNT(CASE WHEN e.event_type = 5 THEN 1 END) AS click
        ,STRING_AGG(
            CASE 
                WHEN ph.product_id IS NOT NULL AND e.event_type = 2
                THEN ph.page_name ELSE NULL END, ', ')
                WITHIN GROUP (ORDER BY e.sequence_number) AS cart_products
    FROM users u
    JOIN events e ON u.cookie_id = e.cookie_id
    LEFT JOIN campaign_identifier ci ON e.event_time BETWEEN ci.start_date AND ci.end_date
    LEFT JOIN page_hierarchy ph ON e.page_id = ph.page_id
    GROUP BY u.user_id, e.visit_id
)

SELECT
    vs.*
    ,ci.campaign_name
FROM visit_summary vs
LEFT JOIN campaign_identifier ci
    ON vs.visit_start_time BETWEEN ci.start_date AND ci.end_date
ORDER BY vs.user_id

