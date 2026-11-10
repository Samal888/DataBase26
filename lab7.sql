-- ===========================================================================
--  Laboratory Work 7: SQL Views and Roles  --  solutions
--  Run as a superuser (e.g. postgres):  psql -d shop -f surname_lab7.sql
--
--  NOTE: the Lab 6 tables were not in the PDF, so Part 1 assumes the usual
--  Lab 6 schema. It is safe to run on top of your own Lab 6 data
--  (IF NOT EXISTS / ON CONFLICT DO NOTHING). Adjust column names if yours differ.
--  Roles are cluster-wide: run this script ONCE (re-running fails on CREATE ROLE).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Part 1: setup (Lab 6 tables)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS departments (
    dept_id    int PRIMARY KEY,
    dept_name  varchar(50) NOT NULL,
    location   varchar(50)
);
CREATE TABLE IF NOT EXISTS employees (
    emp_id     int PRIMARY KEY,
    emp_name   varchar(100) NOT NULL,
    dept_id    int REFERENCES departments,
    salary     int
);
CREATE TABLE IF NOT EXISTS projects (
    project_id   int PRIMARY KEY,
    project_name varchar(100) NOT NULL,
    dept_id      int REFERENCES departments,
    budget       int
);

INSERT INTO departments VALUES
  (101, 'IT', 'Building A'),
  (102, 'HR', 'Building B'),
  (103, 'Operations', 'Building C')
ON CONFLICT DO NOTHING;

INSERT INTO employees VALUES
  (1, 'John Smith',    102, 50000),
  (2, 'Jane Doe',      101, 60000),
  (3, 'Mike Johnson',  101, 55000),
  (4, 'Sarah Williams',102, 65000),
  (5, 'Tom Brown',     NULL, 45000)
ON CONFLICT DO NOTHING;

INSERT INTO projects VALUES
  (201, 'Website Redesign',   101, 100000),
  (202, 'Database Migration', 101, 200000),
  (203, 'HR System Upgrade',  102,  50000)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- Part 2: basic views
-- ---------------------------------------------------------------------------

-- 2.1
CREATE VIEW employee_details AS
SELECT e.emp_name, e.salary, d.dept_name, d.location
FROM employees e
JOIN departments d ON d.dept_id = e.dept_id;

SELECT * FROM employee_details;
-- Q: 4 rows with the sample data. Tom Brown has dept_id = NULL, so the
--    INNER JOIN finds no matching department and drops him.

-- 2.2  (LEFT JOIN keeps departments with no employees)
CREATE VIEW dept_statistics AS
SELECT d.dept_id,
       d.dept_name,
       count(e.emp_id)  AS employee_count,
       avg(e.salary)    AS avg_salary,
       max(e.salary)    AS max_salary,
       min(e.salary)    AS min_salary
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
GROUP BY d.dept_id, d.dept_name;

SELECT * FROM dept_statistics ORDER BY employee_count DESC;

-- 2.3  (team size is aggregated separately, so no fan-out)
CREATE VIEW project_overview AS
SELECT p.project_name,
       p.budget,
       d.dept_name,
       d.location,
       COALESCE(t.team_size, 0) AS team_size
FROM projects p
JOIN departments d ON d.dept_id = p.dept_id
LEFT JOIN (SELECT dept_id, count(*) AS team_size
           FROM employees GROUP BY dept_id) t ON t.dept_id = p.dept_id;

-- 2.4  (LEFT JOIN so high earners without a department still appear)
CREATE VIEW high_earners AS
SELECT e.emp_name, e.salary, d.dept_name
FROM employees e
LEFT JOIN departments d ON d.dept_id = e.dept_id
WHERE e.salary > 55000;

SELECT * FROM high_earners;
-- Q: Yes, every employee earning > 55000 is listed. With an INNER JOIN, a
--    high earner with no department would silently disappear.

-- ---------------------------------------------------------------------------
-- Part 3: modifying and managing views
-- ---------------------------------------------------------------------------

-- 3.1  (OR REPLACE: existing columns keep name/order, new column goes last)
CREATE OR REPLACE VIEW employee_details AS
SELECT e.emp_name, e.salary, d.dept_name, d.location,
       CASE WHEN e.salary > 60000 THEN 'High'
            WHEN e.salary > 50000 THEN 'Medium'
            ELSE 'Standard'
       END AS salary_grade
FROM employees e
JOIN departments d ON d.dept_id = e.dept_id;

-- 3.2
ALTER VIEW high_earners RENAME TO top_performers;
SELECT * FROM top_performers;

-- 3.3
CREATE VIEW temp_view AS
SELECT emp_name, salary FROM employees WHERE salary < 50000;
DROP VIEW temp_view;

-- ---------------------------------------------------------------------------
-- Part 4: updatable views
-- ---------------------------------------------------------------------------

-- 4.1
CREATE VIEW employee_salaries AS
SELECT emp_id, emp_name, dept_id, salary FROM employees;

