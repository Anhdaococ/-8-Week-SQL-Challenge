SELECT * FROM [dbo].[customer_nodes]
SELECT * FROM [dbo].[customer_transactions]
SELECT * FROM [dbo].[regions]

                                    --- A. Customer Nodes Exploration

---1.How many unique nodes are there on the Data Bank system?
SELECT COUNT(DISTINCT node_id) AS number_of_nodes
FROM [dbo].[customer_nodes]

---2.What is the number of nodes per region?
SELECT 
    r.region_name
    ,COUNT(DISTINCT n.node_id) AS nb_of_nodes_region
FROM regions r
JOIN customer_nodes n
    ON r.region_id = n.region_id
GROUP BY r.region_name 
ORDER BY r.region_name 

---3.How many customers are allocated to each region?
SELECT 
    r.region_id
    ,r.region_name
    ,COUNT(DISTINCT n.customer_id) AS nb_of_cus_region
FROM regions r
JOIN customer_nodes n
    ON r.region_id = n.region_id
GROUP BY 
    r.region_id
    ,r.region_name 
ORDER BY r.region_id

---4.How many days on average are customers reallocated to a different node?

--- For each customer
SELECT 
    customer_id
    ,ROUND(AVG(DATEDIFF(DAY, start_date, end_date) + 1),0) AS Avg_Day_to_Reallocate
FROM 
    customer_nodes
WHERE 
    end_date != '9999-12-31'
GROUP BY 
    customer_id;

--- For all customer
SELECT 
    ROUND(AVG(DATEDIFF(DAY, start_date, end_date) + 1),0) AS Avg_Day_to_Reallocate
FROM 
    customer_nodes
WHERE 
    end_date != '9999-12-31'

---5.What is the median, 80th and 95th percentile for this same reallocation days metric for each region?

SELECT DISTINCT 
    n.region_id
    ,r.region_name
    ,PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATEDIFF (DAY,start_date,end_date)+1 ) 
        OVER(PARTITION BY n.region_id) AS median_day
    ,PERCENTILE_CONT(0.85) WITHIN GROUP (ORDER BY DATEDIFF (DAY,start_date,end_date)+1)
        OVER (PARTITION BY n.region_id) AS p80th_day
    ,PERCENTILE_CONT (0.9) WITHIN GROUP (ORDER BY DATEDIFF(DAY,start_date,end_date)+1)
        OVER (PARTITION BY n.region_id) AS p90th_day
FROM customer_nodes n
JOIN regions r 
    ON n.region_id = r.region_id
WHERE end_date != '9999-12-31'

                                ----B. Customer Transactions----          

--- 1.What is the unique count and total amount for each transaction type?

SELECT 
    txn_type
    ,COUNT(txn_type) AS unique_count
    ,SUM (txn_amount) AS total_amount
FROM customer_transactions
GROUP BY txn_type

--- 2.What is the average total historical deposit counts and amounts for all customers?
SELECT
    ROUND(AVG(total_txn),0) AS avg_total_txn
    ,ROUND(AVG(amount_transacted),0) AS avg_amount_transacted
FROM 
    (SELECT
        customer_id
        ,COUNT(txn_type) AS total_txn
        ,SUM(txn_amount) AS amount_transacted
    FROM customer_transactions
    WHERE 
        txn_type = 'deposit'
    GROUP BY customer_id) AS t 



--- 3.For each month - how many Data Bank customers make more than 1 deposit and either 1 purchase or 1 withdrawal in a single month?
WITH CTE1 AS(
    SELECT 
        customer_id
        ,MONTH (txn_date) AS month_no
        ,DATENAME (Month,txn_date) AS month_name
        ,SUM (CASE WHEN txn_type = 'deposit' THEN 1 ELSE 0 END ) AS deposit_count
        ,SUM (CASE WHEN txn_type = 'withdrawal' THEN 1 ELSE 0 END) AS withdrawal_count
        ,SUM (CASE WHEN txn_type = 'purchase' THEN 1 ELSE 0 END) AS purchase_count
    FROM customer_transactions
    GROUP BY         
        customer_id
        ,MONTH(txn_date)
        ,DATENAME(MONTH, txn_date)
)
SELECT 
    month_no
    ,month_name
    ,COUNT(DISTINCT customer_id) as active_cus
FROM CTE1
WHERE 
    deposit_count >1
    AND withdrawal_count >1
    AND purchase_count >1 
GROUP BY 
    month_no
    ,month_name
ORDER BY 
    month_no
    ,month_name

--- 4.What is the closing balance for each customer at the end of the month?
SELECT 
    customer_id
    ,MONTH (txn_date) AS month_no
    ,DATENAME (MONTH, txn_date) AS month_num
    ,SUM (CASE 
            WHEN txn_type IN ('withdrawal','purchase') 
                THEN txn_amount * -1 ELSE  txn_amount * 1 
            END) AS Mth_end_balance
FROM customer_transactions
GROUP BY 
    customer_id
    ,MONTH (txn_date) 
    ,DATENAME (MONTH, txn_date) 
ORDER BY 
    customer_id
    ,MONTH (txn_date) 


