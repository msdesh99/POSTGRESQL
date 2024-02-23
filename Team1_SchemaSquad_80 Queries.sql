
--1.What % of the dataset had clinician reported records vs patient reported?

SELECT 
        report_source, 
        COUNT(patient_id) AS patient_count,
        ROUND(COUNT(patient_id)*100/ SUM(COUNT(patient_id)) OVER(),2) ||'%' AS patient_percentage
FROM 
        patient_details
GROUP BY 
        Report_source;

--2.Concatenate Patient ID and all symptoms as meaningful words into one string

SELECT 
        patient_id || ' - ' ||
        CASE 
        WHEN covid19_sympt_chills = 0 AND covid19_sympt_dry_cough = 0 AND covid19_sympt_fatigue = 0 
                AND covid19_sympt_fever = 0 AND covid19_sympt_loss_smell_taste = 0 AND covid19_sympt_nasal_congestion = 0 
                AND covid19_sympt_pain = 0 AND covid19_sympt_pneumonia = 0 AND covid19_sympt_shortness_breath = 0 
                AND covid19_sympt_sore_throat = 0
        THEN ' no symptoms'
        ELSE
        CONCAT(CASE WHEN covid19_sympt_chills = 1 THEN 'Chills, ' END,
        CASE WHEN covid19_sympt_dry_cough = 1 THEN 'Dry cough, ' END,
        CASE WHEN covid19_sympt_fatigue = 1 THEN 'Fatigue, ' END,
        CASE WHEN covid19_sympt_fever = 1 THEN 'Fever, ' END,
        CASE WHEN covid19_sympt_loss_smell_taste = 1 THEN 'Loss of smell and taste, ' END,
        CASE WHEN covid19_sympt_nasal_congestion = 1 THEN 'Nasal Congestion, ' END,
        CASE WHEN covid19_sympt_pain = 1 THEN 'Pain, ' END,
        CASE WHEN covid19_sympt_pneumonia = 1 THEN 'Pneumonia, ' END,
        CASE WHEN covid19_sympt_shortness_breath = 1 THEN 'Shortness of breath, ' END,
        CASE WHEN covid19_sympt_sore_throat = 1 THEN 'Sore throat,' END) 
        END as patient_symptoms 
FROM 
        covid_symptoms;

--3.What percentage of those in the ICU are smokers?

SELECT 
    SUM(CASE WHEN cd.covid19_icu_stay = 1 
    AND pd.smoker = 1 THEN 1 ELSE 0 END)*100/
    NULLIF(SUM(CASE WHEN cd.covid19_icu_stay = 1 THEN 1 ELSE 0 END),0)
        || '%' AS percentage_smoker_icu
FROM 
        patient_details pd
INNER JOIN 
        covid_details cd 
ON 
        pd.patient_id = cd.patient_id
WHERE 
        cd.covid19_icu_stay = 1;

--4.Create a crosstab with each type of MS as columns and covid diagnosed/not diagnosed as rows and show count of patients in each group.

SELECT 
    ms_type2,
    COUNT(pd.patient_id) AS totalpatients,
    SUM(CASE WHEN cd.covid19_confirmed_case = 1 THEN 1 ELSE 0 END) AS "Diagnosed",
    SUM(CASE WHEN cd.covid19_confirmed_case = 0 THEN 1 ELSE 0 END) AS  "Not Diagnosed"
FROM
    patient_details pd
LEFT JOIN
    covid_details cd
ON 
        pd.patient_id = cd.patient_id
GROUP BY 
        ms_type2;
		
--5.How many patients in the dataset are diagnosed with COVID and are on a ventilator?

--Solution 1:
SELECT
        COUNT(patient_id) AS patientscount_covid_ventilation
FROM
        covid_details
WHERE
        covid19_diagnosis = 'confirmed'
        AND covid19_ventilation =1;
        
-- Solution 2:
SELECT
        COUNT(patient_id) AS patientscount_covid_ventilation
FROM
        covid_details
WHERE
        covid19_confirmed_case = 1
        AND covid19_ventilation =1;

--6.Using windows functions show month of onset and the number of hospitalizations in the next month

--Description: COALESCE function replaces null value to 0 (last row of the result )
--Assumption: zero is displayed ,if no of records are found for the next month
--ex.2nd row: for 2020-01 there are no records available for 2020-02 so zero is displayed
SELECT 
        to_char(date_of_onset, 'YYYY-MM') AS onset_month,
        COALESCE (CASE WHEN 
        LEAD(concat(to_char(date_of_onset, 'YYYY-MM'),'-01'),1) 
        OVER()::date != concat(to_char(date_of_onset, 'YYYY-MM'),'-01')::date + interval '1 month'
    THEN 0 
    ELSE LEAD(COUNT(patient_id),1) OVER() END,0) as noOfHospitalizationInNextMonth
FROM 
        covid_details
WHERE 
        covid19_admission_hospital=1
GROUP BY 
        to_char(date_of_onset, 'YYYY-MM')
ORDER BY 
        to_char(date_of_onset, 'YYYY-MM');

--7.How many patients have covid and have reported symptoms of chills?

SELECT 
        COUNT(cs.patient_id) AS num_patients_with_covid_chills
FROM 
        covid_details cd
JOIN 
        covid_symptoms cs
ON 
        cs.patient_id = cd.patient_id
WHERE 
        cd.covid19_confirmed_case = 1
        AND cs.covid19_sympt_chills = 1;

--8.Add a column to the patient table which translates age_in_cat to the following values.
    --(0: age range <18, 1: age range 18-50,2: age range 51-70,3: age range >71)
	
-- create a procedure to add column and update the column
CREATE OR REPLACE PROCEDURE catAge_to_HumanAge()
AS
$$
BEGIN
        -- Add a new column to the table if it does not exists
        ALTER TABLE patient_details ADD COLUMN IF NOT EXISTS human_age varchar(20);
        
        -- Update the new column with the data
    UPDATE patient_details
    SET human_age = CASE
            WHEN age_in_cat=0 THEN '<18'
        WHEN age_in_cat=1 THEN '18-50'
        WHEN age_in_cat=2 THEN '51-70'
        WHEN age_in_cat=3 THEN '>71'
     END;
END;
$$
LANGUAGE plpgsql;

-- call the stored procedure
CALL catAge_to_HumanAge();

-- Select to see results
select * from patient_details;

--9.Do this within a stored procedure" How many patients who recovered had no comorbidities?

-- Function to return comorbidities value per patient
CREATE OR REPLACE FUNCTION public.get_comorbidities_sum(
        patientid text)
    RETURNS integer
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
   sum_comorbidities integer;
BEGIN
   SELECT SUM(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease + com_diabetes +
        com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy + com_neurological_neuromuscular) 
   INTO sum_comorbidities
   FROM comorbidities
   WHERE patient_ID = patientID;
   
   RETURN sum_comorbidities;
END;
$BODY$;

-- Solution Query 
WITH recovered_no_comorbidities
AS
(
SELECT 
        pd.patient_id,
        get_comorbidities_sum(pd.patient_id) AS comorbidities_sum
FROM 
        patient_details pd 
JOIN 
        covid_details cd
ON 
        pd.patient_id = cd.patient_id
WHERE 
        covid19_outcome_recovered = 1
)
SELECT 
        COUNT(patient_id) as patients_recovered_no_comorbidities 
        FROM recovered_no_comorbidities 
        WHERE comorbidities_sum = 0;

