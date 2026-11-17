-- ===========================================================================
--  Laboratory Work 8: SQL Indexes  --  solutions
--  Usage:  createdb lab8
--          psql -d lab8 -f surname_lab8.sql
--
--  Use a FRESH database: Part 1 uses the Lab 8 table definitions, which differ
--  from the Lab 7 ones (projects has proj_id / proj_name here).
--  Answers to the questions are in the comments.
--  Index names in this file are pinned, so run it once on an empty database.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Part 1: setup (as given in the lab)
-- ---------------------------------------------------------------------------
CREATE TABLE departments (
    dept_id   INT PRIMARY KEY,
    dept_name VARCHAR(50),
    location  VARCHAR(50)
);
CREATE TABLE employees (
    emp_id   INT PRIMARY KEY,
    emp_name VARCHAR(100),
    dept_id  INT,
    salary   DECIMAL(10,2),
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);
CREATE TABLE projects (
    proj_id   INT PRIMARY KEY,
    proj_name VARCHAR(100),
    budget    DECIMAL(12,2),
    dept_id   INT,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

INSERT INTO departments VALUES
(101, 'IT', 'Building A'),
(102, 'HR', 'Building B'),
(103, 'Operations', 'Building C');

INSERT INTO employees VALUES
(1, 'John Smith', 101, 50000),
(2, 'Jane Doe', 101, 55000),
(3, 'Mike Johnson', 102, 48000),
(4, 'Sarah Williams', 102, 52000),
(5, 'Tom Brown', 103, 60000);

INSERT INTO projects VALUES
(201, 'Website Redesign', 75000, 101),
(202, 'Database Migration', 120000, 101),
(203, 'HR System Upgrade', 50000, 102);

-- NOTE on tiny tables: with 5 rows the planner nearly always picks a
-- sequential scan, because reading one page is cheaper than going through
-- an index. To SEE an index being used in the EXPLAIN exercises, run
--     SET enable_seqscan = off;
-- in your session first (or test on a bigger table, see the challenges).

-- ---------------------------------------------------------------------------
-- Part 2: basic indexes
-- ---------------------------------------------------------------------------

-- 2.1
CREATE INDEX emp_salary_idx ON employees(salary);

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'employees';
-- Q: 2 indexes: employees_pkey (automatic, from PRIMARY KEY) and emp_salary_idx.

-- 2.2
CREATE INDEX emp_dept_idx ON employees(dept_id);

SELECT * FROM employees WHERE dept_id = 101;
-- Q: PostgreSQL does NOT index foreign key columns automatically. An index on
--    the FK column (a) speeds up JOINs and lookups by that column, and
--    (b) makes checks on the parent table fast: deleting or updating a
--    departments row forces PostgreSQL to look for child rows in employees,
--    which would otherwise be a full scan every time.

-- 2.3
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
-- Q: departments_pkey, emp_dept_idx, emp_salary_idx, employees_pkey,
--    projects_pkey.
--    Created automatically: the three *_pkey indexes (PRIMARY KEY constraints).

-- ---------------------------------------------------------------------------
-- Part 3: multicolumn indexes
-- ---------------------------------------------------------------------------

-- 3.1
CREATE INDEX emp_dept_salary_idx ON employees(dept_id, salary);

SELECT emp_name, salary
FROM employees
WHERE dept_id = 101 AND salary > 52000;
-- Q: A query filtering only by salary gets little benefit. A B-tree
--    multicolumn index is sorted by dept_id first, then salary inside each
--    dept_id, so salaries are not in one continuous order. The index works
--    best when the leading column(s) are constrained. (The planner could
--    still scan the whole index, but that is rarely better than a table scan.)

-- 3.2
CREATE INDEX emp_salary_dept_idx ON employees(salary, dept_id);

SELECT * FROM employees WHERE dept_id = 102 AND salary > 50000;   -- Query 1
SELECT * FROM employees WHERE salary > 50000 AND dept_id = 102;   -- Query 2
-- Q: The order of conditions in WHERE does not matter: Query 1 and Query 2
--    are the same query to the planner. The order of columns IN THE INDEX
--    does matter. (dept_id, salary) is ideal here: equality on the leading
--    column narrows to one dept_id block, then the salary range is read
--    contiguously. (salary, dept_id) has a range on the leading column, so
--    the index scans every entry with salary > 50000 and checks dept_id
--    against each of them. Rule of thumb: equality columns first, range last.

-- ---------------------------------------------------------------------------
-- Part 4: unique indexes
-- ---------------------------------------------------------------------------

-- 4.1
ALTER TABLE employees ADD COLUMN email VARCHAR(100);
UPDATE employees SET email = 'john.smith@company.com'      WHERE emp_id = 1;
UPDATE employees SET email = 'jane.doe@company.com'        WHERE emp_id = 2;
UPDATE employees SET email = 'mike.johnson@company.com'    WHERE emp_id = 3;
UPDATE employees SET email = 'sarah.williams@company.com'  WHERE emp_id = 4;
UPDATE employees SET email = 'tom.brown@company.com'       WHERE emp_id = 5;

CREATE UNIQUE INDEX emp_email_unique_idx ON employees(email);

-- Should fail (commented so the script keeps running):
-- INSERT INTO employees (emp_id, emp_name, dept_id, salary, email)
-- VALUES (6, 'New Employee', 101, 55000, 'john.smith@company.com');
-- Q: ERROR:  duplicate key value violates unique constraint "emp_email_unique_idx"
--    DETAIL: Key (email)=(john.smith@company.com) already exists.

-- 4.2
ALTER TABLE employees ADD COLUMN phone VARCHAR(20) UNIQUE;

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'employees' AND indexname LIKE '%phone%';
-- Q: Yes. PostgreSQL automatically created the unique B-tree index
--    employees_phone_key: CREATE UNIQUE INDEX employees_phone_key
--    ON public.employees USING btree (phone). A UNIQUE constraint is
--    implemented by a unique index; the constraint is the declaration,
--    the index is the mechanism.

-- ---------------------------------------------------------------------------
-- Part 5: indexes and sorting
-- ---------------------------------------------------------------------------

-- 5.1
CREATE INDEX emp_salary_desc_idx ON employees(salary DESC);

SELECT emp_name, salary
FROM employees
ORDER BY salary DESC;
-- Q: The index is already stored in sorted order, so PostgreSQL can read
--    rows in that order and skip the separate sort step. (For a single column,
--    a plain B-tree can be scanned backwards too; an explicit DESC matters
--    mostly in multicolumn indexes with mixed ASC/DESC ordering.)

-- 5.2
CREATE INDEX proj_budget_nulls_first_idx ON projects(budget NULLS FIRST);

SELECT proj_name, budget
FROM projects
ORDER BY budget NULLS FIRST;
-- By default ASC puts NULLs last. This index stores NULLs first, so an
-- ORDER BY ... NULLS FIRST can be served directly from it without sorting.

-- ---------------------------------------------------------------------------
-- Part 6: indexes on expressions
-- ---------------------------------------------------------------------------

-- 6.1
CREATE INDEX emp_name_lower_idx ON employees(LOWER(emp_name));

SELECT * FROM employees WHERE LOWER(emp_name) = 'john smith';
-- Q: Without the index PostgreSQL does a sequential scan, calling LOWER() on
--    emp_name of every row and comparing the result. A plain index on
--    emp_name cannot be used because the query compares LOWER(emp_name), not
--    emp_name. The query expression must match the indexed expression.

-- 6.2
ALTER TABLE employees ADD COLUMN hire_date DATE;
UPDATE employees SET hire_date = '2020-01-15' WHERE emp_id = 1;
UPDATE employees SET hire_date = '2019-06-20' WHERE emp_id = 2;
UPDATE employees SET hire_date = '2021-03-10' WHERE emp_id = 3;
UPDATE employees SET hire_date = '2020-11-05' WHERE emp_id = 4;
UPDATE employees SET hire_date = '2018-08-25' WHERE emp_id = 5;

CREATE INDEX emp_hire_year_idx ON employees(EXTRACT(YEAR FROM hire_date));

SELECT emp_name, hire_date
FROM employees
WHERE EXTRACT(YEAR FROM hire_date) = 2020;      -- John Smith, Sarah Williams

-- ---------------------------------------------------------------------------
-- Part 7: managing indexes
-- ---------------------------------------------------------------------------

-- 7.1
ALTER INDEX emp_salary_idx RENAME TO employees_salary_index;
SELECT indexname FROM pg_indexes WHERE tablename = 'employees';

-- 7.2
DROP INDEX emp_salary_dept_idx;
-- Q: Reasons to drop an index: it is never used; it is redundant (another
--    index covers the same queries, e.g. (salary, dept_id) next to
--    (salary)); it slows INSERT/UPDATE/DELETE because every index must be
--    maintained; it wastes disk space and cache.

-- 7.3
REINDEX INDEX employees_salary_index;
-- Rebuilds the index from scratch: useful after bulk loads, when an index
-- is bloated from many updates/deletes, or when an index is corrupted.

-- ---------------------------------------------------------------------------
-- Part 8: practical scenarios
-- ---------------------------------------------------------------------------

-- 8.1
SELECT e.emp_name, e.salary, d.dept_name
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
WHERE e.salary > 50000
ORDER BY e.salary DESC;

-- Index for the WHERE clause
CREATE INDEX emp_salary_filter_idx ON employees(salary) WHERE salary > 50000;
-- Index for the JOIN: emp_dept_idx (already created)
-- Index for ORDER BY: emp_salary_desc_idx (already created)

-- 8.2
CREATE INDEX proj_high_budget_idx ON projects(budget)
WHERE budget > 80000;

SELECT proj_name, budget FROM projects WHERE budget > 80000;
-- Q: A partial index covers only the rows matching its WHERE condition, so
--    it is smaller, faster to scan, and cheaper to maintain (only matching
--    rows trigger index updates). It helps when queries repeatedly target a
--    small subset. A query can use it only if its condition implies the
--    index condition (budget > 80000 does; budget > 50000 does not).

-- 8.3
EXPLAIN SELECT * FROM employees WHERE salary > 52000;
-- Q: On this 5-row table expect "Seq Scan on employees" with
--    "Filter: (salary > '52000'::numeric)". It tells you the planner decided
--    a full scan is cheaper: for tiny tables (or queries returning a large
--    share of rows) reading the whole table beats going through an index.
--    An index existing does not guarantee it is used. To see an Index Scan,
--    SET enable_seqscan = off; or test on a large table (see Challenge 3).
--    Take your screenshot of this EXPLAIN output for the submission.

-- ---------------------------------------------------------------------------
-- Part 9: index types comparison
-- ---------------------------------------------------------------------------

-- 9.1
CREATE INDEX dept_name_hash_idx ON departments USING HASH (dept_name);
SELECT * FROM departments WHERE dept_name = 'IT';
-- Q: Use HASH only for pure equality lookups (=), where it can be slightly
--    faster/smaller for long keys. It cannot do ranges, ORDER BY, unique
--    constraints or multicolumn indexes. B-tree handles all of those and
--    equality too, so it is the default choice.

-- 9.2
CREATE INDEX proj_name_btree_idx ON projects(proj_name);
CREATE INDEX proj_name_hash_idx  ON projects USING HASH (proj_name);

SELECT * FROM projects WHERE proj_name = 'Website Redesign';  -- either index
SELECT * FROM projects WHERE proj_name > 'Database';          -- B-tree only
-- A hash index stores hashes, which have no order, so it cannot answer
-- range comparisons or sorting.

-- ---------------------------------------------------------------------------
-- Part 10: cleanup and best practices
-- ---------------------------------------------------------------------------

-- 10.1
SELECT schemaname, tablename, indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
-- Q: With so few rows, size reflects structure overhead, not data. The HASH
--    indexes (dept_name_hash_idx, proj_name_hash_idx) are typically the
--    largest (about 32 kB) because a hash index pre-allocates bucket pages,
--    while a tiny B-tree is only a meta page plus one leaf page (16 kB).
--    Check your own output: on real data the biggest indexes are on wide
--    columns (e.g. emp_name / email / expression indexes) or multicolumn ones.

-- 10.2
DROP INDEX IF EXISTS proj_name_hash_idx;
-- (Hash index duplicates the B-tree on the same column and gives nothing
--  extra, so we keep only proj_name_btree_idx.)

-- 10.3
CREATE VIEW index_documentation AS
SELECT tablename,
       indexname,
       indexdef,
       'Improves salary-based queries' AS purpose
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE '%salary%';

SELECT * FROM index_documentation;
-- Lists employees_salary_index, emp_salary_desc_idx, emp_salary_filter_idx.

-- ---------------------------------------------------------------------------
-- Summary questions
-- ---------------------------------------------------------------------------
-- 1. B-tree.
-- 2. Create an index on: columns frequently used in WHERE filters; foreign
--    key / JOIN columns; columns used in ORDER BY (and unique columns).
-- 3. Do NOT index: very small tables; columns with very low selectivity
--    (e.g. a boolean or a status with 2 values); tables with heavy writes
--    and few reads; columns that are never queried.
-- 4. Every INSERT adds entries to each index, every DELETE removes them,
--    and an UPDATE of an indexed column changes the index entries. So
--    more indexes = slower writes, plus extra disk space.
-- 5. Run EXPLAIN (or EXPLAIN ANALYZE) and look for Index Scan / Index Only
--    Scan / Bitmap Index Scan rather than Seq Scan.
--
-- Reflection: indexes pay off when reads dominate and queries select a small
-- fraction of a large table. Index what you filter, join and sort on, verify
-- with EXPLAIN, and drop what is unused, because every index taxes writes.

-- ---------------------------------------------------------------------------
-- Additional challenges
-- ---------------------------------------------------------------------------

-- 1. Employees hired in a given month
CREATE INDEX emp_hire_month_idx ON employees(EXTRACT(MONTH FROM hire_date));
SELECT emp_name FROM employees WHERE EXTRACT(MONTH FROM hire_date) = 6;

-- 2. Composite unique index on dept_id and email
CREATE UNIQUE INDEX emp_dept_email_unique_idx ON employees(dept_id, email);

-- 3. EXPLAIN ANALYZE with and without an index, on a large test table
CREATE TABLE perf_test AS
SELECT g AS id,
       (random() * 100000)::int AS val
FROM generate_series(1, 200000) AS g;
ANALYZE perf_test;

EXPLAIN ANALYZE SELECT * FROM perf_test WHERE val = 500;   -- Seq Scan (slow)
CREATE INDEX perf_test_val_idx ON perf_test(val);
ANALYZE perf_test;
EXPLAIN ANALYZE SELECT * FROM perf_test WHERE val = 500;   -- Index/Bitmap scan (fast)
-- Compare "Execution Time": the indexed run is typically orders of
-- magnitude faster on 200,000 rows.
DROP TABLE perf_test;

-- 4. Covering index: all columns of the query live in the index, so
--    PostgreSQL can answer with an Index Only Scan (no table access).
CREATE INDEX emp_dept_covering_idx ON employees(dept_id) INCLUDE (emp_name, salary);
EXPLAIN SELECT emp_name, salary FROM employees WHERE dept_id = 101;