--- 5.What is the percentage of customers who increase their closing balance by more than 5%?
SELECT 
    COUNT (DISTINCT customer_id) *1.0 /
    (SELECT COUNT(DISTINCT customer_id) FROM customer_nodes) AS growth
    FROM (
        SELECT 
        month_no
        ,customer_id
        ,Mth_end_balance
        ,(Mth_end_balance - LAG(Mth_end_balance)OVER (PARTITION BY customer_id ORDER BY month_no))*1.0
        / ABS(LAG(Mth_end_balance) OVER (PARTITION BY customer_id ORDER BY month_no)) AS pers_chance
        FROM(
            SELECT 
                customer_id,
                MONTH(txn_date) AS month_no,
                SUM(CASE 
                        WHEN txn_type IN ('withdrawal','purchase') 
                            THEN txn_amount * -1 
                        ELSE txn_amount * 1 
                    END) AS Mth_end_balance
            FROM customer_transactions
            GROUP BY 
                customer_id,
                MONTH(txn_date)
        ) AS MonthlyBalance
) AS WithPercChange
WHERE pers_chance > 0.05

                            ---C. Data Allocation Challenge---

----Option 1: data is allocated based off the amount of money at the end of the previous month
WITH month_end AS (
    SELECT 
        customer_id
        ,MONTH (txn_date) AS month_no
        ,DATENAME (MONTH, txn_date) AS month_name
        ,SUM (CASE 
                WHEN txn_type IN ('withdrawal','purchase' ) THEN txn_amount *-1 ELSE txn_amount * 1 END)  AS Mth_end_bal
    FROM customer_transactions
    GROUP BY   
        customer_id
        ,MONTH (txn_date) 
        ,DATENAME (MONTH, txn_date) 
)
, DataAllocated AS (
    SELECT 
        *
        ,LAG(Mth_end_bal) OVER (PARTITION BY customer_id ORDER BY month_no ) AS prev_balance
    FROM month_end
)

,DataInGB AS (
    SELECT *
        ,CASE
            WHEN prev_balance IS NULL THEN 0.5 
            WHEN prev_balance < 0 THEN 0.5
            ELSE (prev_balance /100.0 ) * 2 + 0.5
        END AS data_allocated_gb
    FROM DataAllocated
)

SELECT
    month_no
    ,month_name
    ,CAST(SUM(data_allocated_gb) AS DECIMAL(10,2)) AS total_data_allocated_gb
FROM DataInGB
GROUP BY month_name, month_no
ORDER BY month_no


----Option 2: data is allocated on the average amount of money kept in the account in the previous 30 days
WITH month_end AS (
    SELECT 
        customer_id
        ,MONTH(txn_date) AS month_no
        ,DATENAME(MONTH, txn_date) AS month_name
        ,AVG(txn_amount) AS Avg_end_bal
    FROM customer_transactions
    WHERE txn_type = 'deposit'
    GROUP BY  
        customer_id
        ,MONTH(txn_date) 
        ,DATENAME(MONTH, txn_date) 
)
, DataAllocated AS (
    SELECT 
        *
        ,LAG(Avg_end_bal) OVER (PARTITION BY customer_id ORDER BY month_no) AS prev_balance
    FROM month_end
)

,DataInGB AS (
    SELECT
        *
        ,CASE 
            WHEN prev_balance IS NULL THEN 0.5
            WHEN prev_balance < 0 THEN 0.5
            ELSE (prev_balance/100.0)*2 +0.5
        END AS data_allocated_gb
    FROM DataAllocated
)

SELECT 
    month_no
    ,month_name 
    ,CAST (SUM ( data_allocated_gb) AS DECIMAL (10,2)) AS total_data_allocated_gb
FROM DataInGB
GROUP BY 
    month_no
    ,month_name 
ORDER BY month_no

----Option 3: data is updated real-time

WITH running_balance AS (
    SELECT 
        customer_id,
        MONTH(txn_date) AS month_no,
        DATENAME(MONTH, txn_date) AS month_name,
        txn_date,
        txn_type,
        txn_amount,
        SUM(CASE
                WHEN txn_type = 'deposit' THEN txn_amount 
                WHEN txn_type IN ('withdrawal', 'purchase') THEN -txn_amount 
                ELSE 0
            END) OVER (PARTITION BY customer_id ORDER BY txn_date) AS running_bal
    FROM customer_transactions
)

,DataInGB AS (
    SELECT 
        *
        ,CASE 
            WHEN running_bal <0 THEN 0.5
            ELSE (running_bal /100.0) *2 +0.5
        END data_allocated_gb
    FROM running_balance
)

SELECT 
    month_no
    ,month_name
    ,CAST (SUM (data_allocated_gb) AS DECIMAL (10,2)) AS total_data_allocated_gb
FROM DataInGB
GROUP BY 
    month_no
    ,month_name 
ORDER BY month_no

                                        -----D. Extra Challenge
WITH running_balance AS (
    SELECT 
        customer_id,
        MONTH(txn_date) AS month_no,
        DATENAME(MONTH, txn_date) AS month_name,
        txn_date,
        txn_type,
        txn_amount,
        SUM(CASE
                WHEN txn_type = 'deposit' THEN txn_amount 
                WHEN txn_type IN ('withdrawal', 'purchase') THEN -txn_amount 
                ELSE 0
            END) OVER (PARTITION BY customer_id ORDER BY txn_date) AS running_bal
    FROM customer_transactions
)
,Interest AS (
    SELECT 
        *
        ,running_bal * 0.000164 AS intr
    FROM running_balance
)
,DataInGB AS (
    SELECT 
        *
        ,CASE 
            WHEN intr <0 THEN 0
            ELSE (intr/100.0) * 2 
        END AS data_allocated_gb 
    FROM Interest
)

SELECT 
    month_no
    ,month_name
    ,CAST (SUM (data_allocated_gb) AS DECIMAL (10,2)) AS total_data_allocated_gb
FROM DataInGB
GROUP BY 
    month_no
    ,month_name
ORDER BY 
    month_no