Case Study Questions
-- 1 Design ERD
-- 2. Digital Analysis
-- Using the available datasets - answer the following questions using a single query for each one:

-- How many users are there?
select 
    count (distinct user_id) num_cookies
from 
    clique_bait.users

-- How many cookies does each user have on average?

with count_cookies as (
	select 
        user_id, 
        count(cookie_id) num_cookies
	from 
        clique_bait.users
	group by 1
    )

select 
    round(avg(num_cookies))
from
    count_cookies

-- What is the number of unique visits by all users per month?
select 
    to_char(e.event_time, 'Month') month_of_year, 
    date_trunc('month', e.event_time ) month_date, 
    u.user_id, 
    count(distinct e.visit_id) num_visits
from 
    clique_bait.users u
join 
    clique_bait.events e
on 
    u.cookie_id = e.cookie_id
group by 2, 1, 3
order by 2, 3
	
-- What is the number of events for each event type?
select 
    count(*) num_events, 
    event_type
from 
    clique_bait.events
group by 2

-- What is the percentage of visits which have a purchase event?
with count_visits as (
	select 
		count(distinct visit_id) num_unique_visit, 
		count(case when event_name='Purchase' then visit_id end) num_visits_with_purchase
	from 
		clique_bait.events e
	join 
		clique_bait.event_identifier ei
	on 
		e.event_type = ei.event_type
    )
	
select 
	round(((num_visits_with_purchase/num_unique_visit::decimal)*100), 2) percent_of_visits_with_purchase
from 
	count_visits
	
    
--What is the percentage of visits which view the checkout page but do not have a purchase event?
with page_event_string as (
    select 
        visit_id, 
        string_agg(page_id::text, ', ') page_str, 
        string_agg(event_name, ', ') event_str 
	from 
		clique_bait.events e
	join 
		clique_bait.event_identifier ei
	on 
		e.event_type = ei.event_type
	group by 
        visit_id
    ),
		
count_visits as (
    select 
		count(case when page_str like '%12%' and event_str not like '%Purchase%' then visit_id end) num_checkout_page_visits_without_purchase, -- 12 being the page id for the checkout page
	   (select count(distinct visit_id) from clique_bait.events) num_unique_visits
    from page_event_string
    )
	
select 
    round(((num_checkout_page_visits_without_purchase::decimal/num_unique_visits) * 100), 2) percent_checkout_visits_without_purchase
from
    count_visits
	
-- What are the top 3 pages by number of views?
select 
    count(*) num_page_views, page_id	
from 
	clique_bait.events e
join 
	clique_bait.event_identifier ei
on 
	e.event_type = ei.event_type
group by page_id
order by 1 desc
limit 3

-- What is the number of views and cart adds for each product category?
select 
    product_category, 
    count(*) num_views, 
    count(case when event_name = 'Add to Cart' then visit_id end) num_add_to_cart_events
		
from 
	clique_bait.events e
join 
	clique_bait.event_identifier ei
on 
	e.event_type = ei.event_type
join 
	clique_bait.page_hierarchy ph
on 
	ph.page_id = e.page_id
where 
    product_category is not null
group by 1

-- What are the top 3 products by purchases?
with all_events_string as (
	select 
		visit_id, 
		string_agg(ph.page_name, ', ') pn_str,
        string_agg(e.page_id::text, ', ') page_str, 
        string_agg(event_name, ', ') event_str 
	from 
		clique_bait.events e
	join 
		clique_bait.event_identifier ei
	on 
		e.event_type = ei.event_type
	join 
		clique_bait.page_hierarchy ph
	on 
		ph.page_id = e.page_id
	group by 1),
	
includes_purchase_event as (
	select 
		visit_id, 
		unnest(string_to_array(event_str, ', ')) event_, 
		unnest(string_to_array(pn_str, ', ')) product_page, 
		unnest(string_to_array(page_str, ', ')) page_id_
	from 
		all_events_string
	where 
		event_str like '%Purchase%')
	
select 
	count(*) num_purchases, 
	product_page
from 
	includes_purchase_event 
