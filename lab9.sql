-- ===========================================================================
--  Laboratory Work 9: Stored Procedures and User-Defined Functions
--  Solutions for Parts 2-7, written answers, and Lab Questions.
--
--  Usage:  createdb citybike
--          psql -d citybike -f lab9_setup.sql      -- Part 1 (given)
--          psql -d citybike -f surname_lab9.sql
--
--  Run on a CLEAN database, once. Lines starting with "-- =>" show the
--  expected result of the call above them (computed from the sample data);
--  paste your own real output into the report as text.
--  The three exercises whose errors you must copy verbatim (4.3, 5.3, 5.4) are
--  wrapped in DO blocks that catch the error and print it as a NOTICE, so the
--  script keeps running. You can also run the bare failing call by itself in
--  psql to get the exact text with its LINE/CONTEXT lines.
-- ===========================================================================

-- ###########################################################################
-- Part 2: Your first function
-- ###########################################################################

-- Exercise 2.1
CREATE OR REPLACE FUNCTION rental_days(p_rental_id INT) RETURNS INT AS $$
DECLARE
    d INT;
BEGIN
    SELECT end_date - start_date INTO d
    FROM rentals
    WHERE rental_id = p_rental_id;
    RETURN d;
END; $$ LANGUAGE plpgsql;

SELECT rental_days(2);      -- => 5
SELECT rental_days(11);     -- => 8
SELECT rental_days(19);     -- => NULL
SELECT rental_days(999);    -- => NULL
-- Q: Both return NULL, but for different reasons. Rental 19 EXISTS but is
--    still open: end_date is NULL, so end_date - start_date is NULL. Rental 999
--    does not exist: SELECT ... INTO finds no row and (without STRICT) sets the
--    variable to NULL.

-- Exercise 2.2
CREATE OR REPLACE FUNCTION member_rental_count(p_member_id INT) RETURNS INT AS $$
DECLARE
    c INT;
BEGIN
    SELECT COUNT(*) INTO c FROM rentals WHERE member_id = p_member_id;
    RETURN c;
END; $$ LANGUAGE plpgsql;

SELECT member_rental_count(1);   -- => 5
SELECT member_rental_count(5);   -- => 4
SELECT member_rental_count(6);   -- => 0
-- Q: An aggregate without GROUP BY always returns exactly one row, even over
--    zero input rows. COUNT of zero rows is defined as 0 (SUM/AVG/MAX would be
--    NULL). It does not check whether the member exists, it just counts the
--    matching rentals rows: none for member 6, none for member 99.

-- Exercise 2.3
CREATE OR REPLACE FUNCTION station_city(p_station_id INT) RETURNS VARCHAR AS $$
DECLARE
    c VARCHAR;
BEGIN
    SELECT city INTO c FROM stations WHERE station_id = p_station_id;
    RETURN c;
END; $$ LANGUAGE plpgsql;

SELECT station_city(30);   -- => Astana
SELECT station_city(77);   -- => NULL (no such station)

-- Exercise 2.4
SELECT rental_id, member_id, rental_days(rental_id) AS days
FROM rentals
WHERE rental_days(rental_id) > 4
ORDER BY days DESC, rental_id;
-- => (11,3,8) (4,1,7) (15,5,7) (17,5,7) (7,2,6) (14,4,6) (20,4,6) (2,1,5)

-- ###########################################################################
-- Part 3: Parameter modes
-- ###########################################################################

