Case Study Questions
-- 1 Design ERD
-- 2. Digital Analysis
-- Using the available datasets - answer the following questions using a single query for each one:

-- How many users are there?
SELECT 
    count (DISTINCT user_id) num_cookies
FROM 
    clique_bait.users

-- How many cookies does each user have ON average?

WITH count_cookies AS (
	SELECT 
        user_id, 
        COUNT(cookie_id) num_cookies
	FROM 
        clique_bait.users
	GROUP BY 1
    )

SELECT 
    round(avg(num_cookies))
FROM
    count_cookies

-- What is the number of unique visits by all users per month?
SELECT 
    TO_CHAR(e.event_time, 'Month') month_of_year, 
    DATE_TRUNC('month', e.event_time ) month_date, 
    u.user_id, 
    COUNT(DISTINCT e.visit_id) num_visits
FROM 
    clique_bait.users u
JOIN
    clique_bait.events e
ON 
    u.cookie_id = e.cookie_id
GROUP BY 2, 1, 3
ORDER BY 2, 3
	
-- What is the number of events for each event type?
SELECT 
    COUNT(*) num_events, 
    event_type
FROM 
    clique_bait.events
GROUP BY 2

-- What is the percentage of visits which have a purchase event?
WITH count_visits AS (
	SELECT 
		COUNT(DISTINCT visit_id) num_unique_visit, 
		COUNT(CASE WHEN event_name='Purchase' THEN visit_id END) num_visits_with_purchase
	FROM 
		clique_bait.events e
	JOIN 
		clique_bait.event_identifier ei
	ON 
		e.event_type = ei.event_type
    )
	
SELECT 
	round(((num_visits_with_purchase/num_unique_visit::decimal)*100), 2) percent_of_visits_with_purchase
FROM 
	count_visits
	
    
--What is the percentage of visits which view the checkout page but do not have a purchase event?
WITH page_event_string AS (
    SELECT 
        visit_id, 
        SRING_AGG(page_id::text, ', ') page_str, 
        SRING_AGG(event_name, ', ') event_str 
	FROM 
		clique_bait.events e
	JOIN 
		clique_bait.event_identifier ei
	ON 
		e.event_type = ei.event_type
	GROUP BY 
        visit_id
    ),
		
count_visits AS (
    SELECT 
		COUNT(CASE WHEN page_str LIKE '%12%' and event_str NOT LIKE '%Purchase%' THEN visit_id END) num_checkout_page_visits_without_purchase, -- 12 being the page id for the checkout page
	   (SELECT COUNT(DISTINCT visit_id) FROM clique_bait.events) num_unique_visits
    FROM page_event_string
    )
	
SELECT 
    round(((num_checkout_page_visits_without_purchase::decimal/num_unique_visits) * 100), 2) percent_checkout_visits_without_purchase
FROM
    count_visits
	
-- What are the top 3 pages by number of views?
SELECT 
    COUNT(*) num_page_views, page_id	
FROM 
	clique_bait.events e
JOIN 
	clique_bait.event_identifier ei
ON 
	e.event_type = ei.event_type
GROUP BY page_id
ORDER BY 1 DESC
LIMIT 3

-- What is the number of views and cart adds for each product category?
SELECT 
    product_category, 
    COUNT(*) num_views, 
    COUNT(CASE WHEN event_name = 'Add to Cart' THEN visit_id END) num_add_to_cart_events
		
FROM 
	clique_bait.events e
JOIN 
	clique_bait.event_identifier ei
ON 
	e.event_type = ei.event_type
JOIN 
	clique_bait.page_hierarchy ph
ON 
	ph.page_id = e.page_id
WHERE 
    product_category IS NOT NULL 
GROUP BY 1