where 
	event_ = 'Add to Cart'
group by 2
order by 1 desc
limit 3
	
	


        -- 3. Product Funnel Analysis
Using a single SQL query - create a new output table which has the following details:

How many times was each product viewed?
How many times was each product added to cart?
How many times was each product added to a cart but not purchased (abandoned)?
How many times was each product purchased?

CREATE TABLE product_stats AS (
with views_and_cart_adds as (	
	select 
		product_id,
		sum((event_name='Page View')::int) num_page_views, 
		sum((event_name='Add to Cart')::int) num_times_added_to_cart
	from 
		clique_bait.events e
	join 
		clique_bait.event_identifier ei
	on 
		e.event_type = ei.event_type
	join 
		clique_bait.page_hierarchy ph
	on 
		ph.page_id = e.page_id
	where product_id is not null
	group by product_id
	),
	
product_and_event_agg as (
	select 
		visit_id, 
		string_agg(coalesce(ph.product_id, 200)::text, ', ') pid_str,
        string_agg(event_name, ', ') event_str 
	from 
		clique_bait.events e
	join 
		clique_bait.event_identifier ei
	on 
		e.event_type = ei.event_type
	join 
		clique_bait.page_hierarchy ph
	on 
		ph.page_id = e.page_id
	group by 1),
	
added_not_purchased as (
	select 
		visit_id, 
		unnest(string_to_array(event_str, ', ')) event_, 
		unnest(string_to_array(pid_str, ', ')) p_id
	from 
		product_and_event_agg 
	where 
		event_str like '%Add to Cart%' and event_str not like '%Purchase%'), 

count_not_purchased as (
	select 
		p_id::int, 
		sum((event_ = 'Add to Cart')::int) num_times_not_purchased
	from 
		added_not_purchased
	where p_id != '200'
	group by p_id),
	
purchased as (select 
		visit_id, 
		unnest(string_to_array(event_str, ', ')) event_, 
		unnest(string_to_array(pid_str, ', ')) p_id
	from 
		product_and_event_agg 
	where 
		event_str like '%Purchase%'), 

count_purchased as (
	select 
		p_id::int, 
		sum((event_ = 'Add to Cart')::int) num_times_purchased
	from purchased
	where p_id != '200'
	group by p_id)
	
select 
	product_id, 
	num_page_views, 
	num_times_added_to_cart, 
	num_times_not_purchased, 
	num_times_purchased 
from 
	views_and_cart_adds v
join 
	count_not_purchased np
on 
	v.product_id = np.p_id
join 
	count_purchased p
on 
	p.p_id = np.p_id
order by 1
);

-- Additionally, create another table which further aggregates the data for the above points 
-- but this time for each product category instead of individual products.

CREATE TABLE product_category_stats AS (
with views_and_cart_adds as (	
	select 
		product_category,
		sum((event_name='Page View')::int) num_page_views, 
		sum((event_name='Add to Cart')::int) num_times_added_to_cart
	from 
		clique_bait.events e
	join 
		clique_bait.event_identifier ei
	on 
		e.event_type = ei.event_type
	join 
		clique_bait.page_hierarchy ph
	on 
		ph.page_id = e.page_id
	where product_id is not null
	group by product_category
	),
	
product_and_event_agg as (
	select 
		visit_id, 
		string_agg(coalesce(ph.product_category, 'none')::text, ', ') pcat_str,
        string_agg(event_name, ', ') event_str 
	from 
		clique_bait.events e
	join 
		clique_bait.event_identifier ei
	on 
		e.event_type = ei.event_type
	join 
		clique_bait.page_hierarchy ph
	on 
		ph.page_id = e.page_id
	group by 1),
	
added_not_purchased as (
	select 
		visit_id, 
		unnest(string_to_array(event_str, ', ')) event_, 
		unnest(string_to_array(pcat_str, ', ')) p_cat
	from 
		product_and_event_agg 
	where 
		event_str like '%Add to Cart%' and event_str not like '%Purchase%'), 

count_not_purchased as (
	select 
		p_cat, 
		sum((event_ = 'Add to Cart')::int) num_times_not_purchased
	from 
		added_not_purchased
	where p_cat != 'none'
	group by p_cat),
	
purchased as (select 
		visit_id, 
		unnest(string_to_array(event_str, ', ')) event_, 
		unnest(string_to_array(pcat_str, ', ')) p_cat
	from 
		product_and_event_agg 
	where 
		event_str like '%Purchase%'), 

count_purchased as (
	select 
		p_cat, 
		sum((event_ = 'Add to Cart')::int) num_times_purchased
	from purchased
	where p_cat != '200'
	group by p_cat)
	
select 
	product_category, 
	num_page_views, 
	num_times_added_to_cart, 
	num_times_not_purchased, 
	num_times_purchased 
from 
	views_and_cart_adds v
join 
	count_not_purchased cn
on 
	v.product_category = cn.p_cat
join 
	count_purchased cp
on 
	cp.p_cat = cn.p_cat
order by 1
);

    -- Use your 2 new output tables - answer the following questions:

--Which product had the most views, cart adds and purchases?
select 
    page_name as product
from 
    product_stats ps
join 
    clique_bait.page_hierarchy ph
on 
    ps.product_id = ph.product_id
order by 
    num_page_views desc, 
    num_times_added_to_cart desc, 
    num_times_purchased desc
limit 1

--Which product was most likely to be abandoned?
select 
	page_name as product, 
	round((num_times_not_purchased::numeric/num_times_added_to_cart) * 100, 1) abandonment_rate
from 
	product_stats ps
join 
	clique_bait.page_hierarchy ph
on 
	ps.product_id = ph.product_id
order by abandonment_rate desc
limit 1

--Which product had the highest view to purchase percentage?
select 
	page_name as product, 
	round((num_times_purchased::numeric/num_page_views) * 100, 1) purchase_view_percentage
from 
	product_stats ps
join 
	clique_bait.page_hierarchy ph
on 
	ps.product_id = ph.product_id
order by purchase_view_percentage desc
limit 1

-- What is the average conversion rate from view to cart add?
    -- product
with conversion_rate as (
	select 
		page_name as product, 
		round((num_times_added_to_cart::numeric/num_page_views) * 100, 2) view_to_cart_conversion_rate
	from 
		product_stats ps
	join 
		clique_bait.page_hierarchy ph
	on 
		ps.product_id = ph.product_id)
		
select round(avg(view_to_cart_conversion_rate), 2) avg_conversion_rate
from conversion_rate

    -- product category
select round((avg(num_times_added_to_cart::numeric/num_page_views) * 100), 2) avg_conversion_rate
from product_category_stats 

-- What is the average conversion rate from cart add to purchase?
    -- product
with conversion_rate as (
	select 
		page_name as product, 
		round((num_times_purchased::numeric/num_times_added_to_cart) * 100, 2) cart_to_purchase_conversion_rate
	from 
		product_stats ps
	join 
		clique_bait.page_hierarchy ph
	on 
		ps.product_id = ph.product_id)
		
select round(avg(cart_to_purchase_conversion_rate), 2) avg_conversion_rate
from conversion_rate

    -- product category
select round((avg(num_times_purchased::numeric/num_times_added_to_cart) * 100), 2) avg_conversion_rate
from product_category_stats 


        -- 4. Campaign Analysis
-- Generate a table that has 1 single row for every unique visit_id record and has the following columns:

-- user_id
-- visit_id
-- visit_start_time: the earliest event_time for each visit
-- page_views: count of page views for each visit
-- cart_adds: count of product cart add events for each visit
-- purchase: 1/0 flag if a purchase event exists for each visit
-- campaign_name: map the visit to a campaign if the visit_start_time falls between the start_date and end_date
-- impression: count of ad impressions for each visit
-- click: count of ad clicks for each visit
-- (Optional column) 
-- cart_products: a comma separated text value with products added to the cart sorted by 
-- the order they were added to the cart 
-- (hint: use the sequence_number)

