USE [SMS]

-- Accounts to be modeled using the assigned criteria
DROP TABLE IF EXISTS #accounts;
SELECT DISTINCT
	Pt_No
INTO #accounts
FROM
	sms.dbo.Pt_Accounting_Reporting_ALT
WHERE
	payer_organization = 'Anthem'
	AND product_class = 'Commercial'
	AND Tot_Chgs > 0
	AND FC != 'X'
	and Acct_Type = 'OP'
	AND Unit_Date is null;


-- Claim info for these accounts
DROP TABLE IF EXISTS #claim_info;
SELECT
	Patient_Account_Number,
	Pt_NO,
	Ins_CD,
	Unit_NO,
	Seq_No,
	INST,
	File_Creation_Date,
	Billing_NPI,
	Claim_Filing_Indicator_Code,
	Subscriber_Zip,
	Subscriber_Gender,
	Charge_Amount,
	Facility_Type_Code,
	Facility_Code,
	Frequency_Code,
	Statement_From_Date,
	Admission_Type_Code,
	Admission_Source_Code,
	Patient_Status_Code,
	Medical_Record_Number,
	Attending_Phys_ID,
	Operating_Phys_ID,
	Rendering_Provider_ID,
	number,
	parent_name,
	INST_info_code,
	info_Code_description_short,
	info_Code_qualifier,
	info_Code,
	Line_Revenue_Code,
	Line_Procedure_Code,
	Line_Amount_Total
INTO #claim_info
FROM
	sms.dbo.c_INST_JOIN_ALL_v as a
WHERE
	EXISTS (
		SELECT
			1
		FROM
			#accounts as b
		WHERE
			a.Pt_NO = b.Pt_No
	)
	AND info_Code_description_short = 'Principal Diagnosis'
	--AND Pt_NO in ('10151199493','10115214685')
;


-- To get the status of each claim, the feedback from the first remit will be used

-- Map each claim to its remits
DROP TABLE IF EXISTS #all_claims_and_remits;
SELECT DISTINCT
	a.Pt_NO,
	a.INST, -- claim number
	a.File_Creation_Date, -- claim sent date
	a.REMIT, -- remit number
	a.Check_EFT_Date -- remit date
INTO #all_claims_and_remits
FROM
	sms.dbo.c_INST_REMIT_Recon_v as a
WHERE
	EXISTS (
		SELECT
			1
		FROM
			#accounts as b
		WHERE
			a.Pt_NO = b.Pt_No
	);


-- Get just the first remit sent back for each claim, and the claim status associated with that remit
DROP TABLE IF EXISTS #first_remits;
WITH CTE AS (
	SELECT
		*,
		ROW_NUMBER() OVER(PARTITION BY INST ORDER BY Pt_NO, File_Creation_Date, Check_EFT_Date, INST, REMIT) as row_num
	FROM
		#all_claims_and_remits
)
SELECT
	CTE.Pt_NO,
	CTE.INST,
	CTE.File_Creation_Date,
	CTE.REMIT,
	CTE.Check_EFT_Date,
	REMIT.Claim_Status
INTO #first_remits
FROM
	CTE
	LEFT JOIN sms.dbo.c_REMIT_JOIN_ALL_tbl as REMIT
		ON CTE.Pt_NO = REMIT.Pt_NO
			AND CTE.REMIT = REMIT.REMIT
WHERE row_num = 1;



-- Top 100 Procedure Codes; need these because there are too many to pivot out
DROP TABLE IF EXISTS #top_procedure_codes;
SELECT TOP 100
	Line_Procedure_Code
INTO #top_procedure_codes
FROM
	#claim_info
GROUP BY
	Line_Procedure_Code
ORDER BY 
	COUNT(Line_Procedure_Code) DESC


-- Format the claims data to include only the top 100 procedure codes, for all others fill in 'Other'
DROP TABLE IF EXISTS #claim_info_formatted;
SELECT DISTINCT
	a.Patient_Account_Number,
	a.Pt_NO,
	a.Ins_CD,
	a.Unit_NO,
	a.Seq_No,
	a.INST,
	a.File_Creation_Date,
	a.Billing_NPI,
	a.Claim_Filing_Indicator_Code,
	a.Subscriber_Zip,
	a.Subscriber_Gender,
	a.Charge_Amount,
	a.Facility_Type_Code,
	a.Facility_Code,
	a.Frequency_Code,
	a.Statement_From_Date,
	a.Admission_Type_Code,
	a.Admission_Source_Code,
	a.Patient_Status_Code,
	a.Medical_Record_Number,
	a.Attending_Phys_ID,
	a.Operating_Phys_ID,
	a.Rendering_Provider_ID,
	a.number,
	a.parent_name,
	a.INST_info_code,
	a.info_Code_description_short,
	a.info_Code_qualifier,
	a.info_Code,
	a.Line_Revenue_Code,
	[Line_Procedure_Code] = CASE
				WHEN b.Line_Procedure_Code IS NULL
				THEN 'Other'
				ELSE b.Line_Procedure_Code
				END,
	a.Line_Amount_Total,
	ClaimStatus = CASE
				WHEN c.Claim_Status IN (
						'Processed As Primary',
						'Processed as Primary, Forwarded to Additional Payer(s)',
						'Processed As Secondary',
						'Processed as Secondary, Forwarded to Additional Payer(s)',
						'Processed As Tertiary')
				THEN 'Approved'
				WHEN c.Claim_Status IN (
						'Pended',
						'Reversal of Previous Payment')
				THEN 'Unknown'
				WHEN c.Claim_Status = 'Denied'
				THEN 'Denied'
				ELSE c.Claim_Status
				END