--10.What % of overweight patients have COVID?

WITH overweight_covid AS
 (
 SELECT 
         cd.covid19_confirmed_case,
        to_char((count(pd.patient_id) * 100.0 / sum(count(pd.patient_id)) OVER ()), 'FM90.0" %"') AS Percentage
 FROM
         patient_details pd
 JOIN  
         covid_details cd
 ON 
         pd.patient_id = cd.patient_id
 WHERE 
         pd.bmi_in_cat2 >= 25
GROUP BY 
        cd.covid19_confirmed_case 
)
SELECT
        percentage as percentage_overweight_covid
FROM 
        overweight_covid
WHERE
        covid19_confirmed_case = 1;

--11.What is the correlation between smoking and being on a ventilator?

SELECT 
        ROUND(CORR(pd.smoker, cd.covid19_ventilation):: numeric,3) AS Correlation
FROM 
        patient_details pd
JOIN
        covid_details cd 
ON 
        pd.patient_id=cd.patient_id;

--12.Display an array of personal markers:BMI, EDSS, MS Type for every patient. The result should look like this 

SELECT
        pd.patient_id,
        ARRAY[pd.ms_type2, pd.bmi_in_cat2, pm.edss_in_cat2 ]::text[] AS mstype_bmi_edss_marker
FROM 
        patient_details pd
JOIN 
        patient_msdetails pm 
ON 
        pd.patient_id = pm.patient_id;
		
--13.What is the Standard deviation, mean and variance from mean in EDSS levels for all patients.

SELECT 
        STDDEV(edss_in_cat2) AS Standard_dev,
        AVG(edss_in_cat2) as Mean,
        VARIANCE(edss_in_cat2) as Variance
FROM 
        patient_msdetails;
		
--14.Create a materialized view with patient details (for all those with covid) and 
  --assign a COVID severity score to each patient assigning 1 point each for these symptoms.
  --(cardiovascular_disease,chronic_kidney_disease,chronic_liver_disease,diabetes,hypertension,
  --immunodeficiency,lung_disease,malignancy,neurological_neuromuscular)

-- DROP MATERIALIZED VIEW IF EXISTS;
DROP MATERIALIZED VIEW view_covidSeverity;

-- Creation of Materialized View
CREATE MATERIALIZED VIEW view_covidSeverity
AS
SELECT cd.patient_id,pd.report_source category,pd.sex,pd.age_group,
        (SELECT SUM(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease + com_diabetes +
        com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy + com_neurological_neuromuscular) AS covid_severity
         FROM comorbidities como WHERE cd.patient_id = como.patient_id)
FROM covid_details cd JOIN comorbidities com
ON cd.patient_id = com.patient_id
JOIN patient_details pd
ON cd.patient_id = pd.patient_id
WHERE covid19_confirmed_case = 1
ORDER BY covid_severity DESC
WITH NO DATA;

-- Refresh the view to load the data
REFRESH MATERIALIZED VIEW view_covidSeverity;

-- Select to see the results
SELECT * FROM view_covidSeverity;

--15.What percentage of the dataset is male vs what percentage is female? Calculate without the Use of a subquery or CTE

-- Solution 1
SELECT
        ROUND((COUNT(CASE WHEN sex = 'male' THEN 1 END) * 100.0 / COUNT(*)),2) || '%' AS  percent_male,
        ROUND((COUNT(CASE WHEN sex = 'female' THEN 1 END) * 100.0 / COUNT(*)),2)  ||'%' AS percent_female
FROM 
        patient_details; 
		
-- Solution 2
SELECT
        sex, count(patient_id),
        to_char((count(patient_id) * 100.0 / sum(count(patient_id)) OVER ()), 'FM90.00" %"') AS Percentage
FROM
        patient_details
GROUP BY
        sex;
		
--16.Create a function that checks if the patientId entered is a smoker. It should return a true/false answer.

CREATE OR REPLACE FUNCTION patient_issmoker(patientID varchar) 
RETURNS boolean 
AS
$body$
BEGIN
    IF EXISTS( 
                SELECT patient_id
                FROM patient_details
                WHERE patient_id = patientID AND smoker = 1
        )THEN
                RETURN true;
        ELSE
                RETURN false;
        END IF;   
END;
$body$ LANGUAGE plpgsql;
   
--Verify to view the results --
SELECT  patient_issmoker('C_1091') AS smoker; -- returns true

SELECT  patient_issmoker('P_123') AS smoker; -- returns false

--verify the output ---
SELECT * FROM patient_details WHERE patient_id='C_1091';

SELECT * FROM patient_details WHERE patient_id='P_123';

--17.How many patients are prescribed drugs have names starting with 'd'

SELECT 
        COUNT(patient_id) as patientsCount
FROM 
        patient_msdetails
WHERE 
        prescribed_drug like 'd%';

--18.What is % of all covid patients in each covid19 outcome levels? Use a windows function without a subquery.

SELECT 
        covid19_outcome_levels_2, 
        COUNT(patient_id) as No_of_Patients, 
        to_char((count(patient_id) * 100.0 / sum(count(patient_id)) OVER ()), 'FM90.0" %"') AS Percentage
FROM   
        covid_details
GROUP BY
        covid19_outcome_levels_2
ORDER BY
        covid19_outcome_levels_2 DESC;

--19.Write the query to create an Index on table public.comorbidities by 
   --selecting a column. Show the index using a query and write a query drop the same index.
   
-- Query to verify before and after creating index
EXPLAIN ANALYZE
SELECT 
        pd.patient_id,pd.sex,co.com_hypertension
FROM
        Patient_details pd
JOIN
        comorbidities co
ON pd.patient_id = co.patient_id
WHERE
        sex= 'female' AND co.com_hypertension=1;
        
-- Create index query
CREATE INDEX index_hypertension
ON comorbidities (com_hypertension);

-- Check if index is created
SELECT
    indexname,
    indexdef
FROM
    pg_indexes
WHERE
    tablename = 'comorbidities';
        
-- Drop the index
DROP INDEX index_hypertension;

--20.What % of total symptoms is Fatigue?

-- 0 mean no symptom and 1 mean has symptom
SELECT 
        covid19_sympt_fatigue, 
CASE 
        WHEN covid19_sympt_fatigue=1 THEN 'Has Fatigue Symptom'
        WHEN covid19_sympt_fatigue=0 THEN 'No Fatigue Symptom'
END AS FatigueSymptom,
        COUNT(patient_id) as NoofPatients,
        to_char((count(patient_id) * 100.0 / sum(count(patient_id)) OVER ()), 'FM90.0" %"') AS Percentage
FROM   
        covid_symptoms
GROUP BY
        covid19_sympt_fatigue
ORDER BY
        covid19_sympt_fatigue DESC;

--21.List all patients that were admitted between 2020 January and 2020 March

-- Solution 1:
SELECT 
        * 
FROM 
        public.covid_details