CREATE TABLE campaign_to_cart AS(
with user_visit as (
	select 
		cu.user_id, 
		ce.visit_id,
		min(event_time) over (partition by visit_id) visit_start_time,
		sum((event_type=1)::int) over (partition by visit_id) page_views,
		sum((event_type=2)::int) over (partition by visit_id) cart_adds, 
		case when (sum((event_type=3)::int) over (partition by visit_id)) > 0 then 1 else 0 end as purchase_flag,
		cc.campaign_name,
		sum(case when campaign_id is not null then (event_type=4)::int else null end) over (partition by visit_id) impression,
		sum(case when campaign_id is not null then (event_type=5)::int else null end) over (partition by visit_id) click
    from
        clique_bait.users cu
    join 
        clique_bait.events ce
    on 
        cu.cookie_id = ce.cookie_id
    left join 
        clique_bait.campaign_identifier cc
    on 
        ce.event_time > cc.start_date
    and 
        ce.event_time < cc.end_date
    order by 6,5
    ),

add_to_cart_order as (
	select 
		visit_id, 
		cookie_id, 
		string_agg(sequence_number::text, ', ') sequence_str, 
		string_agg(page_name, ', ') product_str 
	from (
			select visit_id, cookie_id, event_type, sequence_number, page_name, ce.page_id
			from clique_bait.events ce 
			join clique_bait.page_hierarchy cp 
			on ce.page_id = cp.page_id 
			where event_type = 2 
			order by visit_id, cookie_id, sequence_number
			) ord
	group by 1,2
    )

select distinct
    uv.*, 
    ad.product_str as cart_products
from 
    user_visit uv
left join 
    add_to_cart_order ad
on 
    uv.visit_id = ad.visit_id);


Use the subsequent dataset to generate at least 5 insights for the Clique Bait team 
-- visits
select 
	count(*) all_visits, 
	(select count(*) from campaign_to_cart where impression = 1) visits_after_impression,
	round(100 * (select count(*) from campaign_to_cart where impression = 1)/count(*)::numeric, 1) percent_visits_after_impression
from 
    campaign_to_cart

--1. 500 unique visitors
--2. 3564 visits
--3. 80% of traffic to the site did not come via the ad campaigns (2817 visits)
--4. 20% of traffic to the site came via the ad campaigns (747 visits)
--5. 50% of visits were converted. i.e. visit ended in a purchase (1777 visits)
--6. 35% of conversions happened after ad impressions or clicks
--7. 5.5% of conversions happened after only ad impressions (i.e. the ad was not clicked)
--8. 85% conversion rate of the traffic from ad campaigns
--9. 40% conversion rate of the non-campaign traffic 
--10. Average number of purchases by visits from campaign = 5
--11. Average number of purchases by non_campaign visits = 3
--12. 3771 products bought in visits from campaign
--13. 4680 products bought in non-campaign visits
--14. 5:6 i.e. For every 5 products bought during campaign-related visits roughly 6 products were bought during non-campaign visits


-- 1.
select 
    count(*) num_visits
from 
    campaign_to_cart

-- 2.
select 
    count(*) all_visits, 
    (select count(*) from campaign_to_cart where impression = 1) visits_after_impression,
    round(100*(select count(*) from campaign_to_cart where impression = 1) / count(*)::numeric, 1) percent_visits_after_impression
from campaign_to_cart

-- 3.
select 
	count(*) all_visits, 
	(select count(*) from campaign_to_cart where purchase_flag = 1) purchase_after_visit,
	round(100 * (select count(*) from campaign_to_cart where purchase_flag = 1)/count(*)::numeric, 1) percent_purchase_after_visit
from 
    campaign_to_cart

-- 4.
select 
	count(*) num_purchases, 
	sum((impression=1)::int) num_impressions, 
	round(100 * sum((impression=1)::int)::numeric/count(*), 1) num_purchases
from 
    campaign_to_cart
where 
	purchase_flag = 1

-- 5.
select 
	count(*) num_purchases, 
	sum((impression=1 and click = 0)::int) num_impressions_no_clicks,
	round(100 * sum((impression=1 and click = 0)::int)::numeric/count(*), 1) percent_of_purchases_after_impressions_no_clicks
