/*******************************************************************************
Recreation of:
	Package: WOKSCAD
	Procedure: P_GenerateWebCheckOutGrpMData (webcosectionmem.csv)
	
For data integrations report
*******************************************************************************/
CREATE OR REPLACE MATERIALIZED VIEW gold_integrations.webcheckout_webcosectionmem
AS
WITH CURRENT_TERM AS (
  SELECT MAX(stvterm_code) AS V_TERM
    FROM bronze_ellucian.saturn_stvterm
   WHERE substr(stvterm_code, 6, 1) = '0'
     AND current_date() >= stvterm_start_date
),
QUERY_ROWS AS (
  SELECT DISTINCT COALESCE(ssbsect_crn, '') || '.' || COALESCE(a.stvterm_code, '') AS section_col,
         spriden.spriden_id AS member_col,
         date_format(a.stvterm_start_date, 'MM/dd/yyyy') AS start_date_col,
         date_format(date_add(z.stvterm_start_date, -1), 'MM/dd/yyyy') AS end_date_col
    FROM bronze_ellucian.saturn_ssbsect, bronze_ellucian.saturn_sfrstcr, bronze_ellucian.saturn_stvterm a, bronze_ellucian.saturn_stvterm z, bronze_ellucian.saturn_spriden spriden
   WHERE ssbsect_term_code = sfrstcr_term_code
     AND sfrstcr_pidm = spriden.spriden_pidm
     AND spriden.spriden_change_ind IS NULL
     AND ssbsect_crn = sfrstcr_crn
     AND ssbsect_term_code = a.stvterm_code
     AND a.stvterm_code = (SELECT V_TERM FROM CURRENT_TERM)
     AND z.stvterm_code =
         (SELECT MIN(q.stvterm_code) 
            FROM bronze_ellucian.saturn_stvterm q 
           WHERE q.stvterm_start_date > current_date() 
             AND q.stvterm_code like '%0')
   UNION
  SELECT DISTINCT COALESCE(ssbsect_crn, '') || '.' || COALESCE(a.stvterm_code, '') AS section_col,
         '000012668' AS member_col,
         date_format(a.stvterm_start_date, 'MM/dd/yyyy') AS start_date_col,
         date_format(date_add(z.stvterm_start_date, -1), 'MM/dd/yyyy') AS end_date_col
    FROM bronze_ellucian.saturn_ssbsect, bronze_ellucian.saturn_sfrstcr, bronze_ellucian.saturn_stvterm a, bronze_ellucian.saturn_stvterm z
   WHERE ssbsect_term_code = sfrstcr_term_code
     AND ssbsect_crn = sfrstcr_crn
     AND ssbsect_term_code = a.stvterm_code
     AND a.stvterm_code = (SELECT V_TERM FROM CURRENT_TERM)
     AND sfrstcr_pidm = 6344762
     AND z.stvterm_code =
         (SELECT MIN(q.stvterm_code) 
            FROM bronze_ellucian.saturn_stvterm q 
           WHERE q.stvterm_start_date > current_date() 
             AND q.stvterm_code like '%0')
),
HEADER_ROWS AS (
  SELECT 1 AS REPORT_ORDER, 1 AS IS_HEADER, '__BEGIN_CONFIG__,,' AS REPORT_TEXT UNION ALL
  SELECT 2 AS REPORT_ORDER, 1 AS IS_HEADER, 'VERSION,2,' AS REPORT_TEXT UNION ALL
  SELECT 3 AS REPORT_ORDER, 1 AS IS_HEADER, 'TYPE,SECTION-MEMBER,' AS REPORT_TEXT UNION ALL
  SELECT 4 AS REPORT_ORDER, 1 AS IS_HEADER, 'ORIGIN,EXTERNAL,' AS REPORT_TEXT UNION ALL
  SELECT 5 AS REPORT_ORDER, 1 AS IS_HEADER, 'LOOKUP_COLUMNS,SECTION,MEMBER' AS REPORT_TEXT UNION ALL
  SELECT 6 AS REPORT_ORDER, 1 AS IS_HEADER, 'IMPORT_COLUMNS,START-DATE,END-DATE' AS REPORT_TEXT UNION ALL
  SELECT 7 AS REPORT_ORDER, 1 AS IS_HEADER, '__BEGIN_DATA__,,' AS REPORT_TEXT UNION ALL
  SELECT 8 AS REPORT_ORDER, 1 AS IS_HEADER, ',,' AS REPORT_TEXT UNION ALL
  SELECT 9 AS REPORT_ORDER, 1 AS IS_HEADER, 'SECTION,MEMBER,START-DATE,END-DATE' AS REPORT_TEXT
)
SELECT section_col, member_col, start_date_col, end_date_col,
       999 AS REPORT_ORDER, 0 AS IS_HEADER,
       REPLACE('"' || COALESCE(section_col, '') || '","' || COALESCE(member_col, '') || '","' || COALESCE(start_date_col, '') || '","' || COALESCE(end_date_col, '') || '"', '""', '') AS REPORT_TEXT
  FROM QUERY_ROWS
UNION ALL
SELECT NULL AS section_col, NULL AS member_col, NULL AS start_date_col, NULL AS end_date_col,
       REPORT_ORDER, IS_HEADER, REPORT_TEXT
  FROM HEADER_ROWS
ORDER BY REPORT_ORDER;