-- What are the top 3 products by purchases?
WITH all_events_string AS (
	SELECT 
		visit_id, 
		SRING_AGG(ph.page_name, ', ') pn_str,
        SRING_AGG(e.page_id::text, ', ') page_str, 
        SRING_AGG(event_name, ', ') event_str 
	FROM 
		clique_bait.events e
	JOIN 
		clique_bait.event_identifier ei
	ON 
		e.event_type = ei.event_type
	JOIN 
		clique_bait.page_hierarchy ph
	ON 
		ph.page_id = e.page_id
	GROUP BY 1),
	
includes_purchase_event AS (
	SELECT 
		visit_id, 
		UNNEST(STRING_TO_ARRAY(event_str, ', ')) event_, 
		UNNEST(STRING_TO_ARRAY(pn_str, ', ')) product_page, 
		UNNEST(STRING_TO_ARRAY(page_str, ', ')) page_id_
	FROM 
		all_events_string
	WHERE 
		event_str LIKE '%Purchase%')
	
SELECT 
	COUNT(*) num_purchases, 
	product_page
FROM 
	includes_purchase_event 
WHERE 
	event_ = 'Add to Cart'
GROUP BY 2
ORDER BY 1 DESC
LIMIT 3
	
	


        -- 3. Product Funnel Analysis
Using a single SQL query - create a new output table which has the following details:

How many times was each product viewed?
How many times was each product added to cart?
How many times was each product added to a cart but not purchased (abandoned)?
How many times was each product purchased?

CREATE TABLE product_stats AS (
WITH views_and_cart_adds AS (	
	SELECT 
		product_id,
		SUM((event_name='Page View')::int) num_page_views, 
		SUM((event_name='Add to Cart')::int) num_times_added_to_cart
	FROM 
		clique_bait.events e
	JOIN 
		clique_bait.event_identifier ei
	ON 
		e.event_type = ei.event_type
	JOIN 
		clique_bait.page_hierarchy ph
	ON 
		ph.page_id = e.page_id
	WHERE product_id IS NOT NULL 
	GROUP BY product_id
	),
	
product_and_event_agg AS (
	SELECT 
		visit_id, 
		SRING_AGG(COALESCE(ph.product_id, 200)::text, ', ') pid_str,
        SRING_AGG(event_name, ', ') event_str 
	FROM 
		clique_bait.events e
	JOIN 
		clique_bait.event_identifier ei
	ON 
		e.event_type = ei.event_type
	JOIN 
		clique_bait.page_hierarchy ph
	ON 
		ph.page_id = e.page_id
	GROUP BY 1),
	
added_not_purchased AS (
	SELECT 
		visit_id, 
		UNNEST(STRING_TO_ARRAY(event_str, ', ')) event_, 
		UNNEST(STRING_TO_ARRAY(pid_str, ', ')) p_id
	FROM 
		product_and_event_agg 
	WHERE 
		event_str LIKE '%Add to Cart%' and event_str NOT LIKE '%Purchase%'), 

count_not_purchased AS (
	SELECT 
		p_id::int, 
		SUM((event_ = 'Add to Cart')::int) num_times_not_purchased
	FROM 
		added_not_purchased
	WHERE p_id != '200'
	GROUP BY p_id),
	
purchased AS (SELECT 
		visit_id, 
		UNNEST(STRING_TO_ARRAY(event_str, ', ')) event_, 
		UNNEST(STRING_TO_ARRAY(pid_str, ', ')) p_id
	FROM 
		product_and_event_agg 
	WHERE 
		event_str LIKE '%Purchase%'), 

count_purchased AS (
	SELECT 
		p_id::int, 
		SUM((event_ = 'Add to Cart')::int) num_times_purchased
	FROM purchased
	WHERE p_id != '200'
	GROUP BY p_id)
	
SELECT 
	product_id, 
	num_page_views, 
	num_times_added_to_cart, 
	num_times_not_purchased, 
	num_times_purchased 
FROM 
	views_and_cart_adds v
JOIN 
	count_not_purchased np
ON 
	v.product_id = np.p_id
JOIN 
	count_purchased p
ON 
	p.p_id = np.p_id
ORDER BY 1
);