from 
    campaign_to_cart
where 
	purchase_flag = 1

-- 6.
select 
	count(*) num_visits_from_campaign, 
	sum((purchase_flag=1)::int) num_visits_from_campaign_with_purchase,
	round(100 * sum((purchase_flag=1)::int)::numeric/count(*), 1) percent_visits_from_campaign_with_purchase
from 
    campaign_to_cart
where 
	impression = 1

-- 7.
select 
	count(*) num_visits_from_impressions, 
	sum((purchase_flag=0)::int) num_visits_from_campaign_no_purchase,
	round(100 * sum((purchase_flag=0)::int)::numeric/count(*), 1) percent_visits_from_campaign_no_purchase
from 
    campaign_to_cart
where 
	impression = 1

-- 8.
select  
	count(*) num_visits_not_from_campaign,
	sum((purchase_flag=1)::int) num_visits_aside_campaign_with_purchase,
	round(100 * sum((purchase_flag=1)::int)::numeric/count(*), 1) percent_visits_aside_campaign_with_purchase
from 
    campaign_to_cart
where 
	impression is null or impression = 0

-- 9.
with t1 as (
    select *, 
        unnest(string_to_array(cart_products, ', ')) purchases_from_campaign
    from 
        campaign_to_cart
    where 
        impression = 1
    ),

t2 as (
    select 
        user_id, 
        visit_id, 
        count(purchases_from_campaign) num_purchases_from_campaign
    from t1
    group by 
        user_id, visit_id
    )

select round(avg(num_purchases_from_campaign))
from t2

-- 10.	
with t1 as (
    select 
        *, 
        unnest(string_to_array(cart_products, ', ')) purchases_outside_campaign
    from 
        campaign_to_cart
    where 
        impression is null or impression = 0
    ),

t2 as (
    select 
        user_id, 
        visit_id, 
        count(purchases_outside_campaign) num_purchases_outside_campaign
    from 
        t1
    group by 
        user_id, visit_id
    )

select round(avg(num_purchases_outside_campaign))
from t2


-- 11.
with t1 as (
    select 
        *, 
        unnest(string_to_array(cart_products, ', ')) purchases_from_campaign
    from 
        campaign_to_cart
    where 
        impression = 1
    ),

t2 as (
    select 
        user_id, 
        visit_id,
        count(purchases_outside_campaign) num_purchases_from_campaign
    from 
        t1
    group by 
        user_id, visit_id
    )

select sum(num_purchases_from_campaign) total_num_purchases
from t2

-- 12.
with t1 as (
    select 
        *, 
        unnest(string_to_array(cart_products, ', ')) purchases_outside_campaign
    from 
        campaign_to_cart
    where 
        impression is null or impression = 0),

t2 as (
    select 
        user_id, 
        visit_id, 
        count(purchases_outside_campaign) num_purchases_outside_campaign
    from 
        t1
    group by 
        user_id, visit_id
    )

select sum(num_purchases_outside_campaign) total_num_purchases
from t2



- Bonus: 
Prepare a single A4 infographic that the team can use for their management reporting sessions, 
be sure to emphasise the most important points from your findings.



Some ideas you might want to investigate further include:

    Identifying users who have received impressions during each campaign period and comparing 
    each metric with other users who did not have an impression event.

    Does clicking on an impression lead to higher purchase rates?
    -- Clicking on an impression is connected with a higher conversion rate
    -- and a higher number of products purchased on average

    What is the uplift in purchase rate when comparing users who click on a campaign impression versus 
    users who do not receive an impression?
    -- There's a 45% uplift in purchase rate observed with users who receive an ad impression versus
    -- users who do not

    What if we compare them with users who just receive an impression but do not click?
    -- 35% of conversions were after impressions and clicks while 5.5% of conversions were
    -- after impressions without ad clicks

    -- Clicking an ad is connected with a 30% increase in conversion rate

    What metrics can you use to quantify the success or failure of each campaign compared to each other?
    conversions
    number of products purchased
    repeat purchases ... how many times can each of the campaigns keep attracting the same user to make a purchase