INTO #claim_info_formatted
FROM
	#claim_info as a
	LEFT JOIN #top_procedure_codes as b
		ON a.Line_Procedure_Code = b.Line_Procedure_Code
	LEFT JOIN #first_remits as c
		ON a.INST = c.INST


/*
All data before pivoting
*/

-- Drop then create the table
DROP TABLE IF EXISTS dbo.c_claims_model_all_data_tbl;
CREATE TABLE dbo.c_claims_model_all_data_tbl
	(
		c_claims_model_all_data_tblId INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, -- primary key column
		Patient_Account_Number VARCHAR(83),
		Pt_NO NUMERIC(18,0),
		Ins_CD VARCHAR(83),
		Unit_NO NUMERIC(18,0),
		Seq_No VARCHAR(30),
		INST INT,
		File_Creation_Date DATE,
		Billing_NPI VARCHAR(166),
		Claim_Filing_Indicator_Code VARCHAR(41),
		Subscriber_Zip VARCHAR(41),
		Subscriber_Gender VARCHAR(41),
		Charge_Amount DECIMAL(16,4),
		Facility_Type_Code VARCHAR(41),
		Facility_Code VARCHAR(41),
		Frequency_Code VARCHAR(41),
		Statement_From_Date DATE,
		Admission_Type_Code VARCHAR(41),
		Admission_Source_Code VARCHAR(41),
		Patient_Status_Code VARCHAR(41),
		Medical_Record_Number VARCHAR(83),
		Attending_Phys_ID VARCHAR(166),
		Operating_Phys_ID VARCHAR(166),
		Rendering_Provider_ID VARCHAR(166),
		number VARCHAR(255),
		parent_name VARCHAR(255),
		INST_info_code INT,
		info_Code_description_short VARCHAR(60),
		info_Code_qualifier VARCHAR(3),
		info_Code VARCHAR(30),
		Line_Revenue_Code VARCHAR(83),
		Line_Procedure_Code VARCHAR(83),
		Line_Amount_Total DECIMAL(16,4),
		ClaimStatus VARCHAR(60)
	);
-- Insert claim info from accounts in #accounts
INSERT INTO dbo.c_claims_model_all_data_tbl (
	Patient_Account_Number,
	Pt_NO,
	Ins_CD,
	Unit_NO,
	Seq_No,
	INST,
	File_Creation_Date,
	Billing_NPI,
	Claim_Filing_Indicator_Code,
	Subscriber_Zip,
	Subscriber_Gender,
	Charge_Amount,
	Facility_Type_Code,
	Facility_Code,
	Frequency_Code,
	Statement_From_Date,
	Admission_Type_Code,
	Admission_Source_Code,
	Patient_Status_Code,
	Medical_Record_Number,
	Attending_Phys_ID,
	Operating_Phys_ID,
	Rendering_Provider_ID,
	number,
	parent_name,
	INST_info_code,
	info_Code_description_short,
	info_Code_qualifier,
	info_Code,
	Line_Revenue_Code,
	Line_Procedure_Code,
	Line_Amount_Total,
	ClaimStatus
	)
SELECT *
FROM #claim_info_formatted


/*
Revenue Code View
*/

-- Drop view if it exists
IF OBJECT_ID('dbo.c_claims_model_rev_codes_v', 'V') IS NOT NULL
DROP VIEW dbo.c_claims_model_rev_codes_v
GO
;


-- Create view
CREATE VIEW dbo.c_claims_model_rev_codes_v
AS
SELECT 1 as 'test'
GO
;


-- Populate view by pivoting out the rev codes with the sum of the line totals
DECLARE
	@rev_code_cols as NVARCHAR(MAX),
	@rev_cd_HeaderNameCollection AS NVARCHAR(MAX),
	@rev_code_query as NVARCHAR(MAX);

SELECT
	@rev_code_cols = STUFF(
					(
						SELECT DISTINCT
							',' + QUOTENAME(Line_Revenue_Code)
						FROM
							sms.dbo.c_claims_model_all_data_tbl
						FOR
							XML PATH(''), TYPE
					).value('.', 'NVARCHAR(MAX)')
			,1,1,'')
			;