-- Additionally, create another table which further aggregates the data for the above points 
-- but this time for each product category instead of individual products.

CREATE TABLE product_category_stats AS (
WITH views_and_cart_adds AS (	
	SELECT 
		product_category,
		SUM((event_name='Page View')::int) num_page_views, 
		SUM((event_name='Add to Cart')::int) num_times_added_to_cart
	FROM 
		clique_bait.events e
	JOIN 
		clique_bait.event_identifier ei
	ON 
		e.event_type = ei.event_type
	JOIN 
		clique_bait.page_hierarchy ph
	ON 
		ph.page_id = e.page_id
	WHERE product_id IS NOT NULL 
	GROUP BY product_category
	),
	
product_and_event_agg AS (
	SELECT 
		visit_id, 
		SRING_AGG(COALESCE(ph.product_category, 'none')::text, ', ') pcat_str,
        SRING_AGG(event_name, ', ') event_str 
	FROM 
		clique_bait.events e
	JOIN 
		clique_bait.event_identifier ei
	ON 
		e.event_type = ei.event_type
	JOIN 
		clique_bait.page_hierarchy ph
	ON 
		ph.page_id = e.page_id
	GROUP BY 1),
	
added_not_purchased AS (
	SELECT 
		visit_id, 
		UNNEST(STRING_TO_ARRAY(event_str, ', ')) event_, 
		UNNEST(STRING_TO_ARRAY(pcat_str, ', ')) p_cat
	FROM 
		product_and_event_agg 
	WHERE 
		event_str LIKE '%Add to Cart%' and event_str NOT LIKE '%Purchase%'), 

count_not_purchased AS (
	SELECT 
		p_cat, 
		SUM((event_ = 'Add to Cart')::int) num_times_not_purchased
	FROM 
		added_not_purchased
	WHERE p_cat != 'none'
	GROUP BY p_cat),
	
purchased AS (SELECT 
		visit_id, 
		UNNEST(STRING_TO_ARRAY(event_str, ', ')) event_, 
		UNNEST(STRING_TO_ARRAY(pcat_str, ', ')) p_cat
	FROM 
		product_and_event_agg 
	WHERE 
		event_str LIKE '%Purchase%'), 

count_purchased AS (
	SELECT 
		p_cat, 
		SUM((event_ = 'Add to Cart')::int) num_times_purchased
	FROM purchased
	WHERE p_cat != '200'
	GROUP BY p_cat)
	
SELECT 
	product_category, 
	num_page_views, 
	num_times_added_to_cart, 
	num_times_not_purchased, 
	num_times_purchased 
FROM 
	views_and_cart_adds v
JOIN 
	count_not_purchased cn
ON 
	v.product_category = cn.p_cat
JOIN 
	count_purchased cp
ON 
	cp.p_cat = cn.p_cat
ORDER BY 1
);

    -- Use your 2 new output tables - answer the following questions:

--Which product had the most views, cart adds and purchases?
SELECT 
    page_name AS product
FROM 
    product_stats ps
JOIN 
    clique_bait.page_hierarchy ph
ON 
    ps.product_id = ph.product_id
ORDER BY 
    num_page_views DESC, 
    num_times_added_to_cart DESC, 
    num_times_purchased DESC
LIMIT 1

--Which product was most likely to be abandoned?
SELECT 
	page_name AS product, 
	round((num_times_not_purchased::numeric/num_times_added_to_cart) * 100, 1) abandonment_rate
FROM 
	product_stats ps
JOIN 
	clique_bait.page_hierarchy ph
ON 
	ps.product_id = ph.product_id
ORDER BY 
	abandonment_rate DESC
LIMIT 1

--Which product had the highest view to purchase percentage?
SELECT 
	page_name AS product, 
	round((num_times_purchased::numeric/num_page_views) * 100, 1) purchase_view_percentage
FROM 
	product_stats ps