WHERE 
        date_of_onset BETWEEN '2020-01-01' AND '2020-03-31'
        AND covid19_admission_hospital = 1
ORDER BY 
        patient_id;

-- Solution 2:
SELECT 
        * 
FROM 
        public.covid_details
WHERE 
        DATE_PART('MONTH', date_of_onset) IN (1,2,3) AND DATE_PART('YEAR', date_of_onset) = 2020
        AND covid19_admission_hospital = 1
ORDER BY 
        patient_id;

--22.On average, how many comorbidities do people with 'progressive_MS' have

SELECT 
        ROUND(AVG(comorbidities_SUM),2) AS Avg_comorbidities
FROM
        (SELECT patient_id,
         sum(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease + 
                 com_diabetes + com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy + 
                 com_neurological_neuromuscular) AS comorbidities_SUM
        FROM comorbidities 
        WHERE patient_id 
        IN (SELECT patient_id FROM patient_details WHERE ms_type2='progressive MS')
        GROUP BY patient_id)

--23.Create a view without using any schema or table and check the created view using a select statement.

-- Drop the view if it exists
DROP View IF EXISTS view_NoSchemaTable;

-- Create or replace view with the name "view_NoSchemaTable"
CREATE OR REPLACE VIEW view_NoSchemaTable AS SELECT 'View created without Schema or Table' AS Information;

-- Check the view using select statement 
SELECT * FROM view_NoSchemaTable;

--24.Create a crosstab with each type of MS as columns and the medications used as rows

SELECT *
FROM crosstab(
   'SELECT pd.patient_id,pd.ms_type2,pm.prescribed_drug
        FROM Patient_details pd
        JOIN patient_msdetails pm
        ON pd.patient_id = pm.patient_id
    ORDER  BY 1,2',
        'SELECT distinct ms_type2 from Patient_details order by 1'  
   )AS crosstab_mstype (PatientID text,other text, progressive_MS text, relapsing_remitting text);

--25.Get the patient's ID who has a max severity score from the materialized view created in Q14 using windows functions.

-- "view_covidSeverity" is the name of the view created from Q14
SELECT 
        patient_id,covid_severity
FROM 
        (SELECT patient_id,covid_severity,
    RANK() OVER (ORDER BY covid_severity DESC) AS rownum
          FROM view_covidSeverity) 
WHERE 
        rownum = 1;

--26.Rank the types of MS, by the sum of all comorbidities associated with each one.

-- Considering the highest number as Rank 1 here
-- Solution 1 
WITH MS_comorbidities AS
(
SELECT 
        pd.ms_type2,
    (SELECT sum(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease + 
        com_diabetes + com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy + 
        com_neurological_neuromuscular) AS comorbidities_SUM
    FROM comorbidities como 
        WHERE pd.patient_id = como.patient_id)
FROM 
        patient_details pd 
JOIN 
        comorbidities como
ON 
        pd.patient_id = como.patient_id
)
SELECT 
        ms_type2,SUM(comorbidities_SUM) as comorbiditiesSUM,
        RANK () OVER (ORDER BY SUM(comorbidities_SUM) DESC) comorbidities_rank
FROM 
        MS_comorbidities
GROUP BY 
        ms_type2;

-- Solution 2:
SELECT 
        pd.ms_type2,
        sum(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease + 
        com_diabetes + com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy + 
        com_neurological_neuromuscular) AS comorbidities_SUM,
    RANK () OVER (ORDER BY sum(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease + 
                com_diabetes + com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy + 
                com_neurological_neuromuscular) DESC) comorbidities_rank
FROM 
        patient_details pd 
JOIN 
        comorbidities como
ON 
        pd.patient_id = como.patient_id
GROUP BY 
        pd.ms_type2;

--27.What % of patients in the ICU needed ventilation. Calculate and without a subquery or CTE.

SELECT 
        covid19_ventilation,
        CASE
                WHEN covid19_ventilation = 0 THEN 'Ventilation Not Required'
                WHEN covid19_ventilation = 1 THEN 'Ventilation Required'
        END,
        count(patient_id) AS No_of_Patients,
        to_char((count(patient_id) * 100.0 / sum(count(patient_id)) OVER ()), 'FM90.0" %"') AS Percentage
FROM 
        covid_details
WHERE 
        covid19_icu_stay = 1
GROUP BY 
        covid19_ventilation;

--28.Using mean and std_dev create your own 10 Patient_ids and EDSS values that have the same std_dev as the original table

--29.calculate the frequency of EDSS and cumulative frequency of EDSS of the patients in the dataset

SELECT 
    edss_in_cat2 AS EDSS_Value, 
    COUNT(patient_id) AS EDSS_Frequency,
    SUM(COUNT(patient_id)) OVER (ORDER BY edss_in_cat2) AS EDSS_Cumulative
FROM 
        patient_msdetails
GROUP BY 
        edss_in_cat2
ORDER BY 
        edss_in_cat2;

--30.How many people who have covid are overweight vs those who are not overweight?

--Considering the universal bmi range and have taken value 25

SELECT 
        CASE 
        WHEN pd.bmi_in_cat2 >= 25 THEN 'Overweight'
        WHEN pd.bmi_in_cat2 < 25 THEN 'Not Overweight'
        END AS BMICategory,
        COUNT(pd.bmi_in_cat2) as patientCount
FROM 
        patient_details pd 
JOIN 
        covid_details cd
ON 
        pd.patient_id = cd.patient_id
WHERE 
        covid19_diagnosis = 'confirmed'
GROUP BY 
        BMICategory;

--31.What percentage of each MStype are smokers?

SELECT 
        ms_type2 AS MSType,
        count(patient_id) as PatientCount,
        to_char((count(patient_id) * 100.0 / sum(count(patient_id)) OVER ()), 'FM90.0" %"') AS Percentage
FROM 
        patient_details
WHERE 
        smoker = 1
GROUP BY 
        ms_type2;

--32.Divide avg BMI by avg EDSS  and return number of decimals in the result

SELECT 
    (SELECT AVG(bmi_in_cat2) AS Avg_bmi FROM patient_details) / 
    (SELECT AVG(edss_in_cat2)  AS Avg_edss FROM patient_msdetails) AS Avg_BMI_EDSS,
     SCALE((SELECT AVG(bmi_in_cat2) AS Avg_bmi FROM patient_details) / 
     (SELECT AVG(edss_in_cat2)  AS Avg_edss FROM patient_msdetails)) AS No_of_digits;

--33.List all Patients who are in the youngest age group and did not recover from COVID

--Assumption: not recovered=0, recovered=1
SELECT 
        patient_id 
FROM 
        patient_details
JOIN 
        covid_details covid USING (patient_id)
WHERE 
        covid19_outcome_recovered=0 AND age_in_cat =1
ORDER BY 
        patient_id;

--34.Extract the week from the Date Of Onset and show the distribution of week numbers using width bucket function.

-- Description: Created temporary table ‘weeks’ to calculate ‘maxNoOfWeeks’ :
-- To Avoid hard coding 
-- To Avoid running subquery in the main query for two times to calculate max no of weeks. 
WITH weeks AS (
    SELECT MAX(DATE_PART('week', date_of_onset))::int maxNoOfWeeks
    FROM covid_details
)  --created maxNoOfWeeks
SELECT 
        WIDTH_BUCKET(DATE_PART('week', date_of_onset), 1,
                 (SELECT maxNoOfWeeks FROM weeks),
                 (SELECT maxNoOfWeeks FROM weeks)) AS week_bucket,
    COUNT(patient_id) AS No_of_Patients  
