-- PART 1: DATABASE SETUP
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS departments;

CREATE TABLE employees (
    emp_id INT PRIMARY KEY,
    emp_name VARCHAR(50),
    dept_id INT,
    salary DECIMAL(10, 2)
);

CREATE TABLE departments (
    dept_id INT PRIMARY KEY,
    dept_name VARCHAR(50),
    location VARCHAR(50)
);

CREATE TABLE projects (
    project_id INT PRIMARY KEY,
    project_name VARCHAR(50),
    dept_id INT,
    budget DECIMAL(10, 2)
);

INSERT INTO employees (emp_id, emp_name, dept_id, salary) VALUES
(1, 'John Smith', 101, 50000),
(2, 'Jane Doe', 102, 60000),
(3, 'Mike Johnson', 101, 55000),
(4, 'Sarah Williams', 103, 65000),
(5, 'Tom Brown', NULL, 45000);

INSERT INTO departments (dept_id, dept_name, location) VALUES
(101, 'IT', 'Building A'),
(102, 'HR', 'Building B'),
(103, 'Finance', 'Building C'),
(104, 'Marketing', 'Building D');

INSERT INTO projects (project_id, project_name, dept_id, budget) VALUES
(1, 'Website Redesign', 101, 100000),
(2, 'Employee Training', 102, 50000),
(3, 'Budget Analysis', 103, 75000),
(4, 'Cloud Migration', 101, 150000),
(5, 'AI Research', NULL, 200000);

-- PART 2: CROSS JOIN

-- Exercise 2.1
SELECT e.emp_name, d.dept_name
FROM employees e CROSS JOIN departments d;
-- Answer: 5 employees x 4 departments = 20 rows.

-- Exercise 2.2 a) comma notation
SELECT e.emp_name, d.dept_name
FROM employees e, departments d;

-- Exercise 2.2 b) INNER JOIN ... ON TRUE
SELECT e.emp_name, d.dept_name
FROM employees e
INNER JOIN departments d ON TRUE;

-- Exercise 2.3: all employees x all projects (availability matrix)
SELECT e.emp_name, p.project_name
FROM employees e
CROSS JOIN projects p
ORDER BY e.emp_name, p.project_name;
-- 5 x 5 = 25 rows.


-- PART 3: INNER JOIN

-- Exercise 3.1
SELECT e.emp_name, d.dept_name, d.location
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id;
-- Answer: 4 rows. Tom Brown has dept_id = NULL, and NULL = anything
-- is not TRUE, so he has no match and INNER JOIN drops him.

-- Exercise 3.2
SELECT emp_name, dept_name, location
FROM employees
INNER JOIN departments USING (dept_id);
-- Answer: with USING the join column dept_id appears only ONCE in
-- SELECT * (with ON, both e.dept_id and d.dept_id appear). Also, the
-- column can no longer be qualified with a table alias.
-- With the explicit column list above, the output is identical.

-- Exercise 3.3
SELECT emp_name, dept_name, location
FROM employees
NATURAL INNER JOIN departments;
-- Joins automatically on dept_id (the only common column name).

-- Exercise 3.4
SELECT e.emp_name, d.dept_name, p.project_name
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id
INNER JOIN projects p ON d.dept_id = p.dept_id;
-- 6 rows: John and Mike (IT) x 2 projects each, Jane (HR) x 1, Sarah (Finance) x 1.

-- PART 4: LEFT JOIN

-- Exercise 4.1
SELECT e.emp_name, e.dept_id AS emp_dept, d.dept_id AS dept_dept, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id;
-- Answer: Tom Brown is present; emp_dept, dept_dept and dept_name are NULL.

-- Exercise 4.2
SELECT emp_name, dept_id, dept_name
FROM employees
LEFT JOIN departments USING (dept_id);

-- Exercise 4.3
SELECT e.emp_name, e.dept_id
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_id IS NULL;
-- Result: Tom Brown.