JOIN 
	clique_bait.page_hierarchy ph
ON 
	ps.product_id = ph.product_id
ORDER BY 
	purchase_view_percentage DESC
LIMIT 1

-- What is the average conversion rate FROM view to cart add?
    -- product
WITH conversion_rate AS (
	SELECT 
		page_name AS product, 
		round((num_times_added_to_cart::numeric/num_page_views) * 100, 2) view_to_cart_conversion_rate
	FROM 
		product_stats ps
	JOIN 
		clique_bait.page_hierarchy ph
	ON 
		ps.product_id = ph.product_id)
		
SELECT round(avg(view_to_cart_conversion_rate), 2) avg_conversion_rate
FROM conversion_rate

    -- product category
SELECT round((avg(num_times_added_to_cart::numeric/num_page_views) * 100), 2) avg_conversion_rate
FROM product_category_stats 

-- What is the average conversion rate FROM cart add to purchase?
    -- product
WITH conversion_rate AS (
	SELECT 
		page_name AS product, 
		round((num_times_purchased::numeric/num_times_added_to_cart) * 100, 2) cart_to_purchase_conversion_rate
	FROM 
		product_stats ps
	JOIN 
		clique_bait.page_hierarchy ph
	ON 
		ps.product_id = ph.product_id)
		
SELECT round(avg(cart_to_purchase_conversion_rate), 2) avg_conversion_rate
FROM conversion_rate

    -- product category
SELECT round((avg(num_times_purchased::numeric/num_times_added_to_cart) * 100), 2) avg_conversion_rate
FROM product_category_stats 


        -- 4. Campaign Analysis
-- Generate a table that hAS 1 single row for every unique visit_id record and hAS the following columns:

-- user_id
-- visit_id
-- visit_start_time: the earliest event_time for each visit
-- page_views: count of page views for each visit
-- cart_adds: count of product cart add events for each visit
-- purchase: 1/0 flag if a purchase event exists for each visit
-- campaign_name: map the visit to a campaign if the visit_start_time falls between the start_date and END_date
-- impression: count of ad impressions for each visit
-- click: count of ad clicks for each visit
-- (Optional column) 
-- cart_products: a comma separated text value WITH products added to the cart sorted by 
-- the order they were added to the cart 
-- (hint: use the sequence_number)

CREATE TABLE campaign_to_cart AS(
WITH user_visit AS (
	SELECT 
		cu.user_id, 
		ce.visit_id,
		min(event_time) OVER (PARTITION BY visit_id) visit_start_time,
		SUM((event_type=1)::int) OVER (PARTITION BY visit_id) page_views,
		SUM((event_type=2)::int) OVER (PARTITION BY visit_id) cart_adds, 
		CASE WHEN (SUM((event_type=3)::int) OVER (PARTITION BY visit_id)) > 0 THEN 1 ELSE 0 END AS purchase_flag,
		cc.campaign_name,
		SUM(CASE WHEN campaign_id IS NOT NULL  THEN (event_type=4)::int ELSE NULL END) OVER (PARTITION BY visit_id) impression,
		SUM(CASE WHEN campaign_id IS NOT NULL  THEN (event_type=5)::int ELSE NULL END) OVER (PARTITION BY visit_id) click
    FROM
        clique_bait.users cu
    JOIN 
        clique_bait.events ce
    ON 
        cu.cookie_id = ce.cookie_id
    LEFT JOIN 
        clique_bait.campaign_identifier cc
    ON 
        ce.event_time > cc.start_date
    AND 
        ce.event_time < cc.end_date
    ORDER BY 6,5
    ),

add_to_cart_order AS (
	SELECT 
		visit_id, 
		cookie_id, 
		SRING_AGG(sequence_number::text, ', ') sequence_str, 
		SRING_AGG(page_name, ', ') product_str 
	FROM (
			SELECT visit_id, cookie_id, event_type, sequence_number, page_name, ce.page_id
			FROM clique_bait.events ce 
			JOIN clique_bait.page_hierarchy cp 
			ON ce.page_id = cp.page_id 
			WHERE event_type = 2 
			ORDER BY visit_id, cookie_id, sequence_number
			) ord
	GROUP BY 1,2
    )

SELECT DISTINCT
    uv.*, 
    ad.product_str AS cart_products
FROM 
    user_visit uv
LEFT JOIN 
    add_to_cart_order ad
ON 
    uv.visit_id = ad.visit_id);


