-- ============================================================
-- CustomerDB - Customer Database Management and Error Detection
-- Run in ONE session (the @variables are used in Step 10).
-- Run Step 11 statements one at a time (each must fail).
-- ============================================================
SET SQL_SAFE_UPDATES = 0;   -- avoids Workbench error 1175 on non-key UPDATE/DELETE

-- STEP 1: Create database
DROP DATABASE IF EXISTS CustomerDB;
CREATE DATABASE CustomerDB;
USE CustomerDB;

-- STEP 2: Raw-load table (no constraints on purpose)
CREATE TABLE Customers (
 Row_No INT AUTO_INCREMENT PRIMARY KEY,
 Customer_ID INT,
 Customer_Name VARCHAR(100),
 Email VARCHAR(150),
 Phone_Number VARCHAR(20),
 Age INT,
 City VARCHAR(50),
 Registration_Date DATE
);

-- STEP 3: Insert 500 synthetic records
SET SESSION cte_max_recursion_depth = 1000;
INSERT INTO Customers
 (Row_No, Customer_ID, Customer_Name, Email, Phone_Number, Age, City, Registration_Date)
WITH RECURSIVE n AS (
 SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 500
)
SELECT i, i,
 CONCAT('Customer ', LPAD(i, 3, '0')),
 CONCAT('customer', i, '@example.com'),
 CONCAT(ELT(1 + MOD(i, 4), '6', '7', '8', '9'),
 LPAD(MOD(i * 7919123, 1000000000), 9, '0')),
 18 + MOD(i * 7, 50),
 ELT(1 + MOD(i, 6), 'Nellore','Hyderabad','Chennai','Bengaluru','Vijayawada','Tirupati'),
 DATE_ADD('2023-01-01', INTERVAL MOD(i * 13, 1000) DAY)
FROM n;

SELECT COUNT(*) AS Total_Records FROM Customers;   -- must be 500

-- STEP 4: Inject 50 errors (run in this order)
-- 10 duplicate customer records
UPDATE Customers c JOIN Customers s ON s.Row_No = c.Row_No - 450
SET c.Customer_Name = s.Customer_Name, c.Email = s.Email,
 c.Phone_Number = s.Phone_Number, c.Age = s.Age, c.City = s.City
WHERE c.Row_No BETWEEN 451 AND 460;
-- 7 missing names
UPDATE Customers SET Customer_Name = NULL WHERE Row_No BETWEEN 461 AND 465;
UPDATE Customers SET Customer_Name = '' WHERE Row_No IN (466, 467);
-- 6 missing emails
UPDATE Customers SET Email = NULL WHERE Row_No BETWEEN 468 AND 472;
UPDATE Customers SET Email = '' WHERE Row_No = 473;
-- 7 invalid emails
UPDATE Customers SET Email = CONCAT(Email, ' ') WHERE Row_No = 474;
UPDATE Customers SET Email = CONCAT(' ', Email) WHERE Row_No = 475;
UPDATE Customers SET Email = REPLACE(Email, '@', '@@') WHERE Row_No = 476;
UPDATE Customers SET Email = REPLACE(Email, '@', '') WHERE Row_No = 477;
UPDATE Customers SET Email = REPLACE(Email, '.com', '') WHERE Row_No = 478;
UPDATE Customers SET Email = 'customer479@.com' WHERE Row_No = 479;
UPDATE Customers SET Email = 'customer 480@example.com' WHERE Row_No = 480;
-- 10 incorrect phone numbers
UPDATE Customers SET Phone_Number = CONCAT('+91', Phone_Number) WHERE Row_No = 481;
UPDATE Customers SET Phone_Number = CONCAT(LEFT(Phone_Number,5),'-',RIGHT(Phone_Number,5)) WHERE Row_No = 482;
UPDATE Customers SET Phone_Number = CONCAT(LEFT(Phone_Number,2),' ',SUBSTRING(Phone_Number,3)) WHERE Row_No = 483;
UPDATE Customers SET Phone_Number = '98765' WHERE Row_No = 484;
UPDATE Customers SET Phone_Number = '12345' WHERE Row_No = 485;
UPDATE Customers SET Phone_Number = 'ABCDE12345' WHERE Row_No = 486;
UPDATE Customers SET Phone_Number = CONCAT(Phone_Number, '1') WHERE Row_No = 487;
UPDATE Customers SET Phone_Number = '1234567890' WHERE Row_No = 488;
UPDATE Customers SET Phone_Number = '0000000000' WHERE Row_No = 489;
UPDATE Customers SET Phone_Number = '5123456789' WHERE Row_No = 490;
-- 5 invalid ages
UPDATE Customers SET Age = -5 WHERE Row_No = 496;
UPDATE Customers SET Age = 0 WHERE Row_No = 497;
UPDATE Customers SET Age = 150 WHERE Row_No = 498;
UPDATE Customers SET Age = 200 WHERE Row_No = 499;
UPDATE Customers SET Age = NULL WHERE Row_No = 500;
-- 5 duplicate customer IDs (LAST)
UPDATE Customers SET Customer_ID = Customer_ID - 390 WHERE Row_No BETWEEN 491 AND 495;