FROM 
    covid_details
GROUP BY 
    week_bucket
ORDER BY 
    week_bucket;
	
--35.How many patients were admitted in the current month of any month

-- Solution 1:
-- Create a function with month_onset as input parameter
CREATE OR REPLACE FUNCTION getPatientCountBasedonMonth(
        month_onset int
)
-- returns patient count
RETURNS int
AS $$
DECLARE
        No_of_Patients int;
BEGIN
    SELECT COUNT(*) INTO No_of_Patients FROM covid_details WHERE 
                        covid19_admission_hospital =1 AND EXTRACT('month' from date_of_onset) = month_onset;
        
        RETURN No_of_Patients;
END;
$$ LANGUAGE plpgsql;

-- execute the select statements to view the results.
SELECT getPatientCountBasedonMonth(1);

SELECT getPatientCountBasedonMonth(EXTRACT('month' FROM CURRENT_DATE)::int);

-- Solution 2:
-- Create a procedure with month_onset as input parameter
CREATE OR REPLACE PROCEDURE pr_get_noOFpaitent_admitted_in_month(monthNo integer)
LANGUAGE plpgsql as 
$$
DECLARE
BEGIN
        DROP TABLE IF EXISTS MONTH_TEMP;
        CREATE TABLE month_temp AS         
                SELECT TO_CHAR(date_of_onset, 'Month') as month
              ,count(*) as Patient_Admitted
                FROM covid_details
                WHERE covid19_admission_hospital =1
                 AND extract('month' from date_of_onset) = monthNo::integer
                GROUP BY TO_CHAR(date_of_onset, 'Month');
    IF EXISTS (SELECT *  FROM MONTH_TEMP) THEN
         RAISE NOTICE using message ='PATIENTS GOT ADMITTED IN THIS MONTH
                 '||chr(10)||'PLEASE CHECK MONTH_TEMP TABLE, USE'||CHR(10)||
                 'SELECT * FROM MONTH_TEMP';
        ELSE
         RAISE NOTICE 'No PATIENTS ADMITTED IN THIS MONTH';
    END IF;

EXCEPTION
        WHEN OTHERS THEN 
                RAISE NOTICE 'An error occured: %', SQLERRM;
END; $$

-- execute to see results of currect month of any month
CALL pr_get_noOFpaitent_admitted_in_month(EXTRACT('month' FROM CURRENT_DATE)::int);

-- execute to see result
CALL pr_get_noOFpaitent_admitted_in_month(9); ---not found msg will get displayed

CALL pr_get_noOFpaitent_admitted_in_month(1);

SELECT * FROM month_temp;

--36.Which drug was most used for severe MS. Your answer should consider both frequency and duration of usage of drugs.

--Assumption:severeMS = ‘progressive MS’
SELECT 
        drug AS drug_most_used_for_severe_MS 
FROM (SELECT prescribed_drug,
            Row_number() OVER (ORDER BY 
             COUNT(prescribed_drug),MAX(duration_treatment_cat2)DESC) AS rowNo
                FROM patient_details 
                JOIN patient_msdetails USING (patient_id)
                WHERE ms_type2= 'progressive MS'
                GROUP BY prescribed_drug ,duration_treatment_cat2
                ORDER BY COUNT(prescribed_drug),duration_treatment_cat2 DESC 
) AS DATA(drug,rowNo)
WHERE rowNo=1;


--37.How many different types of medication are there in the dataset? Display count of patients against each one.

SELECT 
        prescribed_drug,
    COUNT(patient_id) AS Count_Of_Patients 
FROM 
        patient_msdetails
GROUP BY 
        prescribed_drug
ORDER BY 
        COUNT(patient_id) DESC;
		
--38.Using windows functions show month of onset and the number of hospitalizations in the previous month

--Description: COALESCE function replaces null value to 0 (1st row of the result )
--Assumption: zero is displayed ,if no of records are not found in the previous month
--ex.3rd row: for 2020-03 there are no records available for 2020-02 so zero is displayed
SELECT 
        to_char(date_of_onset, 'YYYY-MM') AS onset_month,
        COALESCE (CASE WHEN 
        LAG(concat(to_char(date_of_onset, 'YYYY-MM'),'-01'),1) 
        OVER()::date != concat(to_char(date_of_onset, 'YYYY-MM'),'-01')::date - interval '1 month'
    THEN 0 
    ELSE 
                LAG(COUNT(patient_id),1) OVER() END,0) AS Hospitalization_PreviousMonth
FROM 
        covid_details
WHERE 
        covid19_admission_hospital=1
GROUP BY 
        to_char(date_of_onset, 'YYYY-MM')
ORDER BY 
        to_char(date_of_onset, 'YYYY-MM');

--39.List all patients that were admitted during the busiest month in this dataset

-- Solution 1:
-- ASSUMPTION: busiest month = The month having maximum records in the covid_details table. 
SELECT 
        patient_id,to_char(date_of_onset, 'MM') as busiest_month
FROM 
        covid_details
WHERE 
        covid19_admission_hospital = 1
        AND to_char(date_of_onset, 'MM') IN ( 
                   SELECT busiest_month.mon FROM  (
                SELECT COUNT(patient_id) AS cnt,
                to_char(date_of_onset, 'MM') as mon,
                RANK() OVER(ORDER BY COUNT(patient_id) DESC) AS rnk
FROM covid_details
GROUP BY to_char(date_of_onset, 'MM')
ORDER BY rnk) busiest_month
        WHERE rnk =1);
        
-- Solution 2:
-- ASSUMPTION: busiest month = The month and year having maximum records 
--in the covid_details table. '2020-05' having maximum records (47) of the dataset. 
SELECT 
        patient_id 
FROM 
        covid_details
WHERE 
        covid19_admission_hospital= 1
        AND to_char(date_of_onset, 'YYYY-MM') IN 
                (SELECT busiest_month.monthYear FROM (
                SELECT COUNT(patient_id) AS cnt,
                    to_char(date_of_onset, 'YYYY-MM') as monthYear,
                    RANK() OVER(ORDER BY COUNT(patient_id) DESC) AS rnk
                                FROM covid_details
                                GROUP BY to_char(date_of_onset, 'YYYY-MM')
                                ORDER BY rnk) busiest_month
         WHERE rnk =1);

--40.Create a function to calculate the total number of people who recovered for every drug entered.

-- Solution 1: Without cursor
CREATE OR REPLACE FUNCTION fn_patientsRecoveredByDrug(drug text)
RETURNS TABLE(no_Of_Patient_Recoverd bigint)
AS $$
BEGIN
RETURN QUERY
SELECT COUNT(c.patient_id) as no_Of_Patient_Recovered
                FROM covid_details c
                RIGHT JOIN patient_msdetails m using(patient_id)        
                WHERE covid19_outcome_recovered=1
                AND prescribed_drug = drug
                GROUP BY prescribed_drug;
        EXCEPTION
        WHEN OTHERS THEN 
                RAISE NOTICE 'An error occured: %', SQLERRM;
