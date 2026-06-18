/*******************************************************************************
Recreation of:
	Package: BANINST1.wpksrez
	Procedure: p_create_file_line (merge to table scadlocal.wsrsrez)
	
For data integrations report
*******************************************************************************/
MERGE INTO {catalog}.gold_integrations.starrez_demo_daily_control AS target
USING (
    SELECT
        tmpPidm,
        MAX(tmpTermACYR) as tmpTermACYR,
        MAX(tmpPulledTerm) as tmpPulledTerm
    FROM {catalog}.gold_integrations.starrez_demo_daily
    WHERE IS_HEADER = 0
    GROUP BY tmpPidm
) AS source
ON CAST(target.wsrsrez_pidm AS DECIMAL(8,0)) = source.tmpPidm
WHEN MATCHED THEN
  UPDATE SET
    target.wsrsrez_last_acyr = source.tmpTermACYR,
    target.wsrsrez_last_term = source.tmpPulledTerm,
    target.wsrsrez_last_sent = current_timestamp(),
    target.wsrsrez_status_ind = 'A',
    target.wsrsrez_activity_date = current_timestamp()
WHEN NOT MATCHED THEN
  INSERT (
    wsrsrez_pidm,
    wsrsrez_init_term,
    wsrsrez_last_acyr,
    wsrsrez_last_term,
    wsrsrez_last_sent,
    wsrsrez_status_ind,
    wsrsrez_activity_date
  )
  VALUES (
    source.tmpPidm,
    source.tmpPulledTerm,
    source.tmpTermACYR,
    source.tmpPulledTerm,
    current_timestamp(),
    'A',
    current_timestamp()
  );
