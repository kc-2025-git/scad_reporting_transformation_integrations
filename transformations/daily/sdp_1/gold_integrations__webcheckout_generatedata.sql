/*******************************************************************************
Recreation of:
	Package: WOKSCAD
	Procedure: P_GenerateWebCheckOutData
	
For data integrations report
*******************************************************************************/
CREATE OR REPLACE MATERIALIZED VIEW gold_integrations.webcheckout_generatedata
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
         SELECT
             AST.PERSON_UID AS PIDM,
             AST.ID AS ID,
             UPPER
             (
                 CASE
                     WHEN LOWER (AST.STUDENT_LEVEL_DESC) = 'graduate'
                         THEN 'GRAD2'
                     ELSE LOWER (coalesce(AST.STUDENT_LEVEL_DESC,'')) || '-' || coalesce(REPLACE (DECODE (LOWER (AST.STUDENT_CLASSIFICATION_DESC),
                                                                                    'freshmen'                             , 'FRESHMAN',
                                                                                    LOWER (AST.STUDENT_CLASSIFICATION_DESC)), ' ', '-'),'')
                 END
             )
             AS PATRON,
             REPLACE (NVL (PD.PREFERRED_FIRST_NAME, PD.FIRST_NAME), '"', '') AS FIRST_NAME,
             REPLACE (PD.MIDDLE_INITIAL, '"', '') AS MIDDLE_INITIAL,
             REPLACE (PD.LAST_NAME, '"', '') AS LAST_NAME,
             'ACTIVE' AS STATUS,
             COALESCE (EMAIL.GOREMAL_EMAIL_ADDRESS, '') SCAD_EMAIL,
             AST.MAJOR_DESC MAJR_DESC1,
             LISTAGG (coalesce(SC.SUBJECT,'') || coalesce(SC.COURSE_NUMBER,''), ';') WITHIN GROUP (ORDER BY SC.SUBJECT, SC.COURSE_NUMBER) COURSES
         FROM bronze_ellucian.ODSMGR_ACADEMIC_STUDY AST
         INNER JOIN bronze_ellucian.ODSMGR_STUDENT_COURSE SC
         ON  SC.PERSON_UID = AST.PERSON_UID
         AND SC.ACADEMIC_PERIOD = AST.ACADEMIC_PERIOD
         AND SC.TRANSFER_COURSE_IND <> 'Y'
         AND SC.SECTION_ADD_DATE IS NOT NULL
         INNER JOIN bronze_ellucian.ODSMGR_PERSON_DETAIL PD
         ON  PD.PERSON_UID = AST.PERSON_UID
         LEFT JOIN (
                 SELECT
                     GOREMAL_PIDM,
                     LOWER (GOREMAL_EMAIL_ADDRESS) AS GOREMAL_EMAIL_ADDRESS,
                     ROW_NUMBER() OVER
                         (
                             PARTITION BY
                                 GOREMAL_PIDM
                             ORDER BY
                                 GOREMAL_EMAL_CODE ASC
                         )
                     AS RNUM
                 FROM bronze_ellucian.GENERAL_GOREMAL
                 WHERE
                     (
                         GOREMAL_EMAL_CODE = 'SCAD'
                         OR GOREMAL_EMAL_CODE = 'STEM')
                 AND GOREMAL_STATUS_IND = 'A'
                 ORDER BY
                     GOREMAL_EMAL_CODE
             )
             EMAIL
         ON  EMAIL.GOREMAL_PIDM = AST.PERSON_UID
         AND EMAIL.RNUM = 1
         WHERE
             AST.PRIMARY_PROGRAM_IND = 'Y'
         AND AST.REGISTERED_IND = 'Y'
         AND AST.ACADEMIC_PERIOD = (SELECT V_TERM FROM CURRENT_TERM)
         GROUP BY
             AST.PERSON_UID,
             AST.ID,
             UPPER
             (
                 CASE
                     WHEN LOWER (AST.STUDENT_LEVEL_DESC) = 'graduate'
                         THEN 'GRAD2'
                     ELSE LOWER (coalesce(AST.STUDENT_LEVEL_DESC,'')) || '-' || coalesce(REPLACE (DECODE (LOWER (AST.STUDENT_CLASSIFICATION_DESC),
                                                                                    'freshmen'                             , 'FRESHMAN',
                                                                                    LOWER (AST.STUDENT_CLASSIFICATION_DESC)), ' ', '-'),'')
                 END
             ),
             NVL (PD.PREFERRED_FIRST_NAME, PD.FIRST_NAME),
             PD.MIDDLE_INITIAL,
             PD.LAST_NAME,
             COALESCE (EMAIL.GOREMAL_EMAIL_ADDRESS, ''),
             AST.MAJOR_DESC
         -- Jira ISI-135 Add test record 000012668 Frank Neagle
         
         UNION
         
         SELECT
             5012249,
             '000012668',
             'GRAD2',
             'Frank',
             'A',
             'Neagle',
             'ACTIVE',
             'fneagl20@student.scad.edu',
             'Animation',
             ''
     )
     ,
     HEADER_ROWS AS (
         SELECT
             1 AS REPORT_ORDER,
             1 AS IS_HEADER,
             '__BEGIN_CONFIG__,,,,,,,,' AS REPORT_TEXT
         
         UNION
         
         SELECT
             2,1,
             'VERSION,2,,,,,,,'
         
         UNION
         
         SELECT
             3,1,
             'TYPE,PERSON,,,,,,,'
         
         UNION
         
         SELECT
             4,1,
             'ORIGIN,EXTERNAL,,,,,,,'
         
         UNION
         
         SELECT
             5,1,
             'LOOKUP_COLUMNS,USERID,,,,,,,'
         
         UNION
         
         SELECT
             6,1,
             'IMPORT_COLUMNS,PATRON-CLASS,FIRST-NAME,OTHER-NAME,LAST-NAME,STATUS,EMAIL,DEPARTMENT,NOTE'
         
         UNION
         
         SELECT
             7,1,
             '__BEGIN_DATA__,,,,,,,,'
         
         UNION
         
         SELECT
             8,1,
             ',,,,,,,,'
         
         UNION
         
         SELECT
             9,1,
             '"USERID",' || '"PATRON-CLASS",' || '"FIRST-NAME",' || '"OTHER-NAME",' || '"LAST-NAME",' || '"STATUS",' || '"EMAIL",' || '"DEPARTMENT",' || '"NOTE"'
     )
SELECT
    PIDM,
    ID,
    PATRON,
    FIRST_NAME,
    MIDDLE_INITIAL,
    LAST_NAME,
    STATUS,
    SCAD_EMAIL,
    MAJR_DESC1,
    COURSES,
    999 AS REPORT_ORDER,
    0 AS IS_HEADER,
    REPLACE ('"' || ID || '","' || coalesce(PATRON,'') || '","' || coalesce(FIRST_NAME,'') || '","' || coalesce(MIDDLE_INITIAL,'') || '","' || coalesce(LAST_NAME,'') || '","' || 'ACTIVE' || '","' || SCAD_EMAIL || '","' || coalesce(MAJR_DESC1,'') || '","' || coalesce(COURSES,'') || '"', '""') AS REPORT_TEXT
FROM QUERY_ROWS

UNION

SELECT
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    REPORT_ORDER,
    IS_HEADER,
    REPORT_TEXT
FROM HEADER_ROWS
ORDER BY
    REPORT_ORDER
;