END        
$$ LANGUAGE plpgsql;

--TO EXECUTE FUNCTION
SELECT fn_patientsRecoveredByDrug('glatiramer');

-- Solution 2: With cursor
CREATE OR REPLACE FUNCTION fn_patient_recovered(drug text, patient_cursor refcursor) 
RETURNS refcursor
AS $$
BEGIN
    RAISE NOTICE USING MESSAGE =
        'LOOKING FOR THE PATIENTS RECOVERED USING THIS DRUG '||
        drug;        
        OPEN patient_cursor FOR 
                SELECT COUNT(c.patient_id) as no_Of_Patient_Recovered 
                FROM covid_details c
                RIGHT JOIN patient_msdetails m using(patient_id)        
                WHERE covid19_outcome_recovered=1
                AND prescribed_drug = drug
                GROUP BY prescribed_drug;
RETURN patient_cursor;
END;
$$ LANGUAGE plpgsql;

---TO EXECUTE FUNCTION PLEASE RUN EACH STEP SEPERATELY.

BEGIN
SELECT fn_patient_recovered('latiramer','pcursor');
FETCH ALL FROM pcursor;
END;

BEGIN
SELECT fn_patient_recovered('dimethyl fumarate','pcursor');
FETCH ALL IN pcursor;
END;


--41.How many patients have drug names with length >7 letters?

SELECT 
        SUM(COUNT(patient_id)) OVER() AS Patients_drugname_length_gt7 
FROM 
    patient_msdetails
WHERE 
    LENGTH(prescribed_drug)>7;

--42.Show the moving average of patients every 3 months.

-- considering the months available in the dataset only.
-- (skipped month-year those are not present in the dataset) 

SELECT 
    move_avg.monYr AS YYYY_MM,move_avg.patients AS patient_count, 
    round(AVG(move_avg.patients) OVER 
    (ORDER BY move_avg.monYr ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),2) 
           AS moving_avg_Of_patients_every3months
FROM 
(                
SELECT 
    COUNT(patient_id) AS patients, 
    to_char(date_of_onset, 'YYYY-MM') AS monYr 
FROM 
    covid_details
GROUP BY 
    monYr
ORDER BY 
    monYr
) move_avg;

--43.What % of those who self isolated showed symptoms vs everyone else?

SELECT 
    MAX(CASE WHEN isolated.iso=1 THEN isolated.percentage 
        ELSE null END) AS percentageof_isolated_having_symptoms,
    MIN(CASE WHEN isolated.iso = 0 THEN isolated.percentage END) AS percentageof_nonisolated_having_symptoms
FROM 
(
        SELECT 
                covid19_self_isolation AS iso,covid19_has_symptoms AS symp,
            COUNT(patient_id) as total,
                to_char((count(patient_id) * 100.0 / SUM(COUNT(patient_id)) OVER (PARTITION BY covid19_self_isolation)),
                        'FM90.0" %"') AS Percentage
    FROM covid_details
    GROUP BY covid19_self_isolation,covid19_has_symptoms
    ORDER BY covid19_has_symptoms DESC
)isolated
WHERE 
        isolated.symp=1; 

--44.Create a trigger to stop patient records from being deleted from the patient details table

--Function
CREATE OR REPLACE FUNCTION stop_delete_patient_detail_tbl()
RETURNS TRIGGER AS $$
DECLARE
BEGIN
RAISE NOTICE 'TG_OP IS %', TG_OP;
IF TG_OP='DELETE' THEN
    IF EXISTS (SELECT *  FROM patient_details WHERE patient_id = OLD.patient_id) THEN
            RAISE EXCEPTION 'Record cannot be deleted';
    END IF;
        RETURN OLD;
else
        RAISE EXCEPTION 'Trigger encountered unknown TG_OP ';
        RETURN OLD;
END IF;
END;
$$ LANGUAGE plpgsql;

---created trigger
CREATE OR REPLACE TRIGGER stop_delete_trigger
BEFORE DELETE ON patient_details
FOR EACH ROW
EXECUTE FUNCTION stop_delete_patient_detail_tbl();

---try to delete record from 'covid_detail_temp_tbl'
DELETE FROM patient_details 
WHERE PATIENT_ID = 'C_1005';

-- Rollback the transaction for running next query
COMMIT;

--45.Which age-group has the highest count of patients?

-- run commit to rollback the delete trigger transaction before running the next query

SELECT high_agegroup.age_group 
FROM 
        (SELECT 
                  COUNT(patient_id) AS cnt,
        age_group,Row_number() OVER (ORDER BY count(patient_id)DESC) AS rowNo
      FROM patient_details
      GROUP BY age_group) high_agegroup
WHERE 
        high_agegroup.rowNo=1;

--46.Extract only the word fumarate from dimethyl fumarate and show it against the average number of years of treatment

SELECT 
        substr(prescribed_drug,POSITION('fumarate' IN prescribed_drug),LENGTH(prescribed_drug)) AS  drug,
    AVG(duration_treatment_cat2)::numeric(10,5) AS avg_years_of_treatment
FROM 
        patient_msdetails
WHERE 
        prescribed_drug = 'dimethyl fumarate'
GROUP BY 
        prescribed_drug;

--47.Write a query to display all drugs prescribed with Case-Insensitive Replacement of 'Unlisted' to 'Not Found'

SELECT DISTINCT(
        (CASE WHEN prescribed_drug ilike '%unlisted%' 
          THEN 'Not Found' ELSE prescribed_drug END)
        ) AS prescribed_drug 
FROM 
        patient_msdetails
ORDER BY 
        prescribed_drug;

--48.Create a table with patientID, BMI and Covid Status using a stored procedure. Add an auto generated sequence as the first column

-- stored procedure to create a table
CREATE OR REPLACE PROCEDURE proc_covid()
LANGUAGE plpgsql
AS $$
BEGIN
CREATE TABLE status_covid(
        S_id SERIAL PRIMARY KEY,
        PatientID INT, 
        BMI INT ,
        CovidStatus TEXT
);
RAISE NOTICE 'Table Created and Auto Generated Series is added to S_Id';
END;
$$;

-- call the stored procedure
CALL proc_covid();

-- select query to verify it
SELECT * FROM status_covid;


--49.List patients where the MS Type ‘ssi’ along with the position where ‘ssi’ appears.

SELECT 
        patient_id, POSITION('ssi' IN ms_type2) AS position_ssi
FROM 
        patient_details
WHERE 
        ms_type2 LIKE '%ssi%';

--50.Create a child table for the table in Q48  which inherits all the values of the patient table and contains covid symptoms.
--ensure that at least 1 row is inserted into the final table

-- solution to create a child table and insert records
DO $$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'covstatchild') THEN
                RAISE NOTICE 'Table already exists , so deleting and creating the new table.';        
                DROP TABLE covstatchild;        
                CREATE TABLE covstatchild (
                                CovidSymptoms INT
                                ) INHERITS (status_covid);
 
                INSERT INTO covstatchild (PatientID, BMI, CovidStatus, CovidSymptoms) 
                        VALUES (6, 12, 'Positive', 1), (8, 19, 'Negative', 0);
