USE noshowguard;

select count(*) from appointments;
# Result: 990

select count(*) from clinics;
# Result: 8

select SUM(no_show) from appointments;
# Result: 218

INSERT INTO appointments
  (appointment_id, patient_id, clinic_id, booked_on, appt_date, age, gender, distance_km, fee_inr,
  booking_channel, visit_type, reminder_sent, prior_no_shows, status, lead_days, no_show)
  VALUES
  ('A0001', 'P085', 'C08',
  '2024-12-03', '2025-01-17', 38, 'M',
  10.8, 550, 'App', 'Follow-up',
  'Yes', 2, 'No-Show', 45, 1);
# Response: Error Code: 1062. Duplicate entry 'A0001' for key 'appointments.PRIMARY'

-- JOIN appointments to clinics; 
-- for each clinic show clinic_name, city, appointments, no_shows and no_show_pct, where no_show_pct is ROUND(100.0 * SUM(no_show) / COUNT(*), 1). 
-- Keep only clinics with at least 95 appointments (HAVING) and sort by no_show_pct descending. 
-- Then remove the HAVING line, look at all 8 clinics, and note which clinic has the highest rate and how many appointments it has. 
-- In Python, reproduce the clinic counts and no-show counts with groupby and confirm they match the SQL.
select 
	c.clinic_id,
	c.clinic_name,
    c.city,
    count(a.appointment_id) as appointments,
    sum(a.no_show) as no_shows,
    ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1) as no_show_pct
from appointments a
inner join clinics c
on c.clinic_id = a.clinic_id
group by c.clinic_id
having count(a.appointment_id) > 95
order by no_show_pct desc;

select 
	c.clinic_id,
	c.clinic_name,
    c.city,
    count(a.appointment_id) as appointments,
    sum(a.no_show) as no_shows,
    ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1) as no_show_pct
from appointments a
inner join clinics c
on c.clinic_id = a.clinic_id
group by c.clinic_id
order by no_show_pct desc;

-- Using CASE WHEN, put lead_days into four bands 
-- (the labels must come out of the CASE WHEN, not be typed into the data) 
-- — 1-7, 8-14, 15-30, 31+ (upper limits inclusive: 7, 14 and 30 belong to the lower band) 
-- — and show appointments, no-shows and no_show_pct per band in band order 
-- (hint: ORDER BY MIN(lead_days) sorts the bands by how short their lead times are, whereas sorting by the band text would put 15-30 before 8-14).
with band_query as (
	select appointment_id, lead_days, no_show, 
    case 
		when lead_days < 8 then '1-7'
        when lead_days < 15 then '8-14'
        when lead_days < 31 then '15-30'
        else '31+'
	end as bands
    from appointments
)
select 
	bands, 
    count(appointment_id) as appointments, 
    sum(no_show) as total_no_show, 
    ROUND(100.0 * SUM(no_show) / COUNT(*), 1) as no_show_pct
from band_query
group by bands
order by min(lead_days);

-- With a CTE named monthly (month = SUBSTR(appt_date,1,7)), 
-- compute appointments and no_show_pct per month, 
-- then use LAG() with OVER (ORDER BY month) to show the change in percentage points — 
-- this month's rate minus the previous month's rate (blank for January).
with monthly as (
	select
		SUBSTR(appt_date,1,7) as months,
		count(appointment_id) as appointments,
        ROUND(100.0 * SUM(no_show) / COUNT(*), 1) as no_show_pct
	from appointments
    group by SUBSTR(appt_date,1,7)
)
select 
	months, appointments, no_show_pct,
    (no_show_pct - lag(no_show_pct) over (order by months)) as rate_difference
from monthly;

-- With a CTE clinic_rates (clinic, city, no_show_pct), 
-- select every clinic with RANK() OVER (PARTITION BY city ORDER BY no_show_pct DESC) as rank_in_city, 
-- plus a column vs_overall that says 'above', 'below' or 'equal' 
-- (no clinic is exactly equal here, but the query should handle it) 
-- by comparing the clinic's rate with the overall no-show rate computed in a scalar subquery. Order by city, then rank.
SELECT
    ROUND(100.0 * SUM(no_show) / COUNT(*), 2) AS overall_no_show_pct
FROM appointments;

WITH clinic_rates AS (
    SELECT
        c.clinic_name AS clinic,
        c.city,
        ROUND(100.0 * SUM(a.no_show) / COUNT(*), 1) AS no_show_pct
    FROM appointments a
    JOIN clinics c
        ON a.clinic_id = c.clinic_id
    GROUP BY c.clinic_name, c.city
)
SELECT
    clinic,
    city,
    no_show_pct,
    RANK() OVER (
        PARTITION BY city
        ORDER BY no_show_pct DESC
    ) AS rank_in_city,
    CASE
        WHEN no_show_pct > (
            SELECT 100.0 * SUM(no_show) / COUNT(*)
            FROM appointments
        ) THEN 'above'
        WHEN no_show_pct < (
            SELECT 100.0 * SUM(no_show) / COUNT(*)
            FROM appointments
        ) THEN 'below'
        ELSE 'equal'
    END AS vs_overall
FROM clinic_rates
ORDER BY city, rank_in_city;