-- 4.2
UPDATE employee_salaries SET salary = 52000 WHERE emp_name = 'John Smith';
SELECT * FROM employees WHERE emp_name = 'John Smith';
-- Q: Yes. A simple single-table view is automatically updatable and the
--    change is written to the underlying employees table.

-- 4.3
INSERT INTO employee_salaries (emp_id, emp_name, dept_id, salary)
VALUES (6, 'Alice Johnson', 102, 58000);
SELECT * FROM employees WHERE emp_id = 6;
-- Q: Succeeded. Simple views accept INSERT and the row lands in employees.

-- 4.4
CREATE VIEW it_employees AS
SELECT emp_id, emp_name, dept_id, salary
FROM employees
WHERE dept_id = 101
WITH LOCAL CHECK OPTION;

-- This should fail (left commented so the script keeps running):
-- INSERT INTO it_employees (emp_id, emp_name, dept_id, salary)
-- VALUES (7, 'Bob Wilson', 103, 60000);
-- Q: ERROR: new row violates check option for view "it_employees"
--    The new row has dept_id = 103, which does not satisfy the view's
--    WHERE dept_id = 101, and CHECK OPTION rejects rows the view could not show.

-- ---------------------------------------------------------------------------
-- Part 5: materialized views
-- ---------------------------------------------------------------------------

-- 5.1  (employees and projects aggregated separately to avoid fan-out)
CREATE MATERIALIZED VIEW dept_summary_mv AS
SELECT d.dept_id,
       d.dept_name,
       COALESCE(e.total_employees, 0) AS total_employees,
       COALESCE(e.total_salaries, 0)  AS total_salaries,
       COALESCE(p.total_projects, 0)  AS total_projects,
       COALESCE(p.total_budget, 0)    AS total_budget
FROM departments d
LEFT JOIN (SELECT dept_id, count(*) AS total_employees, sum(salary) AS total_salaries
           FROM employees GROUP BY dept_id) e ON e.dept_id = d.dept_id
LEFT JOIN (SELECT dept_id, count(*) AS total_projects, sum(budget) AS total_budget
           FROM projects GROUP BY dept_id) p ON p.dept_id = d.dept_id
WITH DATA;

SELECT * FROM dept_summary_mv ORDER BY total_employees DESC;

-- 5.2
INSERT INTO employees VALUES (8, 'Charlie Brown', 101, 54000);
SELECT * FROM dept_summary_mv WHERE dept_id = 101;   -- BEFORE: old numbers
REFRESH MATERIALIZED VIEW dept_summary_mv;
SELECT * FROM dept_summary_mv WHERE dept_id = 101;   -- AFTER: includes Charlie
-- Q: A materialized view stores a snapshot. Before the refresh it is stale
--    (Charlie is missing); after the refresh employee count and salary total
--    for IT include him.

