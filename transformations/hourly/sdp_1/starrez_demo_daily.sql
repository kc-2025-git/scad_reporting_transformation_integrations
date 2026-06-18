/*******************************************************************************
Recreation of:
	Package: BANINST1.wpksrez
	Procedure: p_create_file_line (StarRez_Demo_Daily.log)
	
For data integrations report
*******************************************************************************/
CREATE OR REPLACE MATERIALIZED VIEW gold_integrations.starrez_demo_daily
TBLPROPERTIES ('delta.columnMapping.mode' = 'name')
AS
WITH CURRENT_TERM AS (
    SELECT MIN(STVTERM_CODE) AS TermIn
    FROM bronze_ellucian.saturn_stvterm
    WHERE stvterm_end_date >= current_date() AND stvterm_code > '201510'
),
params AS (
    SELECT 
        (SELECT TermIn FROM CURRENT_TERM) AS TermIn,
        (SELECT stvterm_acyr_code FROM bronze_ellucian.saturn_stvterm stvterm WHERE stvterm_code = (SELECT TermIn FROM CURRENT_TERM) LIMIT 1) AS tmpACYR,
        (SELECT MIN(stvterm_acyr_code) FROM bronze_ellucian.saturn_stvterm stvterm WHERE stvterm_acyr_code > (SELECT stvterm_acyr_code FROM bronze_ellucian.saturn_stvterm stvterm WHERE stvterm_code = (SELECT TermIn FROM CURRENT_TERM) LIMIT 1)) AS tmpFutACYR
),
sgrclsr_rules AS (
    SELECT
        r.sgrclsr_seq_no,
        r.sgrclsr_clas_code,
        r.sgrclsr_levl_code,
        r.sgrclsr_from_hours,
        r.sgrclsr_to_hours,
        collect_set(c.sgrcatt_atts_code) AS required_atts,
        CASE WHEN count(c.sgrcatt_atts_code) = 0 THEN 1 ELSE 0 END AS no_atts_flag
    FROM bronze_ellucian.saturn_sgrclsr r
    LEFT JOIN bronze_ellucian.saturn_sgrcatt c ON c.sgrcatt_seq_no = r.sgrclsr_seq_no
    GROUP BY 1, 2, 3, 4, 5
),
gpa_credits AS (
    SELECT 
        shrlgpa_pidm, 
        shrlgpa_levl_code,
        round(CAST(shrlgpa_gpa AS DOUBLE), 4) AS tmpGPA,
        round(CAST(COALESCE(shrlgpa_hours_earned, 0) AS DOUBLE), 3) AS tmpCredit
    FROM bronze_ellucian.saturn_shrlgpa
    WHERE shrlgpa_gpa_type_ind = 'O'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY shrlgpa_pidm, shrlgpa_levl_code ORDER BY (SELECT NULL)) = 1
),
student_holds AS (
    SELECT 
        sprhold_pidm,
        MAX(CASE WHEN sprhold_hldd_code IN ('RH','AH','VC','AA','LR','NS','IN','ES','GA','GD','AD','UN','RC') THEN '1' ELSE '0' END) AS entrydetail_academichold,
        MAX(CASE WHEN sprhold_hldd_code IN ('DI','JS') THEN '1' ELSE '0' END) AS entrydetail_incidenthold,
        MAX(CASE WHEN sprhold_hldd_code IN ('LF','AM','BR','DH','GR','RB','SA','CO','DC','IL','AT','FA','PP','PW','NC','CA','RP','TR','LH','FN') THEN '1' ELSE '0' END) AS entrydetail_accounthold
    FROM bronze_ellucian.saturn_sprhold
    WHERE sprhold_to_date > current_date()
    GROUP BY sprhold_pidm
),
student_phones AS (
    SELECT 
        sprtele_pidm, 
        sprtele_tele_code,
        substring(
            concat(
                CASE WHEN COALESCE(CAST(sprtele_phone_area AS STRING), '0') = '0' THEN '' ELSE CASE WHEN length(CAST(sprtele_phone_area AS STRING)) = 3 THEN concat(COALESCE(sprtele_phone_area, ''), '-') ELSE CAST(sprtele_phone_area AS STRING) END END,
                CASE WHEN COALESCE(CAST(sprtele_phone_number AS STRING), '0') = '0' THEN '' ELSE CASE WHEN length(CAST(sprtele_phone_number AS STRING)) = 7 THEN concat(substring(COALESCE(sprtele_phone_number, ''), 1, 3), '-', substring(COALESCE(sprtele_phone_number, ''), 4, 4)) ELSE CAST(sprtele_phone_number AS STRING) END END
            ), 1, 12
        ) AS phone
    FROM bronze_ellucian.saturn_sprtele 
    WHERE sprtele_status_ind IS NULL AND sprtele_tele_code IN ('MA', 'MOB', 'PR')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY sprtele_pidm, sprtele_tele_code ORDER BY CASE WHEN sprtele_primary_ind = 'Y' THEN 1 ELSE 2 END ASC, sprtele_seqno DESC) = 1
),
student_addresses AS (
    SELECT 
        spraddr.spraddr_pidm,
        spraddr.spraddr_atyp_code,
        spraddr.spraddr_street_line1 AS street_line1,
        substring(concat(COALESCE(spraddr.spraddr_street_line2, ''), CASE WHEN COALESCE(spraddr.spraddr_street_line3, '0') = '0' THEN '' ELSE concat(' ', COALESCE(spraddr.spraddr_street_line3, '')) END), 1, 80) AS street_line2,
        substring(spraddr.spraddr_city, 1, 60) AS city,
        spraddr.spraddr_stat_code AS stat_code,
        substring(spraddr.spraddr_zip, 1, 10) AS zip,
        CASE WHEN COALESCE(wxwalknation.sf_iso, '0') = '0' THEN 'US' ELSE wxwalknation.sf_iso END AS iso
    FROM bronze_ellucian.saturn_spraddr spraddr
    LEFT OUTER JOIN bronze_scad.scadsf_wxwalknation wxwalknation ON wxwalknation.scadem_banner_code = spraddr.spraddr_natn_code
    WHERE spraddr.spraddr_atyp_code IN ('MA', 'PR') AND spraddr.spraddr_status_ind IS NULL AND (current_date() <= spraddr.spraddr_to_date OR spraddr.spraddr_to_date IS NULL)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY spraddr.spraddr_pidm, spraddr.spraddr_atyp_code ORDER BY spraddr.spraddr_activity_date DESC) = 1
),
student_emergency AS (
    SELECT 
        spremrg.spremrg_pidm,
        substring(concat_ws(' ', spremrg.spremrg_first_name, spremrg.spremrg_last_name), 1, 80) AS contact_name,
        substring(spremrg.spremrg_street_line1, 1, 80) AS street_line1,
        substring(CASE WHEN COALESCE(spremrg.spremrg_street_line2, '0') = '0' THEN '' ELSE concat_ws(' ', spremrg.spremrg_street_line2, spremrg.spremrg_street_line3) END, 1, 80) AS street_line2,
        spremrg.spremrg_city AS city,
        spremrg.spremrg_stat_code AS stat_code,
        substring(spremrg.spremrg_zip, 1, 10) AS zip,
        substring(concat(
            CASE WHEN COALESCE(CAST(spremrg.spremrg_phone_area AS STRING), '0') = '0' THEN '' ELSE CASE WHEN length(CAST(spremrg.spremrg_phone_area AS STRING)) = 3 THEN concat(COALESCE(spremrg.spremrg_phone_area, ''), '-') ELSE CAST(spremrg.spremrg_phone_area AS STRING) END END,
            CASE WHEN COALESCE(CAST(spremrg.spremrg_phone_number AS STRING), '0') = '0' THEN '' ELSE CASE WHEN length(CAST(spremrg.spremrg_phone_number AS STRING)) = 7 THEN concat(substring(COALESCE(spremrg.spremrg_phone_number, ''), 1, 3), '-', substring(COALESCE(spremrg.spremrg_phone_number, ''), 4, 4)) ELSE CAST(spremrg.spremrg_phone_number AS STRING) END END
        ), 1, 25) AS phone,
        stvrelt.stvrelt_desc AS relt_desc
    FROM bronze_ellucian.saturn_spremrg spremrg
    LEFT JOIN bronze_ellucian.saturn_stvrelt stvrelt ON stvrelt.stvrelt_code = spremrg.spremrg_relt_code
    QUALIFY ROW_NUMBER() OVER (PARTITION BY spremrg.spremrg_pidm ORDER BY spremrg.spremrg_activity_date DESC) = 1
),
sgbstdn_max_terms AS (
    SELECT sgbstdn_pidm, 
           MAX(sgbstdn_term_code_eff) as max_term, 
           MAX(CASE WHEN sgbstdn_camp_code = 'L' THEN sgbstdn_term_code_eff END) as max_lac_term,
           MAX(CASE WHEN sgbstdn_term_code_eff <= params.TermIn THEN sgbstdn_term_code_eff END) as max_term_capped
    FROM bronze_ellucian.saturn_sgbstdn
    CROSS JOIN params
    GROUP BY sgbstdn_pidm
),
tbrdepo_max_terms AS (
    SELECT tbrdepo_pidm, MAX(tbrdepo_term_code) as max_term
    FROM bronze_ellucian.taismgr_tbrdepo
    WHERE tbrdepo_detail_code_deposit IN ('DHOU','DRST','DHOS','DRES','DREH','DOHK','DHOK','DPHK','DHRS','DHRA','DHSA','DHAT')
    GROUP BY tbrdepo_pidm
),
tbrdepo_lac_max_terms AS (
    SELECT tbrdepo_pidm, MAX(tbrdepo_term_code) as max_term
    FROM bronze_ellucian.taismgr_tbrdepo
    WHERE tbrdepo_detail_code_deposit IN ('DLAC','DLAS')
    GROUP BY tbrdepo_pidm
),
cumulative_shrtgpa AS (
    SELECT 
        shrtgpa_pidm,
        shrtgpa_levl_code,
        shrtgpa_term_code,
        COALESCE(SUM(shrtgpa_hours_earned) OVER (PARTITION BY shrtgpa_pidm, shrtgpa_levl_code ORDER BY shrtgpa_term_code ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) as cum_hrs
    FROM bronze_ellucian.saturn_shrtgpa
    WHERE shrtgpa_gpa_type_ind IN ('I','T')
),
base_students AS (
    -- 1. Housing Deposit Students (New)
    SELECT DISTINCT 
		1 as grp_num,
        spriden.spriden_pidm,
        spriden.spriden_id as entry_id1,
        CAST(NULL AS STRING) as entry_id2,
        spbpers.spbpers_name_prefix as entry_nametitle,
        spriden.spriden_last_name as entry_namelast,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN CASE WHEN COALESCE(spriden.spriden_first_name, '0') = '0' THEN 'NoName' ELSE spriden.spriden_first_name END ELSE spbpers.spbpers_pref_first_name END as entry_namefirst,
        CAST(NULL AS STRING) as entry_nameother,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN spriden.spriden_first_name ELSE spbpers.spbpers_pref_first_name END as entry_namepreferred,
        spbpers.SPBPERS_SEX as entry_birth_genderenum,
        date_format(to_date(spbpers.spbpers_birth_date, 'dd-MMM-yyyy'), 'MM/dd/yyyy') AS entry_dob,
        '0' as entrydetail_married,
        CASE WHEN spbpers.SPBPERS_CONFID_IND = 'Y' THEN '1' ELSE '0' END as entry_directoryflagprivacy,
        stvclas.stvclas_desc as entrydetail_enrollmentclass,
        stvlevl.stvlevl_desc as entrydetail_enrollmentlevel,
        CASE stvstyp.stvstyp_code WHEN 'P' THEN 'Graduate First Term' WHEN 'F' THEN 'Freshman First Term' WHEN 'D' THEN 'Dual Enrollment Freshman' WHEN 'A' THEN 'Graduate First Term' WHEN 'J' THEN 'Freshman First Term' ELSE stvstyp.stvstyp_desc END as entrydetail_enrollmentstatus,
        stvmajr.stvmajr_desc,
        d.tbrdepo_term_code AS tmpPulledTerm,
        gpa.tmpGPA,
        COALESCE(gpa.tmpCredit, 0) AS tmpCredit
    FROM bronze_ellucian.saturn_spriden spriden
    JOIN bronze_ellucian.saturn_spbpers spbpers ON spriden.spriden_pidm = spbpers.spbpers_pidm
    JOIN bronze_ellucian.taismgr_tbrdepo d ON d.tbrdepo_pidm = spbpers.spbpers_pidm
    JOIN tbrdepo_max_terms d_max ON d_max.tbrdepo_pidm = d.tbrdepo_pidm AND d_max.max_term = d.tbrdepo_term_code
    JOIN bronze_ellucian.saturn_sgbstdn g ON g.sgbstdn_pidm = spbpers.spbpers_pidm 
    JOIN sgbstdn_max_terms g_max ON g_max.sgbstdn_pidm = g.sgbstdn_pidm AND g_max.max_term = g.sgbstdn_term_code_eff
    JOIN bronze_ellucian.saturn_stvlevl stvlevl ON g.sgbstdn_levl_code = stvlevl.stvlevl_code
    JOIN bronze_ellucian.saturn_stvstyp stvstyp ON stvstyp.stvstyp_code = g.sgbstdn_styp_code
    JOIN bronze_ellucian.saturn_stvmajr stvmajr ON stvmajr.stvmajr_code = g.sgbstdn_majr_code_1
    CROSS JOIN params
    LEFT JOIN gpa_credits gpa ON gpa.shrlgpa_pidm = g.SGBSTDN_PIDM AND gpa.shrlgpa_levl_code = g.SGBSTDN_LEVL_CODE
    LEFT JOIN LATERAL (SELECT cum_hrs FROM cumulative_shrtgpa c2 WHERE c2.shrtgpa_pidm = g.sgbstdn_pidm AND c2.shrtgpa_levl_code = g.sgbstdn_levl_code AND c2.shrtgpa_term_code <= d.tbrdepo_term_code ORDER BY c2.shrtgpa_term_code DESC, c2.cum_hrs DESC  LIMIT 1) h ON true
    LEFT JOIN LATERAL (SELECT r.sgrclsr_clas_code FROM sgrclsr_rules r WHERE r.sgrclsr_levl_code = g.sgbstdn_levl_code AND COALESCE(h.cum_hrs, 0) BETWEEN r.sgrclsr_from_hours AND r.sgrclsr_to_hours ORDER BY r.no_atts_flag DESC, r.sgrclsr_clas_code ASC LIMIT 1) cls ON true
    LEFT JOIN bronze_ellucian.saturn_stvclas stvclas ON stvclas.stvclas_code = substring(cls.sgrclsr_clas_code, 1, 2)
    WHERE spriden.spriden_change_ind is null 
    AND d.tbrdepo_term_code >= params.TermIn
    AND d.tbrdepo_detail_code_deposit IN ('DHOU','DRST','DHOS','DRES','DREH','DHOK','DOHK','DPHK','DHRS','DHRA','DHSA','DHAT')
    AND NOT EXISTS (SELECT 1 FROM gold_integrations.starrez_demo_daily_control wsrsrez JOIN bronze_ellucian.saturn_stvterm stvterm ON wsrsrez.wsrsrez_last_acyr >= stvterm.stvterm_acyr_code WHERE CAST(wsrsrez.wsrsrez_pidm AS DECIMAL(8,0)) = spriden.spriden_pidm AND stvterm.stvterm_code = d.tbrdepo_term_code AND wsrsrez.wsrsrez_status_ind = 'A')

    UNION
    -- 2. Sent Students with Changes
    SELECT DISTINCT 
        2 as grp_num,
		spriden.spriden_pidm,
        spriden.spriden_id as entry_id1,
        CAST(NULL AS STRING) as entry_id2,
        spbpers.spbpers_name_prefix as entry_nametitle,
        spriden.spriden_last_name as entry_namelast,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN CASE WHEN COALESCE(spriden.spriden_first_name, '0') = '0' THEN 'NoName' ELSE spriden.spriden_first_name END ELSE spbpers.spbpers_pref_first_name END as entry_namefirst,
        CAST(NULL AS STRING) as entry_nameother,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN spriden.spriden_first_name ELSE spbpers.spbpers_pref_first_name END as entry_namepreferred,
        spbpers.SPBPERS_SEX as entry_birth_genderenum,
        date_format(to_date(spbpers.spbpers_birth_date, 'dd-MMM-yyyy'), 'MM/dd/yyyy') AS entry_dob,
        '0' as entrydetail_married,
        CASE WHEN spbpers.SPBPERS_CONFID_IND = 'Y' THEN '1' ELSE '0' END as entry_directoryflagprivacy,
        stvclas.stvclas_desc as entrydetail_enrollmentclass,
        stvlevl.stvlevl_desc as entrydetail_enrollmentlevel,
        CASE stvstyp.stvstyp_code WHEN 'P' THEN 'Graduate First Term' WHEN 'F' THEN 'Freshman First Term' WHEN 'D' THEN 'Dual Enrollment Freshman' WHEN 'A' THEN 'Graduate First Term' WHEN 'J' THEN 'Freshman First Term' ELSE stvstyp.stvstyp_desc END as entrydetail_enrollmentstatus,
        stvmajr.stvmajr_desc,
        wsrsrez.wsrsrez_last_term AS tmpPulledTerm,
        gpa.tmpGPA,
        COALESCE(gpa.tmpCredit, 0) AS tmpCredit
    FROM bronze_ellucian.saturn_spriden spriden
    JOIN bronze_ellucian.saturn_spbpers spbpers ON spriden.spriden_pidm = spbpers.spbpers_pidm
    JOIN bronze_ellucian.saturn_sgbstdn g ON g.sgbstdn_pidm = spbpers.spbpers_pidm 
    JOIN sgbstdn_max_terms g_max ON g_max.sgbstdn_pidm = g.sgbstdn_pidm AND g_max.max_term = g.sgbstdn_term_code_eff
    JOIN bronze_ellucian.saturn_stvlevl stvlevl ON g.sgbstdn_levl_code = stvlevl.stvlevl_code
    JOIN bronze_ellucian.saturn_stvstyp stvstyp ON stvstyp.stvstyp_code = g.sgbstdn_styp_code
    JOIN bronze_ellucian.saturn_stvmajr stvmajr ON stvmajr.stvmajr_code = g.sgbstdn_majr_code_1
    JOIN gold_integrations.starrez_demo_daily_control wsrsrez ON CAST(wsrsrez.wsrsrez_pidm AS DECIMAL(8,0)) = spriden.spriden_pidm
    CROSS JOIN params
    LEFT JOIN gpa_credits gpa ON gpa.shrlgpa_pidm = g.SGBSTDN_PIDM AND gpa.shrlgpa_levl_code = g.SGBSTDN_LEVL_CODE
    LEFT JOIN LATERAL (SELECT cum_hrs FROM cumulative_shrtgpa c2 WHERE c2.shrtgpa_pidm = g.sgbstdn_pidm AND c2.shrtgpa_levl_code = g.sgbstdn_levl_code AND c2.shrtgpa_term_code <= params.TermIn ORDER BY c2.shrtgpa_term_code DESC, c2.cum_hrs DESC  LIMIT 1) h ON true
    LEFT JOIN LATERAL (SELECT r.sgrclsr_clas_code FROM sgrclsr_rules r WHERE r.sgrclsr_levl_code = g.sgbstdn_levl_code AND COALESCE(h.cum_hrs, 0) BETWEEN r.sgrclsr_from_hours AND r.sgrclsr_to_hours ORDER BY r.no_atts_flag DESC, r.sgrclsr_clas_code ASC LIMIT 1) cls ON true
    LEFT JOIN bronze_ellucian.saturn_stvclas stvclas ON stvclas.stvclas_code = substring(cls.sgrclsr_clas_code, 1, 2)
    WHERE spriden.spriden_change_ind is null 
    AND wsrsrez.wsrsrez_last_acyr >= params.tmpACYR
    AND wsrsrez.wsrsrez_status_ind = 'A'
    AND (
        EXISTS (SELECT 'em' FROM bronze_ellucian.general_goremal goremal WHERE goremal.goremal_pidm = spriden.spriden_pidm AND goremal.goremal_emal_code = 'STEM' AND goremal.goremal_activity_date > wsrsrez.wsrsrez_last_sent)
        OR EXISTS (SELECT 'addr' FROM bronze_ellucian.saturn_spraddr spraddr WHERE spraddr.spraddr_pidm = spriden.spriden_pidm AND spraddr.spraddr_atyp_code IN ('MA','PR') AND spraddr.spraddr_activity_date > wsrsrez.wsrsrez_last_sent)
        OR EXISTS (SELECT 'tele' FROM bronze_ellucian.saturn_sprtele sprtele WHERE sprtele.sprtele_pidm = spriden.spriden_pidm AND sprtele.sprtele_tele_code IN ('MA','PR') AND sprtele.sprtele_activity_date > wsrsrez.wsrsrez_last_sent)
        OR (spriden.spriden_activity_date > wsrsrez.wsrsrez_last_sent)
        OR (spbpers.spbpers_activity_date > wsrsrez.wsrsrez_last_sent)
        OR (g.sgbstdn_activity_date > wsrsrez.wsrsrez_last_sent)
        OR EXISTS (SELECT 'citz' FROM bronze_ellucian.general_gobintl gobintl WHERE gobintl.gobintl_pidm = spriden.spriden_pidm AND gobintl.gobintl_activity_date > wsrsrez.wsrsrez_last_sent)
        OR EXISTS (SELECT 'visa' FROM bronze_ellucian.general_gorvisa gorvisa WHERE gorvisa.gorvisa_pidm = spriden.spriden_pidm AND gorvisa.gorvisa_activity_date > wsrsrez.wsrsrez_last_sent) 
        OR EXISTS (SELECT 'emgr' FROM bronze_ellucian.saturn_spremrg spremrg WHERE spremrg.spremrg_pidm = spriden.spriden_pidm AND spremrg.spremrg_activity_date > wsrsrez.wsrsrez_last_sent)
        OR EXISTS (SELECT 'admit' FROM bronze_ellucian.saturn_saradap x1 WHERE x1.saradap_pidm = spriden.spriden_pidm AND x1.saradap_activity_date > wsrsrez.wsrsrez_last_sent AND x1.saradap_apst_code not in ('1','W') AND x1.saradap_term_code_entry = (SELECT MAX(sarappd_term_code_entry) FROM bronze_ellucian.saturn_sarappd WHERE sarappd_pidm = x1.saradap_pidm AND sarappd_term_code_entry = x1.saradap_term_code_entry AND sarappd_apdc_code = 'CP'))
        OR EXISTS (SELECT 'AdmAdv' FROM bronze_ellucian.saturn_sorainf sorainf WHERE sorainf.sorainf_pidm = spriden.spriden_pidm AND sorainf.sorainf_radm_code = 'ADMCOUN' AND sorainf.sorainf_term_code >= params.TermIn AND sorainf.sorainf_activity_date > wsrsrez.wsrsrez_last_sent)
        OR EXISTS (SELECT 'sprt' FROM bronze_ellucian.saturn_sgrsprt sgrsprt WHERE sgrsprt.sgrsprt_pidm = spriden.spriden_pidm AND sgrsprt.sgrsprt_term_code = params.TermIn AND sgrsprt.sgrsprt_spst_code = 'AC' AND sgrsprt.sgrsprt_elig_code = 'AC' AND sgrsprt.sgrsprt_activity_date > wsrsrez.wsrsrez_last_sent)
        OR EXISTS (SELECT 'HOUS' FROM bronze_ellucian.saturn_saraatt saraatt WHERE saraatt.saraatt_pidm = spriden.spriden_pidm AND saraatt.saraatt_term_code >= params.TermIn AND saraatt.saraatt_atts_code = 'HOUS' AND saraatt.saraatt_activity_date > wsrsrez.wsrsrez_last_sent)  
        OR EXISTS (SELECT 'HLDD' FROM bronze_ellucian.saturn_sprhold sprhold WHERE sprhold.sprhold_hldd_code IN ('RH','AH','AM','BR','DH','DI','GR','AA','RB','LR','SA','CO','DC','NS','IL','IN','AT','ES','GA','GD','AD','UN','RC','CA','RP','JS','TR','LH','DI','JS','AM','BR','SA','CO','DC','IL','FA','CA','RP') AND sprhold.sprhold_pidm = spriden.spriden_pidm AND sprhold.sprhold_release_ind <> 'Y' AND sprhold.sprhold_activity_date > wsrsrez.wsrsrez_last_sent)  
        OR wsrsrez.wsrsrez_last_sent < (SELECT MAX(d1.tbrdepo_activity_date) FROM bronze_ellucian.taismgr_tbrdepo d1 WHERE d1.tbrdepo_pidm = spriden.spriden_pidm AND d1.tbrdepo_term_code >= params.TermIn AND d1.tbrdepo_detail_code_deposit IN ('DHOU','DRST','DHOS','DRES','DREH','DOHK','DHOK','DPHK','DHRS','DHRA','DHSA','DHAT') GROUP BY d1.tbrdepo_pidm)
    )

    UNION
    -- 3. LACOSTE Students
    SELECT DISTINCT 
        3 as grp_num,
		spriden.spriden_pidm,
        spriden.spriden_id as entry_id1,
        CAST(NULL AS STRING) as entry_id2,
        spbpers.spbpers_name_prefix as entry_nametitle,
        spriden.spriden_last_name as entry_namelast,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN CASE WHEN COALESCE(spriden.spriden_first_name, '0') = '0' THEN 'NoName' ELSE spriden.spriden_first_name END ELSE spbpers.spbpers_pref_first_name END as entry_namefirst,
        CAST(NULL AS STRING) as entry_nameother,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN spriden.spriden_first_name ELSE spbpers.spbpers_pref_first_name END as entry_namepreferred,
        spbpers.SPBPERS_SEX as entry_birth_genderenum,
        date_format(to_date(spbpers.spbpers_birth_date, 'dd-MMM-yyyy'), 'MM/dd/yyyy') AS entry_dob,
        '0' as entrydetail_married,
        CASE WHEN spbpers.SPBPERS_CONFID_IND = 'Y' THEN '1' ELSE '0' END as entry_directoryflagprivacy,
        stvclas.stvclas_desc as entrydetail_enrollmentclass,
        stvlevl.stvlevl_desc as entrydetail_enrollmentlevel,
        CASE stvstyp.stvstyp_code WHEN 'P' THEN 'Graduate First Term' WHEN 'F' THEN 'Freshman First Term' WHEN 'D' THEN 'Dual Enrollment Freshman' WHEN 'A' THEN 'Graduate First Term' WHEN 'J' THEN 'Freshman First Term' ELSE stvstyp.stvstyp_desc END as entrydetail_enrollmentstatus,
        stvmajr.stvmajr_desc,
        d.tbrdepo_term_code AS tmpPulledTerm,
        gpa.tmpGPA,
        COALESCE(gpa.tmpCredit, 0) AS tmpCredit
    FROM bronze_ellucian.saturn_spriden spriden
    JOIN bronze_ellucian.saturn_spbpers spbpers ON spriden.spriden_pidm = spbpers.spbpers_pidm
    JOIN bronze_ellucian.taismgr_tbrdepo d ON d.tbrdepo_pidm = spbpers.spbpers_pidm
    JOIN tbrdepo_lac_max_terms d_max ON d_max.tbrdepo_pidm = d.tbrdepo_pidm AND d_max.max_term = d.tbrdepo_term_code
    JOIN bronze_ellucian.saturn_sgbstdn g ON g.sgbstdn_pidm = spbpers.spbpers_pidm AND g.sgbstdn_camp_code = 'L'
    JOIN bronze_ellucian.saturn_stvterm L ON d.tbrdepo_term_code = L.stvterm_code
    JOIN bronze_ellucian.saturn_stvlevl stvlevl ON g.sgbstdn_levl_code = stvlevl.stvlevl_code
    JOIN bronze_ellucian.saturn_stvstyp stvstyp ON stvstyp.stvstyp_code = g.sgbstdn_styp_code
    JOIN bronze_ellucian.saturn_stvmajr stvmajr ON stvmajr.stvmajr_code = g.sgbstdn_majr_code_1
    CROSS JOIN params
    LEFT JOIN gpa_credits gpa ON gpa.shrlgpa_pidm = g.SGBSTDN_PIDM AND gpa.shrlgpa_levl_code = g.SGBSTDN_LEVL_CODE
    LEFT JOIN LATERAL (SELECT cum_hrs FROM cumulative_shrtgpa c2 WHERE c2.shrtgpa_pidm = g.sgbstdn_pidm AND c2.shrtgpa_levl_code = g.sgbstdn_levl_code AND c2.shrtgpa_term_code <= d.tbrdepo_term_code ORDER BY c2.shrtgpa_term_code DESC, c2.cum_hrs DESC  LIMIT 1) h ON true
    LEFT JOIN LATERAL (SELECT r.sgrclsr_clas_code FROM sgrclsr_rules r WHERE r.sgrclsr_levl_code = g.sgbstdn_levl_code AND COALESCE(h.cum_hrs, 0) BETWEEN r.sgrclsr_from_hours AND r.sgrclsr_to_hours ORDER BY r.no_atts_flag DESC, r.sgrclsr_clas_code ASC LIMIT 1) cls ON true
    LEFT JOIN bronze_ellucian.saturn_stvclas stvclas ON stvclas.stvclas_code = substring(cls.sgrclsr_clas_code, 1, 2)
    WHERE spriden.spriden_change_ind is null 
    AND d.tbrdepo_term_code >= params.TermIn
    AND d.tbrdepo_detail_code_deposit IN ('DLAC','DLAS')
    AND g.sgbstdn_term_code_eff = (SELECT MAX(g1.sgbstdn_term_code_eff) FROM bronze_ellucian.saturn_sgbstdn g1 WHERE g1.sgbstdn_pidm = g.sgbstdn_pidm AND g1.sgbstdn_camp_code = 'L' AND g1.sgbstdn_term_code_eff <= d.tbrdepo_term_code)
    AND NOT EXISTS (SELECT 1 FROM bronze_ellucian.taismgr_tbrdepo d2 JOIN bronze_ellucian.saturn_stvterm dterm ON d2.tbrdepo_term_code = dterm.stvterm_code WHERE d2.tbrdepo_pidm = d.tbrdepo_pidm AND d2.tbrdepo_detail_code_deposit IN ('DHOU','DRST','DHOS','DRES','DREH','DOHK','DHOK','DPHK','DHRS','DHRA','DHSA','DHAT') AND dterm.stvterm_acyr_code = L.stvterm_acyr_code) 
    AND NOT EXISTS (SELECT 1 FROM gold_integrations.starrez_demo_daily_control wsrsrez JOIN bronze_ellucian.saturn_stvterm stvterm ON wsrsrez.wsrsrez_last_acyr = stvterm.stvterm_acyr_code WHERE CAST(wsrsrez.wsrsrez_pidm AS DECIMAL(8,0)) = spriden.spriden_pidm)

    UNION
    -- 4. Active Registration Students
    SELECT 
        4 as grp_num,
		spriden.spriden_pidm,
        spriden.spriden_id as entry_id1,
        CAST(NULL AS STRING) as entry_id2,
        spbpers.spbpers_name_prefix as entry_nametitle,
        spriden.spriden_last_name as entry_namelast,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN CASE WHEN COALESCE(spriden.spriden_first_name, '0') = '0' THEN 'NoName' ELSE spriden.spriden_first_name END ELSE spbpers.spbpers_pref_first_name END as entry_namefirst,
        CAST(NULL AS STRING) as entry_nameother,
        CASE WHEN COALESCE(spbpers.spbpers_pref_first_name, '0') = '0' THEN spriden.spriden_first_name ELSE spbpers.spbpers_pref_first_name END as entry_namepreferred,
        spbpers.SPBPERS_SEX as entry_birth_genderenum,
        date_format(to_date(spbpers.spbpers_birth_date, 'dd-MMM-yyyy'), 'MM/dd/yyyy') AS entry_dob,
        '0' as entrydetail_married,
        CASE WHEN spbpers.SPBPERS_CONFID_IND = 'Y' THEN '1' ELSE '0' END as entry_directoryflagprivacy,
        stvclas.stvclas_desc as entrydetail_enrollmentclass,
        stvlevl.stvlevl_desc as entrydetail_enrollmentlevel,
        CASE stvstyp.stvstyp_code WHEN 'P' THEN 'Graduate First Term' WHEN 'F' THEN 'Freshman First Term' WHEN 'D' THEN 'Dual Enrollment Freshman' WHEN 'A' THEN 'Graduate First Term' WHEN 'J' THEN 'Freshman First Term' ELSE stvstyp.stvstyp_desc END as entrydetail_enrollmentstatus,
        stvmajr.stvmajr_desc,
        MIN(sfrstcr.sfrstcr_term_code) AS tmpPulledTerm,
        MAX(gpa.tmpGPA) AS tmpGPA,
        MAX(COALESCE(gpa.tmpCredit, 0)) AS tmpCredit
    FROM bronze_ellucian.saturn_spriden spriden
    JOIN bronze_ellucian.saturn_spbpers spbpers ON spriden.spriden_pidm = spbpers.spbpers_pidm
    JOIN bronze_ellucian.saturn_sfrstcr sfrstcr ON sfrstcr.sfrstcr_pidm = spriden.spriden_pidm
    JOIN bronze_ellucian.saturn_sgbstdn g ON g.sgbstdn_pidm = spbpers.spbpers_pidm 
    JOIN bronze_ellucian.saturn_stvterm L ON L.stvterm_code = sfrstcr.sfrstcr_term_code
    JOIN bronze_ellucian.saturn_stvlevl stvlevl ON g.sgbstdn_levl_code = stvlevl.stvlevl_code
    JOIN bronze_ellucian.saturn_stvstyp stvstyp ON stvstyp.stvstyp_code = g.sgbstdn_styp_code
    JOIN bronze_ellucian.saturn_stvmajr stvmajr ON stvmajr.stvmajr_code = g.sgbstdn_majr_code_1
    CROSS JOIN params
    LEFT JOIN gpa_credits gpa ON gpa.shrlgpa_pidm = g.SGBSTDN_PIDM AND gpa.shrlgpa_levl_code = g.SGBSTDN_LEVL_CODE
    LEFT JOIN LATERAL (SELECT cum_hrs FROM cumulative_shrtgpa c2 WHERE c2.shrtgpa_pidm = g.sgbstdn_pidm AND c2.shrtgpa_levl_code = g.sgbstdn_levl_code AND c2.shrtgpa_term_code <= sfrstcr.sfrstcr_term_code ORDER BY c2.shrtgpa_term_code DESC, c2.cum_hrs DESC LIMIT 1) h ON true
    LEFT JOIN LATERAL (SELECT r.sgrclsr_clas_code FROM sgrclsr_rules r WHERE r.sgrclsr_levl_code = g.sgbstdn_levl_code AND COALESCE(h.cum_hrs, 0) BETWEEN r.sgrclsr_from_hours AND r.sgrclsr_to_hours ORDER BY r.no_atts_flag DESC, r.sgrclsr_clas_code ASC LIMIT 1) cls ON true
    LEFT JOIN bronze_ellucian.saturn_stvclas stvclas ON stvclas.stvclas_code = substring(cls.sgrclsr_clas_code, 1, 2)
    WHERE spriden.spriden_change_ind is null 
    AND sfrstcr.sfrstcr_rsts_code IN ('RE','RW','AU')
    AND sfrstcr.sfrstcr_term_code >= params.TermIn
    AND g.sgbstdn_term_code_eff = (SELECT MAX(g1.sgbstdn_term_code_eff) FROM bronze_ellucian.saturn_sgbstdn g1 WHERE g1.sgbstdn_pidm = g.sgbstdn_pidm AND g1.sgbstdn_term_code_eff <= sfrstcr.sfrstcr_term_code)
    AND NOT EXISTS (SELECT 1 FROM bronze_ellucian.taismgr_tbrdepo d2 JOIN bronze_ellucian.saturn_stvterm dterm ON d2.tbrdepo_term_code = dterm.stvterm_code WHERE d2.tbrdepo_pidm = spriden.spriden_pidm AND d2.tbrdepo_detail_code_deposit IN ('DHOU','DRST','DHOS','DRES','DREH','DOHK','DHOK','DPHK','DHRS','DHRA','DHSA','DHAT') AND dterm.stvterm_acyr_code = L.stvterm_acyr_code) 
    AND NOT EXISTS (SELECT 1 FROM gold_integrations.starrez_demo_daily_control wsrsrez WHERE CAST(wsrsrez.wsrsrez_pidm AS DECIMAL(8,0)) = spriden.spriden_pidm AND wsrsrez.wsrsrez_last_acyr >= L.stvterm_acyr_code)
    GROUP BY spriden.spriden_pidm, spriden.spriden_id, spbpers.spbpers_name_prefix, spriden.spriden_last_name, spbpers.spbpers_pref_first_name, spriden.spriden_first_name, spbpers.SPBPERS_SEX, spbpers.spbpers_birth_date, spbpers.SPBPERS_CONFID_IND, stvclas.stvclas_desc, stvlevl.stvlevl_desc, stvstyp.stvstyp_code, stvstyp.stvstyp_desc, stvmajr.stvmajr_desc, g.sgbstdn_pidm, g.sgbstdn_levl_code
),
enriched_students AS (
    SELECT 
        b.*,
        COALESCE(wxn.sf_iso, 'US') AS entrydetail_citizenship_countryid_abbreviation,
        COALESCE(visatype.stvvtyp_desc, 'US') AS entrydetail_visadetails,
        COALESCE(term_opt1.term1, term_opt2.term2) AS entrydetail_enrollmentterm,
        CASE WHEN saraatt.saraatt_pidm IS NOT NULL THEN 'Y' ELSE NULL END AS entrycustomfield_housingexemptionindicator,
        COALESCE(sh.entrydetail_academichold, '0') AS entrydetail_academichold,
        COALESCE(sh.entrydetail_incidenthold, '0') AS entrydetail_incidenthold,
        COALESCE(sh.entrydetail_accounthold, '0') AS entrydetail_accounthold,
        actc.stvactc_desc AS entrydetail_athleteteam,
        CASE WHEN ferpa.student_pidm IS NOT NULL THEN '1' ELSE '0' END AS entrycustomfield_ferpa,
        goremal.goremal_email_address AS entryaddress_mailing_email,
        emgr.contact_name AS emgr_contact_name, emgr.street_line1 AS emgr_street_line1, emgr.street_line2 AS emgr_street_line2, emgr.city AS emgr_city, emgr.stat_code AS emgr_stat_code, emgr.zip AS emgr_zip, emgr.phone AS emgr_phone, emgr.relt_desc AS emgr_relt_desc,
        ma.street_line1 AS ma_street_line1, ma.street_line2 AS ma_street_line2, ma.city AS ma_city, ma.stat_code AS ma_stat_code, ma.zip AS ma_zip, ma.iso AS ma_iso,
        pr.street_line1 AS pr_street_line1, pr.street_line2 AS pr_street_line2, pr.city AS pr_city, pr.stat_code AS pr_stat_code, pr.zip AS pr_zip, pr.iso AS pr_iso,
        ph_ma.phone AS ma_phone,
        ph_mob.phone AS mob_phone,
        ph_pr.phone AS pr_phone
    FROM base_students b
    LEFT JOIN (SELECT gobintl_pidm, gobintl_natn_code_legal FROM bronze_ellucian.general_gobintl QUALIFY ROW_NUMBER() OVER(PARTITION BY gobintl_pidm ORDER BY gobintl_activity_date DESC)=1) gbi ON gbi.gobintl_pidm = b.spriden_pidm
    LEFT JOIN bronze_scad.scadsf_wxwalknation wxn ON gbi.gobintl_natn_code_legal = wxn.scadem_banner_code
    LEFT JOIN (SELECT gorvisa_pidm, gorvisa_vtyp_code FROM bronze_ellucian.general_gorvisa QUALIFY ROW_NUMBER() OVER(PARTITION BY gorvisa_pidm ORDER BY gorvisa_activity_date DESC)=1) gv ON gv.gorvisa_pidm = b.spriden_pidm
    LEFT JOIN bronze_ellucian.saturn_stvvtyp visatype ON gv.gorvisa_vtyp_code = visatype.stvvtyp_code
    LEFT JOIN (SELECT x1.saradap_pidm, MAX(x1.saradap_term_code_entry) AS term1 FROM bronze_ellucian.saturn_saradap x1 INNER JOIN bronze_ellucian.saturn_sarappd sarappd ON sarappd.sarappd_pidm = x1.saradap_pidm AND sarappd.sarappd_term_code_entry = x1.saradap_term_code_entry WHERE x1.saradap_apst_code NOT IN ('1','W') AND sarappd.sarappd_apdc_code = 'CP' GROUP BY x1.saradap_pidm) term_opt1 ON term_opt1.saradap_pidm = b.spriden_pidm
    LEFT JOIN (SELECT saradap_pidm, MAX_BY(saradap_term_code_entry, saradap_appl_no) AS term2 FROM bronze_ellucian.saturn_saradap GROUP BY saradap_pidm) term_opt2 ON term_opt2.saradap_pidm = b.spriden_pidm
    LEFT JOIN (SELECT saraatt_pidm FROM bronze_ellucian.saturn_saraatt WHERE saraatt_atts_code = 'HOUS' GROUP BY saraatt_pidm) saraatt ON saraatt.saraatt_pidm = b.spriden_pidm
    LEFT JOIN student_holds sh ON sh.sprhold_pidm = b.spriden_pidm
    LEFT JOIN (SELECT s.sgrsprt_pidm, a.stvactc_desc FROM bronze_ellucian.saturn_sgrsprt s JOIN bronze_ellucian.saturn_stvactc a ON a.stvactc_code = s.sgrsprt_actc_code CROSS JOIN params WHERE s.sgrsprt_term_code = params.TermIn AND s.sgrsprt_spst_code = 'AC' AND s.sgrsprt_elig_code = 'AC' QUALIFY ROW_NUMBER() OVER(PARTITION BY s.sgrsprt_pidm ORDER BY s.sgrsprt_activity_date DESC)=1) actc ON actc.sgrsprt_pidm = b.spriden_pidm
    LEFT JOIN (SELECT student_pidm FROM bronze_scad.grailssf_ferpa GROUP BY student_pidm) ferpa ON ferpa.student_pidm = b.spriden_pidm
    LEFT JOIN (SELECT goremal_pidm, goremal_email_address FROM bronze_ellucian.general_goremal WHERE goremal_status_ind = 'A' AND goremal_emal_code = 'STEM' QUALIFY ROW_NUMBER() OVER(PARTITION BY goremal_pidm ORDER BY goremal_activity_date DESC)=1) goremal ON goremal.goremal_pidm = b.spriden_pidm
    LEFT JOIN student_emergency emgr ON emgr.spremrg_pidm = b.spriden_pidm
    LEFT JOIN student_addresses ma ON ma.spraddr_pidm = b.spriden_pidm AND ma.spraddr_atyp_code = 'MA'
    LEFT JOIN student_addresses pr ON pr.spraddr_pidm = b.spriden_pidm AND pr.spraddr_atyp_code = 'PR'
    LEFT JOIN student_phones ph_ma ON ph_ma.sprtele_pidm = b.spriden_pidm AND ph_ma.sprtele_tele_code = 'MA'
    LEFT JOIN student_phones ph_mob ON ph_mob.sprtele_pidm = b.spriden_pidm AND ph_mob.sprtele_tele_code = 'MOB'
    LEFT JOIN student_phones ph_pr ON ph_pr.sprtele_pidm = b.spriden_pidm AND ph_pr.sprtele_tele_code = 'PR'
),
enriched_students_with_advisor AS (
    SELECT 
        e.*,
        adv.tmpADMAdviser
    FROM enriched_students e
    LEFT JOIN (
        SELECT sorainf.sorainf_pidm, sorainf.sorainf_term_code, concat_ws(' ', spriden.spriden_first_name, spriden.spriden_last_name) AS tmpADMAdviser
        FROM bronze_ellucian.saturn_sorainf sorainf
        JOIN bronze_ellucian.saturn_spriden spriden ON sorainf.sorainf_arol_pidm = spriden.spriden_pidm
        WHERE spriden.spriden_change_ind IS NULL AND sorainf.sorainf_radm_code = 'ADMCOUN'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY sorainf.sorainf_pidm, sorainf.sorainf_term_code ORDER BY sorainf.sorainf_activity_date DESC) = 1
    ) adv ON adv.sorainf_pidm = e.spriden_pidm AND adv.sorainf_term_code = e.entrydetail_enrollmentterm
),
term_raw_data AS (
    SELECT pidm, suffix, term, camp, pdate, src, rn
    FROM (
        SELECT pidm, suffix, term, camp, pdate, src, ROW_NUMBER() OVER (PARTITION BY pidm, suffix ORDER BY term DESC, pdate ASC) AS RN
        FROM (
          SELECT d1.tbrdepo_pidm AS pidm, substring(d1.tbrdepo_term_code, -2, 2) AS suffix, d1.tbrdepo_term_code AS term,
              (SELECT CASE WHEN g.sgbstdn_camp_code = 'O' THEN 'M' ELSE g.sgbstdn_camp_code END FROM bronze_ellucian.saturn_sgbstdn g WHERE g.sgbstdn_pidm = d1.tbrdepo_pidm AND g.sgbstdn_term_code_eff <= d1.tbrdepo_term_code ORDER BY g.sgbstdn_term_code_eff DESC LIMIT 1) AS camp,
              date_format(d1.tbrdepo_entry_date, 'MM/dd/yyyy hh:mm:ss a') AS pdate, 1 AS src
          FROM bronze_ellucian.taismgr_tbrdepo d1 WHERE d1.tbrdepo_detail_code_deposit IN ('DHOU','DRST','DHOS','DRES','DREH','DHOK','DOHK','DPHK','DHRS','DHRA','DHSA','DHAT')
        )
        UNION ALL
        SELECT sgbstdn_pidm AS pidm, substring(sgbstdn_term_code_eff, -2, 2) AS suffix, sgbstdn_term_code_eff AS term, CASE WHEN sgbstdn_camp_code = 'O' THEN 'M' ELSE sgbstdn_camp_code END AS camp, NULL AS pdate, 2 AS src, ROW_NUMBER() OVER (PARTITION BY sgbstdn_pidm, substring(sgbstdn_term_code_eff, -2, 2) ORDER BY sgbstdn_term_code_eff DESC) AS rn
        FROM bronze_ellucian.saturn_sgbstdn sgbstdn
    ) sub WHERE sub.rn = 1
),
term_winners AS (
    SELECT pidm, suffix, term, camp, pdate FROM (SELECT pidm, suffix, term, camp, pdate, ROW_NUMBER() OVER (PARTITION BY pidm, suffix ORDER BY term DESC, src ASC) AS win_rn FROM term_raw_data) sub2 WHERE sub2.win_rn = 1
),
rs_overrides AS (
    SELECT sf_contact.pidm, substring(opp.entering_term__c, 1, 6) AS term, CASE stvcamp_code WHEN 'RSA' THEN 'A' WHEN 'RSM' THEN 'M' ELSE stvcamp_code END AS RS_Camp
    FROM bronze_scad.scadsf_sf_contact sf_contact
    JOIN bronze_scad.scadsf_sf_opportunity opp ON opp.contact__c = sf_contact.id
    JOIN bronze_ellucian.saturn_stvcamp stvcamp ON opp.location__c = stvcamp_desc
    WHERE opp.student_type__c = 'Rising Star' AND opp.isdeleted <> 'Y' AND EXISTS (SELECT 1 FROM bronze_ellucian.saturn_saradap saradap JOIN bronze_ellucian.saturn_sarappd sarappd ON saradap.saradap_pidm = sarappd.sarappd_pidm AND saradap.saradap_term_code_entry = sarappd.sarappd_term_code_entry WHERE saradap.saradap_pidm = sf_contact.pidm AND sarappd.sarappd_term_code_entry = substring(opp.entering_term__c, 1, 6) AND saradap.saradap_styp_code = 'R' AND sarappd.sarappd_apdc_code IN ('MT','RS','ND'))
),
final_term_data AS (
    SELECT w.pidm, w.suffix, w.term, CASE WHEN w.camp IN ('R','RSM','RSA') THEN COALESCE(r.RS_Camp, 'M') ELSE w.camp END AS camp, w.pdate
    FROM term_winners w LEFT JOIN rs_overrides r ON r.pidm = w.pidm AND r.term = w.term
),
term_pivoted AS (
    SELECT pidm,
        MAX(CASE WHEN suffix = '10' THEN term END) AS t10_term, MAX(CASE WHEN suffix = '10' THEN camp END) AS t10_camp, MAX(CASE WHEN suffix = '10' THEN pdate END) AS t10_pdate,
        MAX(CASE WHEN suffix = '20' THEN term END) AS t20_term, MAX(CASE WHEN suffix = '20' THEN camp END) AS t20_camp, MAX(CASE WHEN suffix = '20' THEN pdate END) AS t20_pdate,
        MAX(CASE WHEN suffix = '30' THEN term END) AS t30_term, MAX(CASE WHEN suffix = '30' THEN camp END) AS t30_camp, MAX(CASE WHEN suffix = '30' THEN pdate END) AS t30_pdate,
        MAX(CASE WHEN suffix = '40' THEN term END) AS t40_term, MAX(CASE WHEN suffix = '40' THEN camp END) AS t40_camp, MAX(CASE WHEN suffix = '40' THEN pdate END) AS t40_pdate
    FROM final_term_data GROUP BY pidm
),
QUERY_ROWS AS (
    SELECT 
        e.grp_num,
        e.entry_id1 AS `Entry.ID1`,
        e.entry_id2 AS `Entry.ID2`,
        e.entry_nametitle AS `Entry.NameTitle`,
        e.entry_namelast AS `Entry.NameLast`,
        e.entry_namefirst AS `Entry.NameFirst`,
        e.entry_nameother AS `Entry.NameOther`,
        e.entry_namepreferred AS `Entry.NamePreferred`,
        e.entry_birth_genderenum AS `Entry.Birth_GenderEnum`,
        e.entry_dob AS `Entry.DOB`,
        e.entrydetail_married AS `EntryDetail.Married`,
        e.entrydetail_citizenship_countryid_abbreviation AS `EntryDetail.Citizenship_CountryID.Abbreviation`,
        CAST(NULL AS STRING) AS `EntryDetail.Ethnicity`,
        e.entry_directoryflagprivacy AS `Entry.DirectoryFlagPrivacy`,
        CAST(NULL AS STRING) AS `EntryAddress[Alternate Email].Email`,
        e.entryaddress_mailing_email AS `EntryAddress[Mailing].Email`,
        e.ma_street_line1 AS `EntryAddress[Mailing].Street`,
        e.ma_street_line2 AS `EntryAddress[Mailing].Street2`,
        e.ma_city AS `EntryAddress[Mailing].City`,
        e.ma_stat_code AS `EntryAddress[Mailing].StateProvince`,
        e.ma_zip AS `EntryAddress[Mailing].ZipPostcode`,
        e.ma_iso AS `EntryAddress[Mailing].CountryID.Abbreviation`,
        e.ma_phone AS `EntryAddress[Mailing].Phone`,
        e.mob_phone AS `EntryAddress[Mailing].PhoneMobileCell`,
        CAST(NULL AS STRING) AS `EntryAddress[Home].Email`,
        e.pr_street_line1 AS `EntryAddress[Home].Street`,
        e.pr_street_line2 AS `EntryAddress[Home].Street2`,
        e.pr_city AS `EntryAddress[Home].City`,
        e.pr_stat_code AS `EntryAddress[Home].StateProvince`,
        e.pr_zip AS `EntryAddress[Home].ZipPostcode`,
        e.pr_iso AS `EntryAddress[Home].CountryID.Abbreviation`,
        e.pr_phone AS `EntryAddress[Home].Phone`,
        CAST(NULL AS STRING) AS `EntryAddress[Home].PhoneMobileCell`,
        e.emgr_contact_name AS `EntryAddress[Emergency].ContactName`,
        e.emgr_street_line1 AS `EntryAddress[Emergency].Street`,
        e.emgr_street_line2 AS `EntryAddress[Emergency].Street2`,
        e.emgr_city AS `EntryAddress[Emergency].City`,
        e.emgr_stat_code AS `EntryAddress[Emergency].StateProvince`,
        e.emgr_zip AS `EntryAddress[Emergency].ZipPostcode`,
        e.emgr_phone AS `EntryAddress[Emergency].Phone`,
        e.emgr_relt_desc AS `EntryAddress[Emergency].Relationship`,
        e.entrydetail_enrollmentclass AS `EntryDetail.EnrollmentClass`,
        e.entrydetail_enrollmentlevel AS `EntryDetail.EnrollmentLevel`,
        e.entrydetail_enrollmentstatus AS `EntryDetail.EnrollmentStatus`,
        e.entrydetail_enrollmentterm AS `EntryDetail.EnrollmentTerm`,
        e.entrydetail_academichold AS `EntryDetail.AcademicHold`,
        e.entrydetail_incidenthold AS `EntryDetail.IncidentHold`,
        e.entrydetail_accounthold AS `EntryDetail.AccountHold`,
        CASE WHEN e.entrydetail_athleteteam IS NOT NULL THEN '1' ELSE '0' END AS `EntryDetail.Athlete`,
        e.entrydetail_athleteteam AS `EntryDetail.AthleteTeam`,
        e.stvmajr_desc AS `EntryDetail.CurrentMajor`,
        '0' AS `EntryDetail.CurrentHours`,
        COALESCE(e.tmpCredit, 0) AS `EntryDetail.CumulativeHours`,
        '0' AS `EntryDetail.CurrentGPA`,
        COALESCE(e.tmpGPA, 0) AS `EntryDetail.CumulativeGPA`,
        CAST(NULL AS STRING) AS `EntryDetail.ExpectedGraduationDate`,
        CAST(NULL AS STRING) AS `EntryDetail.Residency`,
        e.tmpADMAdviser AS `EntryCustomField.AdmissionAdvisor`,
        e.entrydetail_visadetails AS `EntryDetail.VisaDetails`,
        e.entrycustomfield_housingexemptionindicator AS `EntryCustomField.HousingExemptionIndicator`,
        e.entrycustomfield_ferpa AS `EntryCustomField.FERPA`,
        tp.t10_term AS `EntryCustomField.FallTerm`,
        tp.t10_camp AS `EntryCustomField.FallLocation`,
        tp.t10_pdate AS `EntryCustomField.FallHousingPaymentDate`,
        tp.t20_term AS `EntryCustomField.WinterTerm`,
        tp.t20_camp AS `EntryCustomField.WinterLocation`,
        tp.t20_pdate AS `EntryCustomField.WinterHousingPaymentDate`,
        tp.t30_term AS `EntryCustomField.SpringTerm`,
        tp.t30_camp AS `EntryCustomField.SpringLocation`,
        tp.t30_pdate AS `EntryCustomField.SpringHousingPaymentDate`,
        tp.t40_term AS `EntryCustomField.SummerTerm`,
        tp.t40_camp AS `EntryCustomField.SummerLocation`,
        tp.t40_pdate AS `EntryCustomField.SummerHousingPaymentDate`,
        e.spriden_pidm AS tmpPidm,
        CASE WHEN e.tmpPulledTerm < p.TermIn THEN p.TermIn ELSE e.tmpPulledTerm END AS tmpPulledTerm,
        COALESCE((SELECT stvterm_acyr_code FROM bronze_ellucian.saturn_stvterm WHERE stvterm_code = CASE WHEN e.tmpPulledTerm < p.TermIn THEN p.TermIn ELSE e.tmpPulledTerm END LIMIT 1), '0000') AS tmpTermACYR
    FROM enriched_students_with_advisor e
    LEFT JOIN term_pivoted tp ON tp.pidm = e.spriden_pidm
    CROSS JOIN params p
),
HEADER_ROWS AS (
    SELECT 1 AS REPORT_ORDER, 1 AS IS_HEADER, 
    'Entry.ID1|Entry.ID2|Entry.NameTitle|Entry.NameLast|Entry.NameFirst|Entry.NameOther|Entry.NamePreferred|Entry.Birth_GenderEnum|Entry.DOB|EntryDetail.Married|EntryDetail.Citizenship_CountryID.Abbreviation|EntryDetail.Ethnicity|Entry.DirectoryFlagPrivacy|EntryAddress[Alternate Email].Email|EntryAddress[Mailing].Email|EntryAddress[Mailing].Street|EntryAddress[Mailing].Street2|EntryAddress[Mailing].City|EntryAddress[Mailing].StateProvince|EntryAddress[Mailing].ZipPostcode|EntryAddress[Mailing].CountryID.Abbreviation|EntryAddress[Mailing].Phone|EntryAddress[Mailing].PhoneMobileCell|EntryAddress[Home].Email|EntryAddress[Home].Street|EntryAddress[Home].Street2|EntryAddress[Home].City|EntryAddress[Home].StateProvince|EntryAddress[Home].ZipPostcode|EntryAddress[Home].CountryID.Abbreviation|EntryAddress[Home].Phone|EntryAddress[Home].PhoneMobileCell|EntryAddress[Emergency].ContactName|EntryAddress[Emergency].Street|EntryAddress[Emergency].Street2|EntryAddress[Emergency].City|EntryAddress[Emergency].StateProvince|EntryAddress[Emergency].ZipPostcode|EntryAddress[Emergency].Phone|EntryAddress[Emergency].Relationship|EntryDetail.EnrollmentClass|EntryDetail.EnrollmentLevel|EntryDetail.EnrollmentStatus|EntryDetail.EnrollmentTerm|EntryDetail.AcademicHold|EntryDetail.IncidentHold|EntryDetail.AccountHold|EntryDetail.Athlete|EntryDetail.AthleteTeam|EntryDetail.CurrentMajor|EntryDetail.CurrentHours|EntryDetail.CumulativeHours|EntryDetail.CurrentGPA|EntryDetail.CumulativeGPA|EntryDetail.ExpectedGraduationDate|EntryDetail.Residency|EntryCustomField.AdmissionAdvisor|EntryDetail.VisaDetails|EntryCustomField.HousingExemptionIndicator|EntryCustomField.FERPA|EntryCustomField.FallTerm|EntryCustomField.FallLocation|EntryCustomField.FallHousingPaymentDate|EntryCustomField.WinterTerm|EntryCustomField.WinterLocation|EntryCustomField.WinterHousingPaymentDate|EntryCustomField.SpringTerm|EntryCustomField.SpringLocation|EntryCustomField.SpringHousingPaymentDate|EntryCustomField.SummerTerm|EntryCustomField.SummerLocation|EntryCustomField.SummerHousingPaymentDate' AS REPORT_TEXT
)
SELECT 
    tmpPidm, tmpTermACYR, tmpPulledTerm, grp_num,
    999 AS REPORT_ORDER, 
    0 AS IS_HEADER, 
    COALESCE(CAST(`Entry.ID1` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.ID2` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.NameTitle` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.NameLast` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.NameFirst` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.NameOther` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.NamePreferred` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.Birth_GenderEnum` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.DOB` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.Married` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.Citizenship_CountryID.Abbreviation` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.Ethnicity` AS STRING), '') || '|' || 
    COALESCE(CAST(`Entry.DirectoryFlagPrivacy` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Alternate Email].Email` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].Email` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].Street` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].Street2` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].City` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].StateProvince` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].ZipPostcode` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].CountryID.Abbreviation` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].Phone` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Mailing].PhoneMobileCell` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].Email` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].Street` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].Street2` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].City` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].StateProvince` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].ZipPostcode` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].CountryID.Abbreviation` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].Phone` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Home].PhoneMobileCell` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].ContactName` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].Street` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].Street2` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].City` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].StateProvince` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].ZipPostcode` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].Phone` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryAddress[Emergency].Relationship` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.EnrollmentClass` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.EnrollmentLevel` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.EnrollmentStatus` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.EnrollmentTerm` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.AcademicHold` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.IncidentHold` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.AccountHold` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.Athlete` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.AthleteTeam` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.CurrentMajor` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.CurrentHours` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.CumulativeHours` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.CurrentGPA` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.CumulativeGPA` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.ExpectedGraduationDate` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.Residency` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.AdmissionAdvisor` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryDetail.VisaDetails` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.HousingExemptionIndicator` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.FERPA` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.FallTerm` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.FallLocation` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.FallHousingPaymentDate` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.WinterTerm` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.WinterLocation` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.WinterHousingPaymentDate` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.SpringTerm` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.SpringLocation` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.SpringHousingPaymentDate` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.SummerTerm` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.SummerLocation` AS STRING), '') || '|' || 
    COALESCE(CAST(`EntryCustomField.SummerHousingPaymentDate` AS STRING), '') AS REPORT_TEXT
FROM QUERY_ROWS
UNION ALL
SELECT 
    NULL AS tmpPidm, NULL AS tmpTermACYR, NULL AS tmpPulledTerm, NULL AS grp_num,
    REPORT_ORDER, 
    IS_HEADER, 
    REPORT_TEXT
FROM HEADER_ROWS
ORDER BY REPORT_ORDER;