-- STEP 5: Total record count
SELECT COUNT(*) AS Total_Records FROM Customers;

-- STEP 5A: Search / filter / retrieve queries
SELECT * FROM Customers LIMIT 10;
SELECT * FROM Customers WHERE Customer_ID = 25;
SELECT * FROM Customers WHERE City = 'Nellore';
SELECT * FROM Customers WHERE Customer_Name LIKE 'Customer 01%';
SELECT * FROM Customers WHERE Email LIKE '%@example.com' AND Age BETWEEN 25 AND 35;
SELECT * FROM Customers WHERE Registration_Date >= '2024-01-01' ORDER BY Registration_Date DESC LIMIT 20;
SELECT City, COUNT(*) AS Total_Customers, ROUND(AVG(Age),1) AS Avg_Age
FROM Customers GROUP BY City ORDER BY Total_Customers DESC;

-- STEP 6: Detect errors
-- 6.1 Duplicate customer IDs (expect 5)
SELECT Customer_ID, COUNT(*) AS Times_Used FROM Customers
GROUP BY Customer_ID HAVING COUNT(*) > 1;
-- 6.2 Duplicate records, same email (expect 10)
-- (needed on MySQL 8 default mode, else error 1055)
SET SESSION sql_mode = (SELECT REPLACE(@@sql_mode, 'ONLY_FULL_GROUP_BY', ''));
SELECT Email, COUNT(*) AS Copies, GROUP_CONCAT(Customer_ID) AS IDs FROM Customers
WHERE Email IS NOT NULL AND TRIM(Email) <> ''
GROUP BY LOWER(TRIM(Email)) HAVING COUNT(*) > 1;
-- 6.3 Missing names (expect 7)
SELECT * FROM Customers WHERE Customer_Name IS NULL OR TRIM(Customer_Name) = '';
-- 6.4 Missing emails (expect 6)
SELECT * FROM Customers WHERE Email IS NULL OR TRIM(Email) = '';
-- 6.5 Invalid email formats (expect 7)
SELECT * FROM Customers
WHERE Email IS NOT NULL AND TRIM(Email) <> ''
 AND Email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)*[.][A-Za-z]{2,}$';
-- 6.6 Incorrect phones (expect 10)
SELECT * FROM Customers
WHERE Phone_Number IS NULL OR Phone_Number NOT REGEXP '^[6-9][0-9]{9}$';
-- 6.7 Invalid ages (expect 5)
SELECT * FROM Customers WHERE Age IS NULL OR Age NOT BETWEEN 18 AND 100;

-- STEP 7: Backup + rejected table
CREATE TABLE Customers_Before AS SELECT * FROM Customers;
CREATE TABLE Customers_Rejected LIKE Customers;
ALTER TABLE Customers_Rejected ADD COLUMN Reject_Reason VARCHAR(60);

-- STEP 8: Fix errors
-- FIX 1: duplicate IDs
UPDATE Customers c
JOIN (SELECT Row_No, ROW_NUMBER() OVER (PARTITION BY Customer_ID ORDER BY Row_No) AS rn
 FROM Customers) d ON d.Row_No = c.Row_No