ELSE
                   RAISE NOTICE 'No table found, creating new table';
                CREATE TABLE covstatchild (
                                CovidSymptoms INT
                                ) INHERITS (status_covid);
                INSERT INTO covstatchild (PatientID, BMI, CovidStatus, CovidSymptoms) 
                        VALUES (10, 11, 'Positive', 1), (9, 21, 'Negative', 0);
END IF;
END;
$$;

-- select to view results
SELECT * FROM covstatchild;


--51.List out any 5 patients, add '0' to their first part of the ID so that total characters displayed is 10

WITH PatientsList AS(
SELECT LPAD(patient_id,10,'0') as Patients FROM patient_details
)
SELECT Patients, Length(Patients) as Length_PID FROM PatientsList
ORDER BY RANDOM() LIMIT 5

--52.Write a trigger after inserting it on the Patient Details table. if the BMI >40, warn for high risk of covid symptoms

-- create a function to return a trigger
CREATE OR REPLACE FUNCTION Pat_Det_trigger_fnc()
RETURNS TRIGGER AS
$$
BEGIN
  IF NEW.bmi_in_cat2 > 40 THEN
       RAISE NOTICE 'Patient is in high risk of covid symptoms, Inserting data with %bmi_in_cat2', NEW.bmi_in_cat2;
    END IF;
RETURN NEW;
END;
$$
LANGUAGE 'plpgsql';

-- create a trigger when a row is inserted
CREATE TRIGGER Pat_Det_Aft_Trigger
AFTER INSERT
ON patient_details
FOR EACH ROW
EXECUTE PROCEDURE Pat_Det_trigger_fnc();

-- insert data to verify the results.
INSERT INTO  patient_details Values('P_2896', 'patient', 0, 48, 'female', 'other', 0, 0, '18-50');

INSERT INTO  patient_details Values('P_1917', 'patient', 1, 36, 'male', 'other', 0, 0, '18-50');

--53.Show the MS type of any patient in reverse

-- function to reverse ms_type. Input is patient ID
CREATE OR REPLACE FUNCTION rev_patient (patid text)
RETURNS TABLE (mstype2 text)
LANGUAGE  plpgsql
AS $$
BEGIN
RETURN QUERY(
        SELECT REVERSE(ms_type2) FROM patient_details
        WHERE patient_id = patid
);
END;
$$;

-- select statement to verify the results
SELECT * FROM rev_patient('P_1010');

SELECT * FROM rev_patient('P_123');

--54.Create a pie chart to show the distribution of at least 5 symptoms across patients.

SELECT COUNT(patient_id), Five_Symptoms FROM
(
SELECT patient_id,
  CASE
        WHEN covid19_sympt_pneumonia = 1 THEN 'Pnemonia'
        WHEN covid19_sympt_dry_cough = 1 THEN 'Dry_Cough'
        WHEN covid19_sympt_sore_throat = 1 THEN 'Sore Throat'
        WHEN covid19_sympt_loss_smell_taste = 1 THEN 'Loss_Smell_Taste'
    WHEN covid19_sympt_shortness_breath = 1 THEN 'Shortness of Breath'
        ELSE  'Null'
  END AS Five_Symptoms FROM covid_symptoms
)
GROUP BY 
        Five_Symptoms
HAVING 
        Five_Symptoms <> 'Null';

--55.How many patients complained of pain as one of the symptoms of COVID.

SELECT 
        COUNT(patient_id) AS Total_Patients 
FROM 
        covid_symptoms
WHERE 
        covid19_sympt_pain = 1;

--56.create a view that stores MS Type and any 4 comorbidities

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = 'MStype_Com') THEN
        -- Create the view here
                CREATE OR REPLACE VIEW MStype_Com AS
                SELECT ms_type2, com_lung_disease, com_hypertension, com_malignancy,com_diabetes FROM patient_details PD
                INNER JOIN comorbidities CO
                ON PD.patient_id = CO.patient_id;
                RAISE NOTICE 'View created';
                
                ELSE
        RAISE NOTICE 'View already exists. Deleting';
                DROP VIEW MStype_Com;
                CREATE OR REPLACE VIEW MStype_Comorbidities AS
                SELECT ms_type2, com_lung_disease, com_hypertension, com_malignancy,com_diabetes from patient_details PD
                INNER JOIN comorbidities CO
                ON PD.patient_id = CO.patient_id;
                RAISE NOTICE 'View created';
   END IF;
END $$;

-- Select to see results
SELECT * FROM MStype_Com;

--57.How many pregnant women are in the ICU?

SELECT 
        COUNT(PD.patient_id) as No_of_Patients 
FROM 
        patient_details PD
JOIN 
        covid_details CD
ON 
        CD.patient_id = PD.patient_id
WHERE 
        pregnancy = 1 AND covid19_icu_stay = 1;

--58.Display the Day and Year Of onset in 2 separate columns for the patient who were on no Drugs

SELECT 
        PM.patient_id, pm.prescribed_drug,
        EXTRACT(DAY FROM date_of_onset) AS Day, 
        EXTRACT(Year FROM date_of_onset) AS Year 
FROM 
        covid_details CD
INNER JOIN 
        patient_msdetails PM 
ON 
        PM.patient_id=CD.patient_id
WHERE 
        prescribed_drug = 'no dmt';
		
--59.What % of the dataset has been confirmed with a diagnosis of covid

SELECT 
        to_char((Conf_Count * 100.0 / Total_count), 'FM90.00" %"') AS Conf_percent
FROM
        (SELECT COUNT(covid19_diagnosis) Conf_Count FROM covid_details WHERE covid19_diagnosis ='confirmed'), 
    (SELECT COUNT(*) Total_count FROM covid_details); 


--60.Using Windows functions. Divide patients by MS type,  
   --partition MS_type by no. of symptoms into 2 buckets each, label them as high and low risk. Display avg symptoms in each bucket

WITH MStype_symptoms AS
        (SELECT patient_id, 
         SUM(covid19_sympt_fatigue + covid19_sympt_fever + covid19_sympt_pain + covid19_sympt_sore_throat +
         covid19_sympt_chills + covid19_sympt_dry_cough + covid19_sympt_loss_smell_taste +
         covid19_sympt_nasal_congestion + covid19_sympt_pneumonia + covid19_sympt_shortness_breath
         ) AS Total_symp FROM covid_symptoms
    GROUP BY  patient_id
),
GroupBucket AS (
        SELECT patient_id,
        CASE
        WHEN Total_symp BETWEEN 0 AND 5 THEN 'Low Risk'
        WHEN Total_symp BETWEEN 6 AND 10 THEN 'High Risk'
END AS Bucket_Category FROM MStype_symptoms MS 
GROUP BY patient_id, Total_symp
)
SELECT 
        ms_type2, COUNT(MS.patient_id) AS Patient_count, Total_symp, Bucket_Category, 
        ROUND(AVG(Total_symp) OVER(partition by Bucket_Category),2) AS Avg_symp
FROM MStype_symptoms MS
JOIN GroupBucket B
ON MS.patient_id = B.patient_id
JOIN patient_details PD
ON MS.patient_id = PD.patient_id
GROUP BY ms_type2, Total_symp, Bucket_Category
ORDER BY Total_symp;

