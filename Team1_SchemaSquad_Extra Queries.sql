--SQL Hackathon January 2024 Extra Queries

--Team Number: Team1
--Team Name: Schema Squad
--Team Members:
--Total Extra Questions: 7

--EXTRAQ1-Display the arrays of the patients, total number of patients for 
--all combinations of hypertension and diabetes comorbidities with having at least one of the two.

 SELECT comorbidity AS comorbidity
                ,array_length(ARRAY_AGG(patient),1)as noOFPatients
                ,ARRAY_AGG(patient)as array_OF_Patients                
        FROM(                                           
        SELECT  patient_id AS patient 
                ,CASE 
    WHEN com_hypertension=1 AND com_diabetes=1  THEN  'Hypertension-Diabetes'
                WHEN com_diabetes=1 AND com_hypertension=0 THEN 'Diabetes-noHypertension'
                WHEN com_diabetes=0 AND com_hypertension=1 THEN 'NoDiabetes-Hypertension'
                END AS comorbidity
        FROM comorbidities
        WHERE com_hypertension=1
                OR com_diabetes=1
        ) data(patient,comorbidity) GROUP BY comorbidity



--EXTRA Q2--Display all comorbidities having less than 15 patients 
 --using unnest function from the result of above question Question 1

 SELECT UNNEST(d.array_OF_Patients) AS patient_id,d.comorbidity 
       FROM
       (
       SELECT comorbidity AS comorbidity
                                  ,array_length(ARRAY_AGG(patient),1)as noOFPatients
                                  ,ARRAY_AGG(patient)as array_OF_Patients                
        	       FROM
       (                                           
       	          SELECT concat(patient_id, '') as patient,
                	    CASE 
    WHEN com_hypertension=1 AND com_diabetes=1 THEN 'Hypertension-Diabetes'
                	    WHEN com_diabetes=1 AND com_hypertension=0 THEN 'Diabetes-noHypertension'
                	    WHEN com_diabetes=0 AND com_hypertension=1 THEN 'NoDiabetes-Hypertension'
                	    END AS comorbidity
          FROM comorbidities
                       WHERE com_hypertension=1
                       OR com_diabetes=1
        	       ) AS data(patient,comorbidity) 
                      GROUP BY comorbidity
    )d
    WHERE d.noOfpatients<15
    ORDER BY d.noOfpatients


--EXTRA Q3---Find the list of prescribed drug starting with vowels and ends with alphabet 'b' using REGEXP_LIKE

 SELECT 
        DISTINCT(prescribed_drug) AS drug_name_startswith_vowel_endswith_b
       FROM 
                 Patient_msdetails

       WHERE REGEXP_LIKE(prescribed_drug,'^[aeiou][\w]*[b]$','i')
       
       ORDER BY prescribed_drug;


--EXTRA Q4--Display all the patients self isolated in the 
--last quarter of every year present in dataset along with year and quarter.  
--(4th quarter— from October-December)

SELECT 
COUNT(patient_id),
to_char(date_trunc('quarter', date_of_onset)::date, 'yyyy-q')
       FROM 
              covid_details
       WHERE EXTRACT(QUARTER FROM date_of_onset)=4
       AND covid19_self_isolation=1
       GROUP BY to_char(date_trunc('quarter', date_of_onset)::date, 'yyyy-q')
       ORDER BY to_char(date_trunc('quarter', date_of_onset)::date, 'yyyy-q');


--EXTRA-Q5--Display the string of all female pregnant patients,report source in age cat 1 for all ms_type2
SELECT 
           ms_type2, string_agg(patient_id,',') AS patients,
          STRING_AGG(report_source,',') AS report_source 
FROM  patient_details
WHERE age_in_cat =1
AND sex='female'
AND pregnancy=1
GROUP BY ms_type2
ORDER BY ms_type2;

--EXTRA Q6--Write a query displays count of hospitalized patients 
--along with count of patient those are  admitted in icu or in self isolation
SELECT 	
	COUNT(patient_id),
   		COUNT(patient_id) FILTER(WHERE covid19_self_isolation=1) iso_count,
   		COUNT(patient_id) FILTER(WHERE covid19_icu_stay=1) icu_count
FROM covid_details
WHERE covid19_admission_hospital=1
AND (covid19_self_isolation=1
OR covid19_icu_stay =1);

--EXTRA Q7--Create a table with JSON data Type. 
--Insert data from patient_details. 
--Display all patients data
--Display all female patients data
CREATE TABLE 
 	covid_patient_json_tbl 
(
        		id serial NOT NULL PRIMARY KEY,
        		info json NOT NULL
);

INSERT INTO 
covid_patient_json_tbl(info) 
SELECT 
  row_to_json(x)::jsonb FROM
            		(
   SELECT jsonb_build_object('patient_id', patient_id) AS patient, 
                          	   jsonb_build_object('sex', sex, 'age_in_cat', age_in_cat) AS patient_det 
                              FROM patient_details
) x;

--DISPLAY ALL PATIENTS DATA

SELECT info 
FROM 
covid_patient_json_tbl;

--DISPLAYS ALL FEMALE PATIENTS DATA

SELECT info->>'patient' AS patient, 
  info->>'patient_det' AS age_type 
FROM 
covid_patient_json_tbl
WHERE info ->'patient_det'->>'sex' ='female' 