SET c.Customer_ID = 1000 + c.Row_No
WHERE d.rn > 1;
SET @fix_dup_id = ROW_COUNT();
-- FIX 2: repairable emails
UPDATE Customers SET Email = REPLACE(Email, ' ', '') WHERE Email LIKE '% %';
SET @fix_email = ROW_COUNT();
UPDATE Customers SET Email = REPLACE(Email, '@@', '@') WHERE Email LIKE '%@@%';
SET @fix_email = @fix_email + ROW_COUNT();
-- FIX 3: repairable phones
UPDATE Customers
SET Phone_Number = REPLACE(REPLACE(REPLACE(Phone_Number,'+91',''),'-',''),' ','')
WHERE Phone_Number NOT REGEXP '^[6-9][0-9]{9}$'
 AND REPLACE(REPLACE(REPLACE(Phone_Number,'+91',''),'-',''),' ','')
 REGEXP '^[6-9][0-9]{9}$';
SET @fix_phone = ROW_COUNT();
-- FIX 4: duplicate records
INSERT INTO Customers_Rejected
SELECT c.*, 'Duplicate customer record' FROM Customers c
JOIN (SELECT Row_No,
 ROW_NUMBER() OVER (PARTITION BY LOWER(TRIM(Email)) ORDER BY Row_No) AS rn
 FROM Customers WHERE Email IS NOT NULL AND TRIM(Email) <> '') d
 ON d.Row_No = c.Row_No
WHERE d.rn > 1;
SET @rej_dup_rec = ROW_COUNT();
DELETE FROM Customers WHERE Row_No IN
 (SELECT Row_No FROM Customers_Rejected WHERE Reject_Reason = 'Duplicate customer record');
-- FIX 5: missing names
INSERT INTO Customers_Rejected SELECT *, 'Missing name' FROM Customers
WHERE Customer_Name IS NULL OR TRIM(Customer_Name) = '';
SET @rej_name = ROW_COUNT();
DELETE FROM Customers WHERE Customer_Name IS NULL OR TRIM(Customer_Name) = '';
-- FIX 6: missing emails
INSERT INTO Customers_Rejected SELECT *, 'Missing email' FROM Customers
WHERE Email IS NULL OR TRIM(Email) = '';
SET @rej_mail = ROW_COUNT();
DELETE FROM Customers WHERE Email IS NULL OR TRIM(Email) = '';
-- FIX 7: unrepairable emails
INSERT INTO Customers_Rejected SELECT *, 'Invalid email (unrepairable)' FROM Customers
WHERE Email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)*[.][A-Za-z]{2,}$';
SET @rej_bad_mail = ROW_COUNT();
DELETE FROM Customers WHERE Email NOT REGEXP
 '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)*[.][A-Za-z]{2,}$';
-- FIX 8: unrepairable phones
INSERT INTO Customers_Rejected SELECT *, 'Invalid phone (unrepairable)' FROM Customers
WHERE Phone_Number IS NULL OR Phone_Number NOT REGEXP '^[6-9][0-9]{9}$';
SET @rej_phone = ROW_COUNT();
DELETE FROM Customers
WHERE Phone_Number IS NULL OR Phone_Number NOT REGEXP '^[6-9][0-9]{9}$';
-- FIX 9: invalid ages
INSERT INTO Customers_Rejected SELECT *, 'Invalid age' FROM Customers
WHERE Age IS NULL OR Age NOT BETWEEN 18 AND 100;
SET @rej_age = ROW_COUNT();
DELETE FROM Customers WHERE Age IS NULL OR Age NOT BETWEEN 18 AND 100;

-- STEP 9: Constraints
ALTER TABLE Customers
 DROP COLUMN Row_No,
 ADD PRIMARY KEY (Customer_ID),
 ADD UNIQUE KEY uq_customers_email (Email),
 MODIFY Customer_Name VARCHAR(100) NOT NULL,
 MODIFY Email VARCHAR(150) NOT NULL,
 ADD CONSTRAINT chk_phone CHECK (Phone_Number REGEXP '^[6-9][0-9]{9}$'),
 ADD CONSTRAINT chk_age CHECK (Age BETWEEN 18 AND 100);