-- 5.3
CREATE UNIQUE INDEX idx_dept_summary_mv_dept_id ON dept_summary_mv (dept_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY dept_summary_mv;
-- Q: CONCURRENTLY does not lock out readers: SELECTs keep working on the old
--    data during the refresh. It needs a unique index and is slower.

-- 5.4
CREATE MATERIALIZED VIEW project_stats_mv AS
SELECT p.project_name, p.budget, d.dept_name,
       COALESCE(t.emp_count, 0) AS assigned_employees
FROM projects p
JOIN departments d ON d.dept_id = p.dept_id
LEFT JOIN (SELECT dept_id, count(*) AS emp_count
           FROM employees GROUP BY dept_id) t ON t.dept_id = p.dept_id
WITH NO DATA;

-- SELECT * FROM project_stats_mv;
-- Q: ERROR: materialized view "project_stats_mv" has not been populated
--    HINT: Use the REFRESH MATERIALIZED VIEW command.
REFRESH MATERIALIZED VIEW project_stats_mv;
SELECT * FROM project_stats_mv;

-- ---------------------------------------------------------------------------
-- Part 6: roles
-- ---------------------------------------------------------------------------

-- 6.1
CREATE ROLE analyst;                                     -- NOLOGIN by default
CREATE ROLE data_viewer LOGIN PASSWORD 'viewer123';
CREATE USER report_user PASSWORD 'report456';            -- CREATE USER = LOGIN
SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%';

-- 6.2
CREATE ROLE db_creator   LOGIN CREATEDB   PASSWORD 'creator789';
CREATE ROLE user_manager LOGIN CREATEROLE PASSWORD 'manager101';
CREATE ROLE admin_user   LOGIN SUPERUSER  PASSWORD 'admin999';

-- 6.3
GRANT SELECT ON employees, departments, projects TO analyst;
GRANT ALL PRIVILEGES ON employee_details TO data_viewer;
GRANT SELECT, INSERT ON employees TO report_user;

-- 6.4
CREATE ROLE hr_team;
CREATE ROLE finance_team;
CREATE ROLE it_team;

CREATE USER hr_user1      PASSWORD 'hr001';
CREATE USER hr_user2      PASSWORD 'hr002';
CREATE USER finance_user1 PASSWORD 'fin001';

GRANT hr_team      TO hr_user1, hr_user2;
GRANT finance_team TO finance_user1;

GRANT SELECT, UPDATE ON employees TO hr_team;
GRANT SELECT ON dept_statistics TO finance_team;

-- 6.5
REVOKE UPDATE ON employees FROM hr_team;
REVOKE hr_team FROM hr_user2;
REVOKE ALL PRIVILEGES ON employee_details FROM data_viewer;

-- 6.6
ALTER ROLE analyst LOGIN PASSWORD 'analyst123';
ALTER ROLE user_manager SUPERUSER;
ALTER ROLE analyst PASSWORD NULL;
ALTER ROLE data_viewer CONNECTION LIMIT 5;

-- ---------------------------------------------------------------------------
-- Part 7: advanced role management
-- ---------------------------------------------------------------------------

-- 7.1
CREATE ROLE read_only;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_only;   -- includes views

CREATE ROLE junior_analyst LOGIN PASSWORD 'junior123';
CREATE ROLE senior_analyst LOGIN PASSWORD 'senior123';

GRANT read_only TO junior_analyst, senior_analyst;
GRANT INSERT, UPDATE ON employees TO senior_analyst;

-- 7.2
CREATE ROLE project_manager LOGIN PASSWORD 'pm123';
ALTER VIEW  dept_statistics OWNER TO project_manager;
ALTER TABLE projects        OWNER TO project_manager;

-- A view runs with its OWNER's rights on the underlying tables, so the new
-- owner needs SELECT on what dept_statistics reads, or the view breaks:
GRANT SELECT ON employees, departments TO project_manager;

SELECT tablename, tableowner
FROM pg_tables
WHERE schemaname = 'public';

-- 7.3
CREATE ROLE temp_owner LOGIN;
CREATE TABLE temp_table (id int);
ALTER TABLE temp_table OWNER TO temp_owner;

REASSIGN OWNED BY temp_owner TO postgres;
DROP OWNED BY temp_owner;
DROP ROLE temp_owner;

-- 7.4
CREATE VIEW hr_employee_view AS
SELECT * FROM employees WHERE dept_id = 102;
GRANT SELECT ON hr_employee_view TO hr_team;

CREATE VIEW finance_employee_view AS
SELECT emp_id, emp_name, salary FROM employees;
GRANT SELECT ON finance_employee_view TO finance_team;

-- ---------------------------------------------------------------------------
-- Part 8: practical scenarios
-- ---------------------------------------------------------------------------

-- 8.1  (no status column exists, so "active projects" = all projects)
CREATE VIEW dept_dashboard AS
SELECT d.dept_name,
       d.location,
       COALESCE(e.emp_count, 0)                    AS employee_count,
       COALESCE(round(e.avg_salary, 2), 0)         AS avg_salary,
       COALESCE(p.project_count, 0)                AS active_projects,
       COALESCE(p.total_budget, 0)                 AS total_project_budget,
       CASE WHEN COALESCE(e.emp_count, 0) = 0 THEN 0
            ELSE round(COALESCE(p.total_budget, 0)::numeric / e.emp_count, 2)
       END                                         AS budget_per_employee
FROM departments d
LEFT JOIN (SELECT dept_id, count(*) AS emp_count, avg(salary) AS avg_salary
           FROM employees GROUP BY dept_id) e ON e.dept_id = d.dept_id
LEFT JOIN (SELECT dept_id, count(*) AS project_count, sum(budget) AS total_budget
           FROM projects GROUP BY dept_id) p ON p.dept_id = d.dept_id;

-- 8.2
ALTER TABLE projects ADD COLUMN created_date timestamp DEFAULT CURRENT_TIMESTAMP;

CREATE VIEW high_budget_projects AS
SELECT p.project_name,
       p.budget,
       d.dept_name,
       p.created_date,
       CASE WHEN p.budget > 150000 THEN 'Critical Review Required'
            WHEN p.budget > 100000 THEN 'Management Approval Needed'
            ELSE 'Standard Process'
       END AS approval_status
FROM projects p
JOIN departments d ON d.dept_id = p.dept_id
WHERE p.budget > 75000;

-- 8.3
-- Level 1
CREATE ROLE viewer_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO viewer_role;  -- tables and views

-- Level 2
CREATE ROLE entry_role;
GRANT viewer_role TO entry_role;
GRANT INSERT ON employees, projects TO entry_role;

-- Level 3
CREATE ROLE analyst_role;
GRANT entry_role TO analyst_role;
GRANT UPDATE ON employees, projects TO analyst_role;

-- Level 4
CREATE ROLE manager_role;
GRANT analyst_role TO manager_role;
GRANT DELETE ON employees, projects TO manager_role;

-- Users
CREATE USER alice   PASSWORD 'alice123';
CREATE USER bob     PASSWORD 'bob123';
CREATE USER charlie PASSWORD 'charlie123';

GRANT viewer_role  TO alice;
GRANT analyst_role TO bob;
GRANT manager_role TO charlie;
