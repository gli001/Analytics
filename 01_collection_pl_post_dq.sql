{{ config(
    materialized='table',
    alias='collection_pl_post_dq_var2'
) }}

WITH _loan_trail_base AS (
    SELECT 
        flt.LoanID, 
        flt.IndividualKey,
        flt.CurrentProcessDate, 
        flt.DPD, 
        DATE_TRUNC(flt.CurrentProcessDate, MONTH) AS ProcessMth,
        LAG(flt.DPD, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) AS LagDPD,
        LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) AS LeadNSFFeeBal,
        flt.IsAutoACHOff, 
        CASE 
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) = 0 THEN flt.PrinBal 
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) > 0 THEN LEAD(flt.PrinBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) 
            ELSE flt.PrinBal 
        END AS PrinBal,
        CASE 
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) = 0 THEN flt.InterestBal 
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) > 0 THEN LEAD(flt.InterestBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) 
            ELSE flt.InterestBal 
        END AS IntBal,
        CASE 
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) = 0 THEN flt.LateFeeBal
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) > 0 THEN LEAD(flt.LateFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) 
            ELSE flt.LateFeeBal 
        END AS LateFeeBal,
        CASE 
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) = 0 THEN flt.NSFFeeBal
            WHEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) > 0 THEN LEAD(flt.NSFFeeBal, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.CurrentProcessDate) 
            ELSE flt.NSFFeeBal 
        END AS NSFFeeBal,
        flt.IsCeaseAndDesist,
        flt.IsFraud,
        flt.IsInSCRA,
        CASE WHEN flt.NSFFeeBal > 0 THEN 1 ELSE 0 END AS IndNSF, 
        CASE 
            WHEN flt.DSAEnrollmentDate <= flt.CurrentProcessDate AND (flt.DSAInactiveStartDate > flt.CurrentProcessDate OR flt.DSAInactiveStartDate IS NULL) THEN 'Y' 
            ELSE 'N' 
        END AS DSAInd
    FROM {{ source('edw', 'fact_loan_trail') }} AS flt
    WHERE flt.LoanStatusTypeID = 1 
),

_dq_filtered AS (
    SELECT 
        ltb.*,
        ROW_NUMBER() OVER(PARTITION BY ltb.LoanID, ltb.ProcessMth ORDER BY ltb.LoanID, ltb.ProcessMth, ltb.CurrentProcessDate) AS RowNum 
    FROM _loan_trail_base AS ltb
    WHERE ltb.DPD > 0 
        AND ltb.DPD < 10 
        AND ltb.LagDPD = 0 
        AND ltb.CurrentProcessDate BETWEEN '2024-07-01' AND '2025-12-31'
)

SELECT 
    TO_HEX(SHA1(CONCAT(CAST(dqf.LoanID AS STRING), CAST(dqf.ProcessMth AS STRING)))) AS FKPostDQIdentityID,
    dqf.LoanID,
    dqf.IndividualKey,
    dqf.CurrentProcessDate,
    dqf.DPD,
    dqf.ProcessMth,
    dqf.LagDPD,
    dqf.LeadNSFFeeBal,
    dqf.IsAutoACHOff,
    dqf.PrinBal,
    dqf.IntBal,
    dqf.LateFeeBal,
    dqf.NSFFeeBal,
    dqf.IsCeaseAndDesist,
    dqf.IsFraud,
    dqf.IsInSCRA,
    dqf.IndNSF,
    dqf.DSAInd
FROM _dq_filtered AS dqf
WHERE dqf.RowNum = 1