--61.Using the ANY function, what is the maximum treatment duration observed among all patients?

SELECT 
        MAX(duration_treatment_cat2) AS Treatment_duration 
FROM 
        patient_msdetails
WHERE 
        patient_id = ANY(SELECT patient_id FROM patient_details);

--62.Use Case statements to add meaning to the EDSS Score and show number of patients and covid diagnosis per group

SELECT
        CASE
                WHEN edss_in_cat2 ='0' THEN 'Normal Neuro Examination'
                WHEN edss_in_cat2 >'0' AND edss_in_cat2 <='5' THEN 'Fully ambulatory patients'
                WHEN edss_in_cat2 ='10' THEN 'MS-related death cases'
                ELSE ' With Assistance'
        END AS EDSS_Score, 
        COUNT(cd.patient_id) AS Patient_Count,
        COUNT(cd.covid19_diagnosis) AS Covid_diagnosis_Count 
FROM 
        patient_msdetails p
JOIN 
        covid_details cd 
ON cd.patient_id = p.patient_id
GROUP BY 
        cd.covid19_diagnosis, EDSS_Score
ORDER BY 
        EDSS_Score;

--63.Find the average treatment duration for patients and round up to the nearest integer value.

SELECT 
        ROUND(AVG(duration_treatment_cat2)) AS Total_Treatment_duration 
FROM 
        patient_msdetails;

--64.Select the top 5 tables in the COVID database by size

SELECT 
        table_name as CovidDB_TableNames,pg_relation_size(table_schema || '.' || table_name) as CovidDB_Size
FROM 
        information_schema.tables
WHERE 
        table_schema NOT IN ('information_schema', 'pg_catalog')
ORDER BY 
        CovidDB_Size DESC
LIMIT 5;

--65.Divide EDSS by treatment duration for any 5 patients without using mathematical operators like '/'

-- The DIV() function accepts any positive values, negative values, 
-- fractional/floating point values, etc. as arguments and retrieves an integer value 
SELECT 
        patient_ID,edss_in_cat2 AS EDSS,
    duration_treatment_cat2 AS treatment_duration,
    DIV(edss_in_cat2,duration_treatment_cat2) AS div_EDSS_TreatmentDuration
FROM 
        patient_msdetails
ORDER BY 
        RANDOM()
LIMIT 5;

--66.Create a trigger on a view from q56.
--Q66-Create a trigger on a view of from q56.
--q56--create a view that stores MS Type and any 4 comorbidities
--To instead of writing it in view: 
--create a log table of the view.
--create function to insert record into the log table
--create trigger to write a record into log table 
--instead of inserting  or deleting a row into view

--Try to INSERT RECORD in the view MStype_Com;
INSERT INTO MStype_Com VALUES('insert',1,1,1,1) --ERROR OCCURED

CREATE TABLE MStype_Com_log 
AS SELECT * FROM MStype_Com ;

CREATE OR REPLACE FUNCTION insert_mstype()
RETURNS TRIGGER AS $$ 
BEGIN
RAISE NOTICE 'TG_OP IS %', TG_OP;
IF(TG_OP = 'INSERT') THEN
        INSERT INTO MStype_Com_log VALUES(NEW.*);
        RETURN NEW;
 END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
--TRIGGER
CREATE OR REPLACE TRIGGER after_insert_mstype
INSTEAD OF INSERT ON MStype_Com
FOR EACH ROW EXECUTE FUNCTION insert_mstype();

SELECT * FROM MStype_Com_log;  --1141 RECORDS

INSERT INTO MStype_Com VALUES('InsertedbyView',1,1,1,1)


SELECT * FROM MStype_Com_log where ms_type2='InsertedbyView'

SELECT * FROM MStype_Com_log; --- ADDES NEW RECORD
SELECT * FROM MStype_Com --- NO CHANGE
SELECT  * FROM patient_details -- NO CHANGE
SELECT * FROM comorbidities -- No CHANGE


--67.Divide EDSS by treatment duration for any 5 patients without using mathematical operators like '/' and return any remainder

-- MOD() function returns only the remainder after division
SELECT 
        patient_ID,edss_in_cat2 AS EDSS,
    duration_treatment_cat2 AS treatment_duration,
    MOD(edss_in_cat2,duration_treatment_cat2) AS remainder_EDSS_TreatmentDuration
FROM 
        patient_msdetails
ORDER BY 
        RANDOM()
LIMIT 5;

--68.Provide the cumulative distribution for MS type based on average being BMI below or above 30. 

--69.What is the total number of years between the earliest record and the latest

SELECT
    EXTRACT(YEAR FROM MAX(date_of_onset)) - EXTRACT(YEAR FROM MIN(date_of_onset)) AS total_years
FROM
    covid_details;
	
--70.What % of those on glucocorticoids have symptoms and what is the most common symptom among this population?

--Functions: ARRAY, LATERAL
SELECT e.percsympt as percentage_on_glucocorticoids_have_symptoms,
d.row AS most_common_symptom  FROM (
         SELECT SUM(sympArr.elem), sympArr.rowNo 
    ,CASE 
     WHEN to_char((MAX(SUM(sympArr.elem)) OVER()),'FM90')::integer = SUM(sympArr.elem)
         AND sympArr.rowNo  = 1 THEN 'covid19_sympt_chills' 
         WHEN to_char((MAX(SUM(sympArr.elem)) OVER()),'FM90')::integer = SUM(sympArr.elem)
         AND sympArr.rowNo  = 2 THEN 'covid19_sympt_fatigue' 
         WHEN to_char((MAX(SUM(sympArr.elem)) OVER()),'FM90')::integer = SUM(sympArr.elem)
         AND sympArr.rowNo  = 3 THEN 'covid19_sympt_dry_cough' 
         WHEN to_char((MAX(SUM(sympArr.elem)) OVER()),'FM90')::integer = SUM(sympArr.elem)
         AND sympArr.rowNo  = 4 THEN 'covid19_sympt_fever' 
         WHEN to_char((MAX(SUM(sympArr.elem)) OVER()),'FM90')::integer = SUM(sympArr.elem)
         AND sympArr.rowNo  = 5 THEN 'covid19_sympt_loss_smell_taste' 
         WHEN to_char((MAX(SUM(sympArr.elem)) OVER()),'FM90')::integer = SUM(sympArr.elem)
         AND sympArr.rowNo  = 6 THEN 'covid19_sympt_pain' 
         WHEN to_char((MAX(SUM(sympArr.elem)) OVER()),'FM90')::integer = SUM(sympArr.elem)
         AND sympArr.rowNo = 7 THEN 'covid19_sympt_pneumonia' 
         ELSE 'null' END  AS ROW 
          FROM
--         select s.patient_id,a.arr from (
           COVID_DETAILS c 
           JOIN PATIENT_MSDETAILS USING (PATIENT_ID)
           JOIN COVID_SYMPTOMS S  USING (PATIENT_ID) --)
          ,LATERAL (SELECT ARRAY[
                                covid19_sympt_chills,covid19_sympt_fatigue,
                                                   covid19_sympt_dry_cough,covid19_sympt_fever,
                                       covid19_sympt_loss_smell_taste,covid19_sympt_pain,
                                                   covid19_sympt_pneumonia] AS arr) a
                          , UNNEST(a.arr) WITH ORDINALITY sympArr(elem,rowNo)
                        WHERE DMT_GLUCOCORTICOID =1        
        AND 1 = ANY(arr)
         GROUP BY rowNo 
    ORDER BY rowNo 
)d
, (SELECT COUNT(s.patient_id),covid19_has_symptoms
              ,to_char((COUNT(patient_id)*100.0/SUM(COUNT(patient_id))
                    OVER ()), 'FM90.00"%"')AS percsympt
          FROM
           COVID_DETAILS c 
                        JOIN PATIENT_MSDETAILS USING (PATIENT_ID)
                        JOIN COVID_SYMPTOMS S  USING (PATIENT_ID)
                        WHERE DMT_GLUCOCORTICOID =1
             GROUP BY covid19_has_symptoms) e
         WHERE row != 'null'
         AND e.covid19_has_symptoms=1;

