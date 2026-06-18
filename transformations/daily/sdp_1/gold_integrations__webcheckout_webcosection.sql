/*******************************************************************************
Recreation of:
	Package: WOKSCAD
	Procedure: P_GenerateWebCheckOutGrpData (webcosection.csv)
	
For data integrations report
*******************************************************************************/
CREATE OR REPLACE MATERIALIZED VIEW gold_integrations.webcheckout_webcosection
AS
WITH CURRENT_TERM AS (
    SELECT
        MAX (STVTERM_CODE) AS V_TERM
    FROM bronze_ellucian.SATURN_STVTERM
    WHERE
        SUBSTR (STVTERM_CODE, 6, 1) = '0'
    AND CURRENT_DATE >= STVTERM_START_DATE
	),
QUERY_ROWS AS (
    SELECT DISTINCT
           coalesce(ssbsect_crn, '') || '.' || coalesce(stvterm_code, '') AS SECTION_IDENTIFIER,
           coalesce(ssbsect_subj_code, '') || '-' || coalesce(ssbsect_crse_numb, '') || '-' || coalesce(ssbsect_seq_numb, '') AS NAME,
           coalesce(ssbsect_subj_code, '') || '-' || coalesce(ssbsect_crse_numb, '') AS GROUP
      FROM bronze_ellucian.saturn_ssbsect
      JOIN bronze_ellucian.saturn_stvterm ON ssbsect_term_code = stvterm_code
     WHERE stvterm_code = (SELECT V_TERM FROM CURRENT_TERM)
),
HEADER_ROWS AS (
    SELECT 1 AS REPORT_ORDER, 1 AS IS_HEADER, '__BEGIN_CONFIG__,,' AS REPORT_TEXT 
    UNION
    SELECT 2, 1, 'VERSION,2,' 
    UNION
    SELECT 3, 1, 'TYPE,SECTION,' 
    UNION
    SELECT 4, 1, 'ORIGIN,EXTERNAL,' 
    UNION
    SELECT 5, 1, 'LOOKUP_COLUMNS,SECTION-IDENTIFIER' 
    UNION
    SELECT 6, 1, 'IMPORT_COLUMNS,NAME,GROUP' 
    UNION
    SELECT 7, 1, '__BEGIN_DATA__,,' 
    UNION
    SELECT 8, 1, ',,' 
    UNION
    SELECT 9, 1, 'SECTION-IDENTIFIER,NAME,GROUP' 
)
SELECT
    SECTION_IDENTIFIER,
    NAME,
    GROUP,
    999 AS REPORT_ORDER,
    0 AS IS_HEADER,
    REPLACE('"' || coalesce(SECTION_IDENTIFIER, '') || '","' || coalesce(NAME, '') || '","' || coalesce(GROUP, '') || '"', '""') AS REPORT_TEXT
FROM QUERY_ROWS

UNION

SELECT
    NULL,
    NULL,
    NULL,
    REPORT_ORDER,
    IS_HEADER,
    REPORT_TEXT
FROM HEADER_ROWS
ORDER BY
    REPORT_ORDER;