-- Exercise 4.4
SELECT d.dept_name, COUNT(e.emp_id) AS employee_count
FROM departments d
LEFT JOIN employees e ON d.dept_id = e.dept_id
GROUP BY d.dept_id, d.dept_name
ORDER BY employee_count DESC;
-- IT = 2, HR = 1, Finance = 1, Marketing = 0.
-- COUNT(e.emp_id) (not COUNT(*)) so that Marketing gives 0, not 1.


-- PART 5: RIGHT JOIN

-- Exercise 5.1
SELECT e.emp_name, d.dept_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id;
-- 5 rows: 4 employees with departments + Marketing with NULL employee.
-- Tom Brown is not shown (he has no department).

-- Exercise 5.2: same result with LEFT JOIN (tables swapped)
SELECT e.emp_name, d.dept_name
FROM departments d
LEFT JOIN employees e ON d.dept_id = e.dept_id;

-- Exercise 5.3
SELECT d.dept_name, d.location
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id
WHERE e.emp_id IS NULL;
-- Result: Marketing, Building D.


-- PART 6: FULL JOIN

-- Exercise 6.1
SELECT e.emp_name, e.dept_id AS emp_dept, d.dept_id AS dept_dept, d.dept_name
FROM employees e
FULL JOIN departments d ON e.dept_id = d.dept_id;
-- 6 rows.
-- NULL on the LEFT (employee) side: Marketing (department without employees).
-- NULL on the RIGHT (department) side: Tom Brown (employee without department).

-- Exercise 6.2
SELECT d.dept_name, p.project_name, p.budget
FROM departments d
FULL JOIN projects p ON d.dept_id = p.dept_id;
-- 6 rows: Marketing has no project (NULL), 'AI Research' has no department (NULL).

-- Exercise 6.3
SELECT
    CASE
        WHEN e.emp_id IS NULL THEN 'Department without employees'
        WHEN d.dept_id IS NULL THEN 'Employee without department'
        ELSE 'Matched'
    END AS record_status,
    e.emp_name,
    d.dept_name
FROM employees e
FULL JOIN departments d ON e.dept_id = d.dept_id
WHERE e.emp_id IS NULL OR d.dept_id IS NULL;
-- Result: Tom Brown (no department), Marketing (no employees).


-- PART 7: ON vs WHERE
-- Exercise 7.1: filter in ON (LEFT JOIN)
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id AND d.location = 'Building A';
-- 5 rows: all employees. dept_name = 'IT' only for John and Mike,
-- NULL for Jane, Sarah, Tom.

-- Exercise 7.2: filter in WHERE (LEFT JOIN)
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.location = 'Building A';
-- 2 rows: John and Mike only.
-- Explanation: ON decides which rows MATCH; the outer join still keeps
-- unmatched left rows (with NULLs). WHERE runs AFTER the join and removes
-- rows where d.location is NULL or not 'Building A', which cancels the
-- effect of LEFT JOIN (it behaves like an INNER JOIN).

-- Exercise 7.3: INNER JOIN versions
-- ON version
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id AND d.location = 'Building A';

-- WHERE version
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id
WHERE d.location = 'Building A';
-- Answer: no difference (both return John and Mike). INNER JOIN only keeps
-- rows satisfying all conditions, so it does not matter whether the filter
-- is applied during or after the join.



-- PART 8: COMPLEX JOINS

-- Exercise 8.1
SELECT
    d.dept_name,
    e.emp_name,
    e.salary,
    p.project_name,
    p.budget
FROM departments d
LEFT JOIN employees e ON d.dept_id = e.dept_id
LEFT JOIN projects p ON d.dept_id = p.dept_id
ORDER BY d.dept_name, e.emp_name;
-- Note: IT employees are repeated once per IT project (2 x 2 = 4 rows).

-- Exercise 8.2: self join
ALTER TABLE employees ADD COLUMN manager_id INT;