--71.Display the patients with the highest BMI.

SELECT * 
FROM 
        patient_details 
WHERE 
        bmi_in_cat2 = (SELECT MAX(bmi_in_cat2) FROM patient_details);

--72.Is there a correlation between EDSS and Recovery or Ventilation? Show what correlation exists.
-- correlation between edss and Ventilation
SELECT 
        round(CORR(pm.edss_in_cat2, cd.covid19_ventilation)::numeric,2) AS correlation_edss_ventilation
FROM 
        patient_msdetails pm
JOIN 
        covid_details cd 
ON 
        pm.patient_id = cd.patient_id;

-- correlation between edss and recovery
SELECT 
        round(CORR(pm.edss_in_cat2, cd.covid19_outcome_recovered)::numeric,2) AS correlation_edss_recovery
FROM 
        patient_msdetails pm
join 
        covid_details cd 
ON 
        pm.patient_id = cd.patient_id;

--73.How many patients in the dataset have a BMI of 30 or more?

SELECT COUNT(patient_id) FROM patient_details
     WHERE bmi_in_cat2 >=30;

--74.How many patients in the ICU had more than 3 comorbidities?

WITH patient_ICU AS
(
SELECT 
        cd.patient_id,
    (SELECT SUM(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease + 
                com_diabetes + com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy + 
                com_neurological_neuromuscular) AS patient_comorbidities
     FROM comorbidities como 
         WHERE cd.patient_id = como.patient_id)
FROM 
        covid_details cd 
JOIN 
        comorbidities com
ON 
        cd.patient_id = com.patient_id
WHERE 
        covid19_icu_stay = 1
ORDER BY 
        patient_comorbidities DESC
)
SELECT COUNT(patient_id) as patients_ICU_comorbidities
FROM patient_ICU
WHERE patient_comorbidities > 3

--75.Alter table patient_msdetails change the column type of edss_in_cat2 to text and retain all values. 
  --Reverse the change and re-update it as an integer without losing any values
  
-- Step 1: Change the column type to text
ALTER TABLE patient_msdetails
ALTER COLUMN edss_in_cat2 TYPE TEXT;

SELECT * FROM patient_msdetails

-- Step 2: Reverse the column type to integer
ALTER TABLE patient_msdetails
ALTER COLUMN edss_in_cat2 TYPE INTEGER
USING (edss_in_cat2::INTEGER); 

SELECT * FROM patient_msdetails

--76.Write a query using recursive view(use the given dataset only) 

--created recursive view to find patients those are admitted in the hospital 
--in the same month (year may differ) for date_of_onset for patient 'C_1005'
CREATE OR REPLACE RECURSIVE VIEW recursive_view (patient,patient1,dt) AS 
  SELECT patient_id AS patient, 'patient1' AS patient1 
        ,DATE_PART('month',date_of_onset) AS dt 
        FROM 
    covid_details  
                 where patient_id = 'C_1005'        
  UNION ALL 
  SELECT 
    c.patient_id AS patient1, recursive_view.patient AS patient  
        ,DATE_PART('month',date_of_onset) AS dt
        FROM
    covid_details c
         INNER JOIN recursive_view ON DATE_PART('month',date_of_onset)  = recursive_view.dt
        WHERE covid19_admission_hospital=1;

SELECT * FROM recursive_view;

--77.What is the 3rd highest BMI of the patients with more than 2 comorbidities? Use windows functions?

WITH patient_comorbidities AS
(
SELECT 
        pd.patient_id,pd.bmi_in_cat2,
        (SELECT sum(com_cardiovascular_disease + com_chronic_kidney_disease + com_chronic_liver_disease 
        + com_diabetes + com_hypertension + com_immunodeficiency + com_lung_disease + com_malignancy 
        + com_neurological_neuromuscular) AS comorbidities_SUM
        FROM comorbidities como WHERE pd.patient_id = como.patient_id)
FROM 
        patient_details pd 
JOIN 
        comorbidities como
ON 
        pd.patient_id = como.patient_id
)
SELECT bmi_in_cat2 AS hightest_3rdBMI_having_morethan_2_comorbidties
FROM (SELECT bmi_in_cat2,
    DENSE_RANK() OVER (ORDER BY bmi_in_cat2 DESC) AS denserank
  FROM patient_comorbidities WHERE comorbidities_SUM > 2) 
WHERE denserank = 3;

--78.Update the table patient_msdetails. Set drugs prescribed to be Sentence case, query the results of the updated table without writing a second query

UPDATE 
        patient_msdetails
SET 
        prescribed_drug = INITCAP(prescribed_drug)
RETURNING *;

--79.Use the materialized view in Q14. to show every patients details in one single line using a JSON function

-- Query to convert all rows into one single line
SELECT 
        array_to_json(ARRAY_AGG(row_to_json(tablerow)))
FROM (
    SELECT patient_id,category,sex,age_group,covid_severity 
        FROM view_covidSeverity
    ) tablerow

--80.Create a stored procedure that adds a column to table Covid Details. 
   --The column should just be the Year extracted from Date Onset
   
-- Drop the stored procedure "addcolumn_updateyear" if exists
DROP PROCEDURE IF EXISTS addcolumn_updateyear;

-- Drop the column "onset_year" from the table covid_details if exists
ALTER TABLE covid_details 
DROP COLUMN onset_year;

-- Stored Procedure to add a new column and populate the values into that column
CREATE OR REPLACE PROCEDURE addcolumn_updateyear(OUT Infomessage text)
LANGUAGE plpgsql
AS $$
BEGIN
        -- Add a new column with the name "onset_year" to covid_details table
        ALTER TABLE covid_details
        ADD COLUMN onset_year INT;
        
        -- Extract the year from "date_of_onset" column and updates the value to "onset_year" column
        UPDATE covid_details
        SET onset_year = EXTRACT(YEAR FROM date_of_onset);
        
        SELECT 'Updated Successfully' INTO Infomessage;
END; $$

-- Call to the stored procedure - returns a message after the execution is sucessful.
call addcolumn_updateyear(NULL);

-- Select query to verify the results
SELECT patient_id,date_of_onset,onset_year FROM covid_details;