SELECT @rev_cd_HeaderNameCollection= ISNULL(@rev_cd_HeaderNameCollection + ',','') 
       + QUOTENAME(Line_Revenue_Code) + ' as rev_cd_' + CAST(Line_Revenue_Code AS VARCHAR(16))
FROM (SELECT DISTINCT Line_Revenue_Code FROM sms.dbo.c_claims_model_all_data_tbl) AS rev_codes

SET @rev_code_query = '
				ALTER VIEW dbo.c_claims_model_rev_codes_v
				AS
				SELECT
					INST as INST_rev_code_v,
					' + @rev_cd_HeaderNameCollection + '
				FROM (
						SELECT
							INST,
							Line_Revenue_Code,
							Line_Amount_Total
						FROM
							sms.dbo.c_claims_model_all_data_tbl
					) x
				PIVOT (
						SUM(Line_Amount_Total)
						FOR Line_Revenue_Code IN (' + @rev_code_cols + ')
					) p1
					;
					'

EXECUTE (@rev_code_query);


/*
Line Procedure Code View
*/

-- Drop view if it exists
IF OBJECT_ID('dbo.c_claims_model_line_procedure_codes_v', 'V') IS NOT NULL
DROP VIEW dbo.c_claims_model_line_procedure_codes_v
GO
;


-- Create view
CREATE VIEW dbo.c_claims_model_line_procedure_codes_v
AS
SELECT 1 as 'test'
GO
;


-- Populate view by pivoting out the line procedure codes with the count of each code, identifing if it was used or not
DECLARE
	@line_procedure_code_cols as NVARCHAR(MAX),
	@line_procedure_code_HeaderNameCollection AS NVARCHAR(MAX),
	@line_procedure_code_query as NVARCHAR(MAX);

SELECT
	@line_procedure_code_cols = STUFF(
					(
						SELECT DISTINCT
							',' + QUOTENAME(Line_Procedure_Code)
						FROM
							sms.dbo.c_claims_model_all_data_tbl
						FOR
							XML PATH(''), TYPE
					).value('.', 'NVARCHAR(MAX)')
			,1,1,'')
			;

SELECT @line_procedure_code_HeaderNameCollection= ISNULL(@line_procedure_code_HeaderNameCollection + ',','') 
       + QUOTENAME(Line_Procedure_Code) + ' as px_cd_' + CAST(Line_Procedure_Code AS VARCHAR(16))
FROM (SELECT DISTINCT Line_Procedure_Code FROM sms.dbo.c_claims_model_all_data_tbl) AS px_codes

SET @line_procedure_code_query = '
				ALTER VIEW dbo.c_claims_model_line_procedure_codes_v
				AS
				SELECT
					INST as INST_line_procedure_code_v,
					' + @line_procedure_code_HeaderNameCollection + '
				FROM (
						SELECT
							INST,
							Line_Procedure_Code
						FROM
							sms.dbo.c_claims_model_all_data_tbl
					) x
				PIVOT (
						COUNT(Line_Procedure_Code)
						FOR Line_Procedure_Code IN (' + @line_procedure_code_cols + ')
					) p1
					;
					'

EXECUTE (@line_procedure_code_query);


/*
Final view to feed into the model
*/

-- Drop view if it exists
IF OBJECT_ID('dbo.c_claims_model_dataset_v', 'V') IS NOT NULL
DROP VIEW dbo.c_claims_model_dataset_v
GO
;


-- Create view
CREATE VIEW dbo.c_claims_model_dataset_v
AS
SELECT 1 as 'test'
GO
;

ALTER VIEW dbo.c_claims_model_dataset_v
AS
SELECT DISTINCT
	a.Patient_Account_Number,
	a.Pt_NO,
	a.Ins_CD,
	a.Unit_NO,
	a.Seq_No,
	a.INST,
	a.File_Creation_Date,
	a.Billing_NPI,
	a.Claim_Filing_Indicator_Code,
	a.Subscriber_Zip,
	a.Subscriber_Gender,
	a.Charge_Amount,
	a.Facility_Type_Code,
	a.Facility_Code,
	a.Frequency_Code,
	a.Statement_From_Date,
	a.Admission_Type_Code,
	a.Admission_Source_Code,
	a.Patient_Status_Code,
	a.Medical_Record_Number,
	a.Attending_Phys_ID,
	a.Operating_Phys_ID,
	a.Rendering_Provider_ID,
	a.number,
	a.parent_name,
	a.INST_info_code,
	a.info_Code_description_short,
	a.info_Code_qualifier,
	a.info_Code,
	b.*,
	c.*,
	a.ClaimStatus as [Claim_Status]
FROM
	dbo.c_claims_model_all_data_tbl as a
	LEFT JOIN dbo.c_claims_model_rev_codes_v as b
		ON a.INST = b.INST_rev_code_v
	LEFT JOIN dbo.c_claims_model_line_procedure_codes_v as c
		ON a.INST = c.INST_line_procedure_code_v
GO
;