Use the subsequent dataset to generate at least 5 insights for the Clique Bait team 

--   INSIGHTS
--1. 500 unique visitors
--2. 3564 visits
--3. 80% of traffic to the site did not come via the ad campaigns (2817 visits)
--4. 20% of traffic to the site came via the ad campaigns (747 visits)
--5. 50% of visits were converted. i.e. visit ENDed in a purchase (1777 visits)
--6. 35% of conversions happened after ad impressions or clicks
--7. 5.5% of conversions happened after only ad impressions (i.e. the ad was not clicked)
--8. 85% conversion rate of the traffic FROM ad campaigns
--9. 40% conversion rate of the non-campaign traffic 
--10. Average number of purchases by visits FROM campaign = 5
--11. Average number of purchases by non_campaign visits = 3
--12. 3771 products bought in visits FROM campaign
--13. 4680 products bought in non-campaign visits
--14. 5:6 i.e. For every 5 products bought during campaign-related visits roughly 6 products were bought during non-campaign visits


-- 1.
SELECT 
    COUNT(*) num_visits
FROM 
    campaign_to_cart

-- 2.
SELECT 
    COUNT(*) all_visits, 
    (SELECT COUNT(*) FROM campaign_to_cart WHERE impression = 1) visits_after_impression,
    round(100*(SELECT COUNT(*) FROM campaign_to_cart WHERE impression = 1) / COUNT(*)::numeric, 1) percent_visits_after_impression
FROM campaign_to_cart

-- 3.
SELECT 
	COUNT(*) all_visits, 
	(SELECT COUNT(*) FROM campaign_to_cart WHERE purchase_flag = 1) purchase_after_visit,
	round(100 * (SELECT COUNT(*) FROM campaign_to_cart WHERE purchase_flag = 1)/COUNT(*)::numeric, 1) percent_purchase_after_visit
FROM 
    campaign_to_cart

-- 4.
SELECT 
	COUNT(*) num_purchases, 
	SUM((impression=1)::int) num_impressions, 
	round(100 * SUM((impression=1)::int)::numeric/COUNT(*), 1) num_purchases
FROM 
    campaign_to_cart
WHERE 
	purchase_flag = 1

-- 5.
SELECT 
	COUNT(*) num_purchases, 
	SUM((impression=1 and click = 0)::int) num_impressions_no_clicks,
	round(100 * SUM((impression=1 and click = 0)::int)::numeric/COUNT(*), 1) percent_of_purchases_after_impressions_no_clicks
FROM 
    campaign_to_cart
WHERE 
	purchase_flag = 1

-- 6.
SELECT 
	COUNT(*) num_visits_FROM_campaign, 
	SUM((purchase_flag=1)::int) num_visits_FROM_campaign_with_purchase,
	round(100 * SUM((purchase_flag=1)::int)::numeric/COUNT(*), 1) percent_visits_FROM_campaign_with_purchase
FROM 
    campaign_to_cart
WHERE 
	impression = 1

-- 7.
SELECT 
	COUNT(*) num_visits_FROM_impressions, 
	SUM((purchase_flag=0)::int) num_visits_FROM_campaign_no_purchase,
	round(100 * SUM((purchase_flag=0)::int)::numeric/COUNT(*), 1) percent_visits_FROM_campaign_no_purchase
FROM 
    campaign_to_cart
WHERE 
	impression = 1

