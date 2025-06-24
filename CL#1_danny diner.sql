SELECT * FROM [dannys_diner].[members]
SELECT * FROM [dannys_diner].[menu]
SELECT * FROM [dannys_diner].[sales]

/* --------------------
   Case Study Questions
   --------------------*/

-- 1. What is the total amount each customer spent at the restaurant?
SELECT 
    s.customer_id 
    , SUM (m.price) AS spent_amount
FROM [dannys_diner].[sales] s
LEFT JOIN [dannys_diner].[menu] m 
    ON  s.product_id = m.product_id
GROUP BY  s.customer_id 
ORDER BY  s.customer_id 


-- 2. How many days has each customer visited the restaurant?
SELECT 
    customer_id 
    ,COUNT(DISTINCT order_date) AS count_days_cus_visited
FROM [dannys_diner].[sales] 
GROUP BY customer_id 
ORDER BY customer_id 

-- 3. What was the first item from the menu purchased by each customer?
WITH CTE AS(
    SELECT 
        s.customer_id 
        ,s.order_date
        ,m.product_name
        ,DENSE_RANK () OVER(PARTITION BY s.customer_id ORDER BY s.order_date ) AS item_purchased
        FROM [dannys_diner].[sales] s
        JOIN [dannys_diner].[menu] m
        ON s.product_id = m.product_id
)

SELECT 
    customer_id
    ,product_name
FROM CTE 
WHERE item_purchased = 1
GROUP BY customer_id, product_name
ORDER BY customer_id 


-- 4. What is the most purchased item on the menu and how many times was it purchased by all customers?
SELECT TOP 1
    s.product_id
    ,m.product_name
    ,COUNT (s.product_id) AS most_purchased_item
FROM [dannys_diner].[sales] s 
JOIN [dannys_diner].[menu] m
    ON s.product_id = m.product_id
GROUP BY 
    s.product_id
    ,m.product_name
ORDER BY most_purchased_item DESC 

-- 5. Which item was the most popular for each customer?
WITH CTE1 AS (
    SELECT 
        s.customer_id 
        ,m.product_name
        ,COUNT (*) AS count_item_cus_order
    FROM [dannys_diner].[sales] s
    JOIN [dannys_diner].[menu] m
        ON s.product_id = m.product_id
    GROUP BY 
        s.customer_id 
        ,m.product_name
)
,CTE2 AS(
    SELECT 
    customer_id 
    ,product_name
    ,RANK() OVER(PARTITION BY customer_id ORDER BY count_item_cus_order ) AS rank
    FROM CTE1
)

SELECT 
    customer_id 
    ,product_name
FROM CTE2 
WHERE rank = 1

-- 6. Which item was purchased first by the customer after they became a member?

SELECT 
    s.customer_id 
    ,m.product_name AS first_item_purchased
FROM [dannys_diner].[sales] s
JOIN [dannys_diner].[menu] m
    ON s.product_id = m.product_id
JOIN (
    SELECT 
        s.customer_id 
        ,MIN (s.order_date) AS first_date_join
    FROM [dannys_diner].[sales] s
    JOIN [dannys_diner].[members] mb
        ON s.customer_id = mb.customer_id 
    WHERE mb.join_date <= s.order_date
    GROUP BY s.customer_id 
) AS CTE3
    ON s.customer_id = CTE3.customer_id  AND s.order_date = CTE3.first_date_join

-- 7. Which item was purchased just before the customer became a member?
SELECT 
    s.customer_id 
    ,m.product_name AS purchased_item_before_join
FROM [dannys_diner].[sales] s
JOIN [dannys_diner].[menu] m
    ON s.product_id = m.product_id
JOIN (
    SELECT 
        s.customer_id 
        ,MAX (s.order_date) AS date_before_join
    FROM [dannys_diner].[sales] s
    JOIN [dannys_diner].[members] mb
        ON s.customer_id = mb.customer_id 
    WHERE mb.join_date > s.order_date
    GROUP BY s.customer_id 
) AS CTE4
    ON s.customer_id = CTE4.customer_id  AND s.order_date = CTE4.date_before_join

-- 8. What is the total items and amount spent for each member before they became a member?
SELECT 
    s.customer_id
    ,COUNT(*) AS total_item_before_join
    ,SUM(m.price) AS total_spent_amount_before_join
FROM [dannys_diner].[sales] s
JOIN [dannys_diner].[menu] m
    ON  s.product_id = m.product_id
JOIN [dannys_diner].[members] mb
    ON s.customer_id =  mb.customer_id
WHERE mb.join_date > s.order_date
GROUP BY s.customer_id


-- 9.  If each $1 spent equates to 10 points and sushi has a 2x points multiplier - how many points would each customer have?

WITH CTE5 AS(
    SELECT 
        s.customer_id 
        ,m.product_name
        ,m.price 
        ,CASE 
            WHEN m.product_name = 'sushi' THEN m.price *20 
            ELSE m.price * 10 
            END AS item_point 
    FROM [dannys_diner].[sales] s 
    JOIN [dannys_diner].[menu] m
        ON s.product_id = m.product_id
)

SELECT
    customer_id 
    ,SUM (item_point) AS cus_point
FROM CTE5
GROUP BY customer_id 
ORDER BY customer_id 
-- 10. In the first week after a customer joins the program (including their join date) they earn 2x points on all items, not just sushi - how many points do customer A and B have at the end of January?

WITH CTE6 AS (
    SELECT 
        s.customer_id
        ,s.order_date
        ,m.product_name
        ,m.price
        ,mb.join_date
        ,CASE 
            WHEN DATEDIFF(DAY,s.order_date,mb.join_date) BETWEEN 0 AND 6
                THEN m.price * 20
            WHEN mb.join_date > s.order_date 
                THEN CASE 
                    WHEN m.product_name = 'sushi' THEN m.price * 20
                    ELSE m.price * 10
                END
            ELSE
                CASE 
                    WHEN m.product_name = 'sushi' THEN m.price * 20
                    ELSE m.price * 10
                END
        END AS points
FROM [dannys_diner].[sales] s
JOIN [dannys_diner].[menu] m ON s.product_id = m.product_id
LEFT JOIN [dannys_diner].[members] mb ON s.customer_id = mb.customer_id
WHERE s.order_date <= '2021-01-31'  
)

SELECT 
    customer_id
    ,SUM(points) AS total_points
FROM CTE6
GROUP BY customer_id;

---BONUS QUESTIONS
---Join All The Things & Rank All The Things
WITH CTE7 AS(
    SELECT 
        s.customer_id
        ,s.order_date
        ,m.product_name
        ,m.price
        ,CASE 
            WHEN mb.join_date <= order_date THEN 'Y'
            WHEN mb.join_date > order_date THEN 'N' 
            ELSE 'N' END 
            AS member_status
    FROM [dannys_diner].[sales] s
    LEFT JOIN [dannys_diner].[menu] m ON s.product_id = m.product_id
    LEFT JOIN [dannys_diner].[members] mb ON s.customer_id = mb.customer_id
)

SELECT 
    *
    ,CASE 
        WHEN member_status = 'N' then NULL
        ELSE RANK () OVER (
                PARTITION BY customer_id, member_status 
                ORDER BY order_date
        ) END AS ranking
FROM CTE7