-- STEP 10: Final report
-- 10.1 Error report by category
SELECT 'Duplicate customer IDs' AS Error_Type,
 (SELECT COUNT(*) - COUNT(DISTINCT Customer_ID) FROM Customers_Before) AS Found,
 @fix_dup_id AS Corrected_In_Place, 0 AS Removed
UNION ALL SELECT 'Duplicate customer records',
 (SELECT COUNT(*) FROM (SELECT ROW_NUMBER() OVER
 (PARTITION BY LOWER(TRIM(Email)) ORDER BY Row_No) rn FROM Customers_Before
 WHERE Email IS NOT NULL AND TRIM(Email) <> '') t WHERE rn > 1), 0, @rej_dup_rec
UNION ALL SELECT 'Missing names',
 (SELECT COUNT(*) FROM Customers_Before
 WHERE Customer_Name IS NULL OR TRIM(Customer_Name) = ''), 0, @rej_name
UNION ALL SELECT 'Missing emails',
 (SELECT COUNT(*) FROM Customers_Before
 WHERE Email IS NULL OR TRIM(Email) = ''), 0, @rej_mail
UNION ALL SELECT 'Invalid emails',
 (SELECT COUNT(*) FROM Customers_Before
 WHERE Email IS NOT NULL AND TRIM(Email) <> '' AND Email NOT REGEXP
 '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)*[.][A-Za-z]{2,}$'),
 @fix_email, @rej_bad_mail
UNION ALL SELECT 'Incorrect phone numbers',
 (SELECT COUNT(*) FROM Customers_Before
 WHERE Phone_Number IS NULL OR Phone_Number NOT REGEXP '^[6-9][0-9]{9}$'),
 @fix_phone, @rej_phone
UNION ALL SELECT 'Invalid ages',
 (SELECT COUNT(*) FROM Customers_Before
 WHERE Age IS NULL OR Age NOT BETWEEN 18 AND 100), 0, @rej_age;

-- 10.2 Before vs after (expect 500 | 50 | 12 | 38 | 462)
SELECT
 (SELECT COUNT(*) FROM Customers_Before) AS Records_Checked,
 @fix_dup_id + @fix_email + @fix_phone + @rej_dup_rec + @rej_name
 + @rej_mail + @rej_bad_mail + @rej_phone + @rej_age AS Errors_Found,
 @fix_dup_id + @fix_email + @fix_phone AS Errors_Corrected_In_Place,
 (SELECT COUNT(*) FROM Customers_Rejected) AS Records_Removed,
 (SELECT COUNT(*) FROM Customers) AS Valid_Records_Remaining;

-- 10.3 What was removed and why
SELECT Reject_Reason, COUNT(*) AS Records FROM Customers_Rejected GROUP BY Reject_Reason;

-- Clean-check: all four must return 0 rows
SELECT Customer_ID, COUNT(*) FROM Customers GROUP BY Customer_ID HAVING COUNT(*) > 1;
SELECT * FROM Customers WHERE Email NOT REGEXP
 '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)*[.][A-Za-z]{2,}$';
SELECT * FROM Customers WHERE Phone_Number NOT REGEXP '^[6-9][0-9]{9}$';
SELECT * FROM Customers WHERE Age NOT BETWEEN 18 AND 100;

-- STEP 11: Constraints must block bad data (run ONE AT A TIME)
-- Duplicate Customer_ID -> ERROR 1062
INSERT INTO Customers VALUES (1, 'Test User', 'test1@example.com', '9876543210', 30, 'Nellore', '2025-01-01');
-- Duplicate email -> ERROR 1062
INSERT INTO Customers VALUES (9001, 'Test User', 'customer1@example.com', '9876543210', 30, 'Nellore', '2025-01-01');
-- Invalid age -> ERROR 3819
INSERT INTO Customers VALUES (9002, 'Test User', 'test2@example.com', '9876543210', 150, 'Nellore', '2025-01-01');
-- Invalid phone -> ERROR 3819
INSERT INTO Customers VALUES (9003, 'Test User', 'test3@example.com', '12345', 30, 'Nellore', '2025-01-01');
-- Missing name -> ERROR 1048
INSERT INTO Customers VALUES (9004, NULL, 'test4@example.com', '9876543210', 30, 'Nellore', '2025-01-01');