-- 8.
SELECT  
	COUNT(*) num_visits_not_FROM_campaign,
	SUM((purchase_flag=1)::int) num_visits_aside_campaign_with_purchase,
	round(100 * SUM((purchase_flag=1)::int)::numeric/COUNT(*), 1) percent_visits_aside_campaign_with_purchase
FROM 
    campaign_to_cart
WHERE 
	impression is null or impression = 0

-- 9.
WITH t1 AS (
    SELECT *, 
        UNNEST(STRING_TO_ARRAY(cart_products, ', ')) purchases_FROM_campaign
    FROM 
        campaign_to_cart
    WHERE 
        impression = 1
    ),

t2 AS (
    SELECT 
        user_id, 
        visit_id, 
        COUNT(purchases_FROM_campaign) num_purchases_FROM_campaign
    FROM t1
    GROUP BY 
        user_id, visit_id
    )

SELECT round(avg(num_purchases_FROM_campaign))
FROM t2

-- 10.	
WITH t1 AS (
    SELECT 
        *, 
        UNNEST(STRING_TO_ARRAY(cart_products, ', ')) purchases_outside_campaign
    FROM 
        campaign_to_cart
    WHERE 
        impression is null or impression = 0
    ),

t2 AS (
    SELECT 
        user_id, 
        visit_id, 
        COUNT(purchases_outside_campaign) num_purchases_outside_campaign
    FROM 
        t1
    GROUP BY 
        user_id, visit_id
    )

SELECT round(avg(num_purchases_outside_campaign))
FROM t2


-- 11.
WITH t1 AS (
    SELECT 
        *, 
        UNNEST(STRING_TO_ARRAY(cart_products, ', ')) purchases_FROM_campaign
    FROM 
        campaign_to_cart
    WHERE 
        impression = 1
    ),

t2 AS (
    SELECT 
        user_id, 
        visit_id,
        COUNT(purchases_outside_campaign) num_purchases_FROM_campaign
    FROM 
        t1
    GROUP BY 
        user_id, visit_id
    )

SELECT SUM(num_purchases_FROM_campaign) total_num_purchases
FROM t2

-- 12.
WITH t1 AS (
    SELECT 
        *, 
        UNNEST(STRING_TO_ARRAY(cart_products, ', ')) purchases_outside_campaign
    FROM 
        campaign_to_cart
    WHERE 
        impression is null or impression = 0),

t2 AS (
    SELECT 
        user_id, 
        visit_id, 
        COUNT(purchases_outside_campaign) num_purchases_outside_campaign
    FROM 
        t1
    GROUP BY 
        user_id, visit_id
    )

SELECT SUM(num_purchases_outside_campaign) total_num_purchases
FROM t2


/*
- BONUS QUESTIONS: 
Prepare a single A4 infographic that the team can use for their management reporting sessions, 
be sure to emphasise the most important points from your findings.



Some ideas you might want to investigate further include:

    Identifying users who have received impressions during each campaign period and comparing 
    each metric with other users who did not have an impression event.

    Does clicking on an impression lead to higher purchase rates?
    
	-- ANS:
	-- Clicking on an impression is connected WITH a higher conversion rate
    -- and a higher number of products purchased ON average

    What is the uplift in purchase rate when comparing users who click on a campaign impression versus 
    users who do not receive an impression?
    
	-- ANS:
	-- There's a 45% uplift in purchase rate observed with users who receive an ad impression versus
    -- users who do not

    What if we compare them with users who just receive an impression but do not click?
    
	-- ANS:
	-- 35% of conversions were after impressions and clicks while 5.5% of conversions were
    -- after impressions without ad clicks.

    -- Therefore clicking an ad is connected WITH a 30% increase in conversion rate

    What metrics can you use to quantify the success or failure of each campaign compared to each other?
    -- ANS:
	-- conversions
    -- number of products purchased
    -- repeat purchases ... how many times can each of the campaigns keep attracting the same user to make a purchase
*/