-- Exercise 3.1  (IN, the default mode)
CREATE OR REPLACE FUNCTION fee_with_discount(p_fee NUMERIC, p_percent NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN ROUND(p_fee * (1 - p_percent / 100), 2);
END; $$ LANGUAGE plpgsql;

SELECT fee_with_discount(74.00, 15);   -- => 62.90

-- Exercise 3.2  (OUT)
CREATE OR REPLACE FUNCTION member_stats(
    p_member_id INT,
    OUT rental_cnt INT,
    OUT total_fee NUMERIC,
    OUT last_start DATE)
AS $$
BEGIN
    SELECT COUNT(*), COALESCE(SUM(fee), 0), MAX(start_date)
    INTO rental_cnt, total_fee, last_start
    FROM rentals
    WHERE member_id = p_member_id;
END; $$ LANGUAGE plpgsql;

SELECT member_stats(3);      -- => (5,164.75,2025-06-01)   one column, record text
SELECT * FROM member_stats(3);
-- => rental_cnt=5 | total_fee=164.75 | last_start=2025-06-01   three columns
SELECT * FROM member_stats(6);   -- => 0 | 0 | NULL
-- Q: SELECT member_stats(3) returns ONE column holding the whole record as
--    text "(5,164.75,2025-06-01)". SELECT * FROM member_stats(3) expands it
--    into three separate named, typed columns. Use the FROM form inside a larger
--    query: the columns can be filtered, sorted, joined and used in expressions
--    (e.g. FROM members m, LATERAL member_stats(m.member_id) s).
--    Member 6: 0 rentals, total 0 (thanks to COALESCE) and last_start NULL
--    (MAX of nothing).

-- Exercise 3.3  (INOUT)
CREATE OR REPLACE FUNCTION apply_late_fee(INOUT p_fee NUMERIC) AS $$
BEGIN
    p_fee := p_fee + 5.00;
END; $$ LANGUAGE plpgsql;

SELECT apply_late_fee(fee) FROM rentals WHERE rental_id = 1;   -- => 18.50
-- Q: An INOUT parameter is both an input and an output column. When the
--    function ends, the current value of every OUT/INOUT parameter is returned
--    automatically, so no RETURNS clause or RETURN statement is needed.

-- Exercise 3.4  (VARIADIC)
CREATE OR REPLACE FUNCTION fee_summary(
    VARIADIC p_fees NUMERIC[],
    OUT total NUMERIC,
    OUT average NUMERIC,
    OUT largest NUMERIC)
AS $$
BEGIN
    SELECT SUM(p_fees[i]), ROUND(AVG(p_fees[i]), 2), MAX(p_fees[i])
    INTO total, average, largest
    FROM generate_subscripts(p_fees, 1) g(i);
END; $$ LANGUAGE plpgsql;

SELECT * FROM fee_summary(13.50, 35.00, 18.50, 31.50);
-- => total=98.50 | average=24.63 | largest=35.00
SELECT * FROM fee_summary();
-- => NULL | NULL | NULL
-- Q: A variadic parameter accepts zero or more values, so the call is allowed
--    and the function receives an EMPTY array. generate_subscripts() over an
--    empty array yields no rows, so SUM/AVG/MAX all return NULL.
--    It must be last because the caller's trailing arguments are all collected
--    into the array: with a parameter after it, a call like f(1, 2, 3) cannot
--    tell where the array stops and the next parameter starts. (OUT parameters
--    do not count: they are not part of the call's argument list.)

-- Exercise 3.5  (modes)
-- (a) id of the row to look up        -> IN: read-only input, the function
--                                        must not change what the caller passed.
-- (b) running balance passed in and   -> INOUT: the caller supplies the value,
--     returned updated                   the function changes it and returns it.
-- (c) list of station ids, any length -> VARIADIC (an array collecting any
--                                        number of trailing arguments).
-- (d) two statistics from one pass    -> OUT (two OUT parameters, filled by one
--                                        SELECT ... INTO, returned as a row).

-- ###########################################################################
-- Part 4: Defaults and overloading
-- ###########################################################################

-- Exercise 4.1
CREATE OR REPLACE FUNCTION total_fees(p_member_id INT) RETURNS NUMERIC AS $$
DECLARE
    t NUMERIC;
BEGIN
    SELECT COALESCE(SUM(fee), 0) INTO t FROM rentals WHERE member_id = p_member_id;
    RETURN t;
END; $$ LANGUAGE plpgsql;

SELECT total_fees(1);   -- => 98.50  (open rental 19 has NULL fee: ignored by SUM)
SELECT total_fees(6);   -- => 0

-- Exercise 4.2  (overload on argument count)
CREATE OR REPLACE FUNCTION total_fees(p_member_id INT, p_from_date DATE)
RETURNS NUMERIC AS $$
DECLARE
    t NUMERIC;
BEGIN
    SELECT COALESCE(SUM(fee), 0) INTO t
    FROM rentals
    WHERE member_id = p_member_id AND start_date >= p_from_date;
    RETURN t;
END; $$ LANGUAGE plpgsql;

SELECT total_fees(1, DATE '2024-01-01');   -- => 98.50
SELECT total_fees(1, DATE '2025-01-01');   -- => 50.00  (rentals 3 and 4)

-- \df total_fees    or:
SELECT oid::regprocedure AS signature FROM pg_proc WHERE proname = 'total_fees';
-- => total_fees(integer) and total_fees(integer,date)

-- Exercise 4.3  (add a default: same signature, so OR REPLACE swaps the body)
CREATE OR REPLACE FUNCTION total_fees(p_member_id INT,
                                      p_from_date DATE DEFAULT DATE '2025-01-01')
RETURNS NUMERIC AS $$
DECLARE
    t NUMERIC;
BEGIN
    SELECT COALESCE(SUM(fee), 0) INTO t
    FROM rentals
    WHERE member_id = p_member_id AND start_date >= p_from_date;
    RETURN t;
END; $$ LANGUAGE plpgsql;

-- SELECT total_fees(1);    -- the failing call, run it bare to get the full text
DO $$
DECLARE
    v_hint TEXT;
BEGIN
    PERFORM total_fees(1);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    RAISE NOTICE 'ERROR:  %', SQLERRM;
    RAISE NOTICE 'HINT:  %', v_hint;
END $$;
-- => ERROR:  function total_fees(integer) is not unique
--    HINT:   Could not choose a best candidate function. You might need to add
--            explicit type casts.
-- Q: The call total_fees(1) matches BOTH functions equally well:
--    total_fees(integer) directly, and total_fees(integer, date) by filling in
--    the default for the second argument. Both take an integer first argument,
--    so PostgreSQL's ranking rules cannot prefer either, and it refuses to guess.

-- Exercise 4.4
DROP FUNCTION total_fees(INTEGER);
SELECT total_fees(1);   -- => 50.00
-- Q: The two-argument version now answers, using its default date 2025-01-01,
--    so it returns 50.00 (only rentals 3 and 4). Dropping the OTHER version
--    (the two-argument one) would have left total_fees(integer), which sums
--    all rentals and returns 98.50, so the answer would be different.

-- Exercise 4.5  (overload on type)
CREATE OR REPLACE FUNCTION total_fees(p_name VARCHAR) RETURNS NUMERIC AS $$
DECLARE
    t NUMERIC;
BEGIN
    SELECT COALESCE(SUM(r.fee), 0) INTO t
    FROM rentals r
    JOIN members m ON m.member_id = r.member_id
    WHERE m.full_name = p_name;
    RETURN t;
END; $$ LANGUAGE plpgsql;

SELECT total_fees('Aisha Nurlanova');   -- => 98.50  (all her rentals)
SELECT total_fees(1);                    -- => 50.00  (default: since 2025-01-01)
-- Q: Different first-argument TYPES make the calls distinguishable: an integer
--    cannot be implicitly cast to varchar, so total_fees(1) can only reach
--    total_fees(integer, date), and a string literal is resolved in favour of
--    the string-category candidate total_fees(varchar). So no ambiguity.
--    The results differ because the name version has no date filter and sums
--    every rental of the member (98.50), whereas total_fees(1) applies the
--    default p_from_date = 2025-01-01 and sums only rentals 3 and 4 (50.00).

-- ###########################################################################
-- Part 5: Functions that return a table
-- ###########################################################################

-- Exercise 5.1
CREATE OR REPLACE FUNCTION find_bikes(p_pattern VARCHAR)
RETURNS TABLE (found_id INT, found_model VARCHAR, found_rate NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT bike_id, model, daily_rate
    FROM bikes
    WHERE model ILIKE p_pattern
    ORDER BY bike_id;
END; $$ LANGUAGE plpgsql;

SELECT * FROM find_bikes('%road%');   -- => (105,Road Sprint,9.25) (108,Road Sprint,9.25)
SELECT * FROM find_bikes('%Mini');    -- => (106,Folding Mini,3.75)
SELECT find_bikes('%road%');
-- => ONE column named find_bikes with rows like (105,"Road Sprint",9.25).
-- Q: Without FROM, the set-returning function sits in the select list, so each
--    returned row is packed into a single composite (record) value instead of
--    being expanded into the three declared columns.

-- Exercise 5.2
CREATE OR REPLACE FUNCTION member_history(p_member_id INT)
RETURNS TABLE (h_rental_id INT, h_model VARCHAR, h_station VARCHAR,
               h_days INT, h_fee NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT r.rental_id, b.model, s.station_name,
           r.end_date - r.start_date, r.fee
    FROM rentals r
    JOIN bikes b          ON b.bike_id = r.bike_id
    LEFT JOIN stations s  ON s.station_id = b.station_id
    WHERE r.member_id = p_member_id
    ORDER BY r.start_date;
END; $$ LANGUAGE plpgsql;

SELECT * FROM member_history(3);
-- => (8,Mountain X,Expo Gate,4,28.00)  (9,Road Sprint,Expo Gate,3,27.75)
--    (10,Mountain X,Expo Gate,1,7.00)  (21,Mountain X,Riverside,4,28.00)
--    (11,Road Sprint,Expo Gate,8,74.00)

-- Exercise 5.3  (name collision)
CREATE OR REPLACE FUNCTION bike_list(p_station_id INT)
RETURNS TABLE (bike_id INT, model VARCHAR) AS $$
BEGIN
    RETURN QUERY SELECT bike_id, model FROM bikes WHERE station_id = p_station_id;
END; $$ LANGUAGE plpgsql;

-- SELECT * FROM bike_list(10);     -- the failing call, run it bare for full text
DO $$
DECLARE
    v_detail TEXT;
BEGIN
    PERFORM * FROM bike_list(10);
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RAISE NOTICE 'ERROR:  %', SQLERRM;
    RAISE NOTICE 'DETAIL:  %', v_detail;
END $$;
-- => ERROR:  column reference "bike_id" is ambiguous
--    DETAIL: It could refer to either a PL/pgSQL variable or a table column.
-- Q: The RETURNS TABLE columns bike_id and model are also PL/pgSQL variables
--    inside the body, so in the query "bike_id" and "model" could mean the
--    variable or the table column. The CREATE succeeds because PL/pgSQL only
--    checks syntax when the function is created; the SQL inside is analysed and
--    planned at the first call, which is where the ambiguity is found.

-- Fix 1: rename the output columns
DROP FUNCTION bike_list(INT);   -- OR REPLACE cannot change the result columns
CREATE FUNCTION bike_list(p_station_id INT)
RETURNS TABLE (b_id INT, b_model VARCHAR) AS $$
BEGIN
    RETURN QUERY SELECT bike_id, model FROM bikes WHERE station_id = p_station_id;
END; $$ LANGUAGE plpgsql;
SELECT * FROM bike_list(10);    -- => (101,City Cruiser) (102,City Cruiser) (108,Road Sprint)

-- Fix 2: keep the names, qualify the table columns with an alias
DROP FUNCTION bike_list(INT);
CREATE FUNCTION bike_list(p_station_id INT)
RETURNS TABLE (bike_id INT, model VARCHAR) AS $$
BEGIN
    RETURN QUERY SELECT b.bike_id, b.model FROM bikes b WHERE b.station_id = p_station_id;
END; $$ LANGUAGE plpgsql;
SELECT * FROM bike_list(10);    -- same three rows

-- Exercise 5.4  (cast the output)
-- Without casts: COUNT(*) is BIGINT, the declared columns are INT
CREATE OR REPLACE FUNCTION station_board_nocast(p_city VARCHAR)
RETURNS TABLE (s_name VARCHAR, s_bikes INT, s_free INT) AS $$
BEGIN
    RETURN QUERY
    SELECT s.station_name, COUNT(b.bike_id), s.capacity - COUNT(b.bike_id)
    FROM stations s
    LEFT JOIN bikes b ON b.station_id = s.station_id
    WHERE s.city = p_city
    GROUP BY s.station_id, s.station_name, s.capacity;
END; $$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_detail TEXT;
BEGIN
    PERFORM * FROM station_board_nocast('Almaty');
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RAISE NOTICE 'ERROR:  %', SQLERRM;
    RAISE NOTICE 'DETAIL:  %', v_detail;
END $$;
-- => ERROR:  structure of query does not match function result type
--    DETAIL: Returned type bigint at ordinal position 2, but query expects integer.
-- Q: RETURN QUERY requires the column types to match the declaration exactly;
--    it does not insert the BIGINT -> INT cast for you. Fix: cast explicitly.
DROP FUNCTION station_board_nocast(VARCHAR);

CREATE OR REPLACE FUNCTION station_board(p_city VARCHAR)
RETURNS TABLE (s_name VARCHAR, s_bikes INT, s_free INT) AS $$
BEGIN
    RETURN QUERY
    SELECT s.station_name,
           COUNT(b.bike_id)::INT,
           (s.capacity - COUNT(b.bike_id))::INT
    FROM stations s
    LEFT JOIN bikes b ON b.station_id = s.station_id
    WHERE s.city = p_city
    GROUP BY s.station_id, s.station_name, s.capacity
    ORDER BY s.station_id;
END; $$ LANGUAGE plpgsql;

SELECT * FROM station_board('Almaty');
-- => (Central Park,3,1)  (Riverside,2,1)
SELECT * FROM station_board('Astana');
-- => (Expo Gate,2,3)  (Depot,0,0)

-- ###########################################################################
-- Part 6: Block structure, DO blocks and subblocks
-- ###########################################################################

-- Exercise 6.1
DO $$
<<rental_report>>
DECLARE
    total_rentals INTEGER := 0;
BEGIN
    SELECT COUNT(*) INTO total_rentals FROM rentals;
    RAISE NOTICE 'The rentals table holds % rows.', total_rentals;
END rental_report $$;
-- => NOTICE:  The rentals table holds 22 rows.
-- Q: A different label after END is a compile-time error:
--      ERROR:  end label "wrong_name" differs from block's label "rental_report"
--    The block is rejected before it runs.

-- Exercise 6.2
DO $$
<<outer_blk>>
DECLARE
    fee_total NUMERIC;
BEGIN
    SELECT SUM(fee) INTO fee_total FROM rentals;
    RAISE NOTICE 'Outer, before subblock:  %', fee_total;

    DECLARE
        fee_total NUMERIC;           -- hides the outer variable
    BEGIN
        SELECT SUM(fee) INTO fee_total
        FROM rentals WHERE start_date >= DATE '2025-01-01';
        RAISE NOTICE 'Subblock, own value:     %', fee_total;
        RAISE NOTICE 'Outer via its label:     %', outer_blk.fee_total;
    END;

    RAISE NOTICE 'Outer, after subblock:   %', fee_total;
END outer_blk $$;
-- => 621.50 / 369.00 / 621.50 / 621.50
-- Q: No, the outer variable did NOT change. The subblock's fee_total is a
--    separate variable that exists only until the subblock's END; the SELECT
--    INTO inside it assigned the inner one. A declaration is visible only in
--    its own block (and nested ones), and an inner declaration shadows an outer
--    one of the same name, which can still be reached as label.name.

-- Exercise 6.3  (declarations are local)
DO $$
<<outer_blk>>
BEGIN
    DECLARE
        inner_only INT := 42;
    BEGIN
        RAISE NOTICE 'First subblock sees inner_only = %', inner_only;
    END;

    BEGIN
        RAISE NOTICE 'Second subblock sees inner_only = %', inner_only;
    END;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ERROR:  %', SQLERRM;
END outer_blk $$;
-- => First subblock sees inner_only = 42
--    ERROR:  column "inner_only" does not exist
--    (the name is looked up as a variable, not found, then as a column.)

-- Fixed: declaration moved up into the outer block, both subblocks see it
DO $$
<<outer_blk>>
DECLARE
    inner_only INT := 42;
BEGIN
    BEGIN
        RAISE NOTICE 'First subblock sees inner_only = %', inner_only;
    END;
    BEGIN
        RAISE NOTICE 'Second subblock sees inner_only = %', inner_only;
    END;
END outer_blk $$;
-- => both print 42

-- Exercise 6.4
CREATE OR REPLACE FUNCTION fee_split(
    p_from_date DATE,
    OUT before_total NUMERIC,
    OUT after_total NUMERIC)
AS $$
BEGIN
    SELECT COALESCE(SUM(fee) FILTER (WHERE start_date <  p_from_date), 0),
           COALESCE(SUM(fee) FILTER (WHERE start_date >= p_from_date), 0)
    INTO before_total, after_total
    FROM rentals;
END; $$ LANGUAGE plpgsql;

SELECT f.before_total, f.after_total,
       f.before_total + f.after_total AS combined,
       (SELECT SUM(fee) FROM rentals) AS whole_table
FROM fee_split(DATE '2025-01-01') f;
-- => 252.50 | 369.00 | 621.50 | 621.50   (the two parts add up to the total)

-- ###########################################################################
-- Part 7: Practical scenarios
-- ###########################################################################

-- Exercise 7.1
CREATE OR REPLACE FUNCTION station_load(
    p_station_id INT,
    OUT bikes_parked INT,
    OUT capacity_pct NUMERIC)
AS $$
DECLARE
    cap INT;
BEGIN
    SELECT capacity INTO cap FROM stations WHERE station_id = p_station_id;
    SELECT COUNT(*) INTO bikes_parked FROM bikes WHERE station_id = p_station_id;
    -- NULLIF(cap, 0) turns a zero capacity into NULL, so no division by zero
    capacity_pct := ROUND(100.0 * bikes_parked / NULLIF(cap, 0), 1);
END; $$ LANGUAGE plpgsql;

SELECT s.station_id, s.station_name, l.*
FROM stations s, LATERAL station_load(s.station_id) l
ORDER BY s.station_id;
-- => 10 Central Park 3 75.0 | 20 Riverside 2 66.7 | 30 Expo Gate 2 40.0
--    40 Old Town 1 50.0     | 50 Depot 0 NULL
-- Justification: for capacity 0 the percentage is undefined, not 0%. Returning
-- NULL says "not applicable" and cannot be mistaken for a real, empty station
-- (0%). It also stays honest if bikes were ever parked at a zero-capacity
-- station (that would be "infinite", not 0%).

-- Exercise 7.2
CREATE OR REPLACE FUNCTION top_members(p_limit INT DEFAULT 3)
RETURNS TABLE (t_name VARCHAR, t_rentals INT, t_spent NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT m.full_name,
           COUNT(r.rental_id)::INT,
           COALESCE(SUM(r.fee), 0)
    FROM members m
    LEFT JOIN rentals r ON r.member_id = m.member_id
    GROUP BY m.member_id, m.full_name
    ORDER BY COALESCE(SUM(r.fee), 0) DESC, m.full_name
    LIMIT p_limit;
END; $$ LANGUAGE plpgsql;

SELECT * FROM top_members();
-- => Marta Kowalski 5 164.75 | Chen Wei 4 139.25 | Daniyar Serik 4 138.00
SELECT * FROM top_members(6);
-- => the three above, then Aisha Nurlanova 5 98.50 | Omar Haddad 4 81.00 |
--    Elena Petrova 0 0
-- Q: Aisha Nurlanova has 5 rentals, more than Daniyar Serik and Chen Wei above
--    her (4 each), yet ranks lower. Not a bug: the ranking is by amount spent,
--    not by number of rentals, and Aisha's rentals were cheap ones (City
--    Cruiser, 4.50 a day) and one of the five (rental 19) is still open with
--    fee NULL, so it counts as a rental but adds nothing to her total.

-- Exercise 7.3
CREATE OR REPLACE FUNCTION rental_invoice(p_rental_id INT)
RETURNS TABLE (inv_member VARCHAR, inv_model VARCHAR, inv_days INT,
               inv_amount NUMERIC, inv_status VARCHAR) AS $$
BEGIN
    RETURN QUERY
    SELECT m.full_name,
           b.model,
           COALESCE(r.end_date, CURRENT_DATE) - r.start_date,
           ROUND((COALESCE(r.end_date, CURRENT_DATE) - r.start_date) * b.daily_rate, 2),
           (CASE WHEN r.end_date IS NULL THEN 'OPEN' ELSE 'CLOSED' END)::VARCHAR
    FROM rentals r
    JOIN members m ON m.member_id = r.member_id
    JOIN bikes b   ON b.bike_id   = r.bike_id
    WHERE r.rental_id = p_rental_id;
END; $$ LANGUAGE plpgsql STABLE;

SELECT * FROM rental_invoice(11);
-- => Marta Kowalski | Road Sprint | 8 | 74.00 | CLOSED
SELECT * FROM rental_invoice(19);
-- => Aisha Nurlanova | City Cruiser | <days since 2025-10-10> | <days * 4.50> | OPEN
--    (on 21 Nov 2026 that is 407 days and 1831.50)
-- Q: Rental 11: yes, 8 days x 9.25 = 74.00, equal to the stored fee (every
--    stored fee equals days x daily_rate). Rental 19 has no end_date, so it is
--    charged up to CURRENT_DATE and the amount grows by one day's rate every
--    day. Such a function cannot be IMMUTABLE: an immutable function must
--    return the same result for the same arguments forever, and this one's
--    result depends on the current date (and on table data). At best it is
--    STABLE (constant within a single statement), as declared above.

-- Exercise 7.4
CREATE OR REPLACE FUNCTION city_report(p_city VARCHAR)
RETURNS TABLE (c_members INT, c_rentals INT, c_revenue NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT COUNT(DISTINCT m.member_id)::INT,
           COUNT(r.rental_id)::INT,
           COALESCE(SUM(r.fee), 0)
    FROM members m
    LEFT JOIN rentals r ON r.member_id = m.member_id
    WHERE m.city = p_city;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION city_report(p_city VARCHAR, p_from_date DATE)
RETURNS TABLE (c_members INT, c_rentals INT, c_revenue NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT COUNT(DISTINCT m.member_id)::INT,
           COUNT(r.rental_id)::INT,
           COALESCE(SUM(r.fee), 0)
    FROM members m
    LEFT JOIN rentals r ON r.member_id = m.member_id
                       AND r.start_date >= p_from_date     -- condition in ON
    WHERE m.city = p_city;
END; $$ LANGUAGE plpgsql;

SELECT * FROM city_report('Almaty');                       -- => 3 | 9 | 236.50
SELECT * FROM city_report('Almaty', DATE '2025-01-01');    -- => 3 | 5 | 135.50

-- The WRONG variant, date condition in WHERE (kept under another name):
CREATE OR REPLACE FUNCTION city_report_where(p_city VARCHAR, p_from_date DATE)
RETURNS TABLE (c_members INT, c_rentals INT, c_revenue NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT COUNT(DISTINCT m.member_id)::INT,
           COUNT(r.rental_id)::INT,
           COALESCE(SUM(r.fee), 0)
    FROM members m
    LEFT JOIN rentals r ON r.member_id = m.member_id
    WHERE m.city = p_city AND r.start_date >= p_from_date;   -- condition in WHERE
END; $$ LANGUAGE plpgsql;

SELECT * FROM city_report_where('Almaty', DATE '2025-01-01');   -- => 2 | 5 | 135.50
-- Q: The date condition belongs in the ON clause. In ON it only decides which
--    rentals are matched; a member with no matching rental still survives with
--    NULLs, so Almaty keeps all 3 members. In WHERE, the condition runs AFTER
--    the join and r.start_date >= ... is never true for the NULL row, so
--    Elena Petrova (no rentals) is filtered out and the count drops to 2: the
--    LEFT JOIN has silently turned into an inner join.

-- ###########################################################################
-- Lab Questions
-- ###########################################################################
-- 1. The name is just the identifier; the signature is the name PLUS the
--    argument types, e.g. total_fees(integer) vs total_fees(integer, date).
--    PostgreSQL identifies a function by its signature, so overloaded
--    functions are different objects sharing a name. DROP FUNCTION needs the
--    signature to know which one to remove (DROP FUNCTION total_fees(INTEGER)).
--
-- 2. The body is passed to CREATE FUNCTION as a string literal. Dollar quoting
--    ($$ ... $$) delimits it without any escaping, so single quotes inside
--    the body are written normally. Awkward without it:
--      CREATE FUNCTION warn(p_id INT) RETURNS void AS $$
--      BEGIN RAISE NOTICE 'Rental % is still open', p_id; END; $$ LANGUAGE plpgsql;
--    With ordinary quotes every ' in the body would have to be doubled:
--      ... RAISE NOTICE ''Rental % is still open'', p_id; ...
--
-- 3. Use several OUT parameters when the function returns exactly ONE row of a
--    few values (member_stats, station_load); they are simple to fill with
--    SELECT ... INTO. Use RETURNS TABLE when it returns MANY rows (find_bikes,
--    member_history), via RETURN QUERY.
--
-- 4. The caller's trailing arguments are all gathered into the array, so
--    nothing may follow it. Given f(VARIADIC nums INT[], label TEXT), a call
--    f(1, 2, 3) cannot be resolved: are 1, 2, 3 all numbers, or is 3 the label?
--
-- 5. RETURN expr ends the function and returns the value (or, with no
--    expression, just ends a function with OUT parameters). RETURN QUERY
--    appends the rows of a query to the result set of a set-returning function
--    and execution CONTINUES; the function ends at its END or an explicit
--    RETURN.
--
-- 6. A new DEFAULT can make a call match two overloads (total_fees(1) in 4.3),
--    so a call that was fine before the change is now "not unique". In
--    production: do not keep overloads that overlap through defaults; replace
--    the old version (DROP the one-argument function) in the same migration,
--    give functions distinct names, and run the application's test calls after
--    every change.
--
-- 7. The subblock variable ceases to exist at the subblock's END; its value is
--    lost and any outer variable of the same name is visible again, unchanged.
--    A shadowed outer variable is read by qualifying it with the outer block's
--    label: outer_blk.fee_total.
--
-- 8. Advantage: one definition of the rule shared by every application, fewer
--    round trips. Disadvantage: harder to version-control, test and port (code
--    lives in the database, in a DBMS-specific language), and it loads the
--    database server's CPU.
--
-- 9. A trusted language (PL/pgSQL, PL/Perl) cannot reach outside the database:
--    no file system, no OS, no network. So regular users who have been given
--    USAGE on it can create functions in it (plpgsql grants this to everyone by
--    default). An untrusted language (PL/Python = plpython3u, C) can do all of
--    these, so only a superuser may create functions in it.
--
-- 10. CREATE OR REPLACE only replaces a function with the SAME signature. With
--    changed argument types it creates a NEW function and leaves the old one in
--    place. Now two overloads coexist: callers may still hit the stale old
--    version, and calls with literals or implicit casts can become ambiguous
--    or resolve to the wrong one. Drop the old signature explicitly.