UPDATE employees SET manager_id = 3 WHERE emp_id = 1;
UPDATE employees SET manager_id = 3 WHERE emp_id = 2;
UPDATE employees SET manager_id = NULL WHERE emp_id = 3;
UPDATE employees SET manager_id = 3 WHERE emp_id = 4;
UPDATE employees SET manager_id = 3 WHERE emp_id = 5;

SELECT
    e.emp_name AS employee,
    m.emp_name AS manager
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.emp_id;
-- Mike Johnson has no manager (NULL); everyone else reports to Mike.

-- Exercise 8.3
SELECT d.dept_name, AVG(e.salary) AS avg_salary
FROM departments d
INNER JOIN employees e ON d.dept_id = e.dept_id
GROUP BY d.dept_id, d.dept_name
HAVING AVG(e.salary) > 50000;
-- IT (52500), HR (60000), Finance (65000).


-- ------------------------------------------------------------
-- LAB QUESTIONS (answers)
-- ------------------------------------------------------------
-- 1. INNER JOIN returns only rows that have a match in both tables.
--    LEFT JOIN returns all rows of the left table; where there is no
--    match in the right table, right-side columns are NULL.
--
-- 2. CROSS JOIN is useful when all combinations are needed: availability
--    or schedule matrices (employees x projects), generating test data,
--    size x color product variants, calendar grids (dates x slots).
--
-- 3. In an outer join, ON defines which rows match, while unmatched rows
--    of the preserved table are still returned with NULLs. WHERE filters
--    the final result, so it can remove those NULL-extended rows. In an
--    inner join there are no NULL-extended rows, so filtering during or
--    after the join gives the same result.
--
-- 4. 5 x 10 = 50.
--
-- 5. NATURAL JOIN joins on ALL columns that have the same name in both
--    tables (and keeps one copy of each such column).
--
-- 6. Risks: it silently depends on column names. Adding or renaming a
--    column can change the join condition and break queries without any
--    error; unrelated columns with equal names (e.g. 'name', 'id') get
--    joined by mistake; if there are no common columns it turns into a
--    CROSS JOIN. The join condition is not visible in the code.
--
-- 7. SELECT * FROM B RIGHT JOIN A ON A.id = B.id
--    (the result is the same set of rows; column order is B's then A's.)
--
-- 8. Use FULL OUTER JOIN when you need all rows from both tables whether
--    or not they match: data reconciliation/comparison of two sources,
--    finding orphaned records on both sides at once.


-- ------------------------------------------------------------
-- ADDITIONAL CHALLENGES (optional)
-- ------------------------------------------------------------

-- Challenge 1: FULL OUTER JOIN via UNION of LEFT and RIGHT joins
SELECT e.emp_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
UNION
SELECT e.emp_name, d.dept_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id;

-- Challenge 2: employees in departments with more than one project
SELECT e.emp_name, d.dept_name
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_id IN (
    SELECT dept_id
    FROM projects
    WHERE dept_id IS NOT NULL
    GROUP BY dept_id
    HAVING COUNT(*) > 1
);
-- Result: John Smith and Mike Johnson (IT has 2 projects).

-- Challenge 3: organizational hierarchy via self-joins
SELECT
    e.emp_name  AS employee,
    m.emp_name  AS manager,
    mm.emp_name AS managers_manager
FROM employees e
LEFT JOIN employees m  ON e.manager_id = m.emp_id
LEFT JOIN employees mm ON m.manager_id = mm.emp_id;

-- Challenge 4: all pairs of employees in the same department
SELECT
    e1.emp_name AS employee_1,
    e2.emp_name AS employee_2,
    d.dept_name
FROM employees e1
JOIN employees e2 ON e1.dept_id = e2.dept_id AND e1.emp_id < e2.emp_id
JOIN departments d ON e1.dept_id = d.dept_id;
-- Result: John Smith + Mike Johnson (IT).