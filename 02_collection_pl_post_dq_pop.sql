{{ config(
    materialized='table',
    alias='collection_pl_post_dq_pop_var2'
) }}

WITH _base_data AS (
    SELECT * FROM {{ ref('collection_pl_post_dq_var2') }}
),

_dim_loan_data AS (
    SELECT 
        dl.LoanID, 
        dl.ChargeOffDate,
        dl.CustomerDeceasedDate
    FROM {{ source('edw', 'dim_loan') }} AS dl
    WHERE dl.LoanID IN (SELECT bd.LoanID FROM _base_data AS bd)
),

_bankruptcy_start AS (
    SELECT * FROM (
        SELECT
            bd.LoanID,
            bd.CurrentProcessDate,
            flt.BankruptcyStatus,
            flt.BankruptcyFilingDate AS BKStartDate,
            ROW_NUMBER() OVER(PARTITION BY bd.LoanID, bd.CurrentProcessDate ORDER BY flt.BankruptcyFilingDate DESC) AS RowNum
        FROM {{ source('edw', 'fact_loan_trail') }} AS flt
        JOIN _base_data AS bd 
            ON bd.LoanID = flt.LoanID
            AND DATE_DIFF(CAST(flt.BankruptcyFilingDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) <= 0
    ) AS sub
    WHERE sub.RowNum = 1
),

_bankruptcy_end AS (
    SELECT * FROM (
        SELECT
            bd.LoanID,
            bd.CurrentProcessDate,
            flt.BankruptcyStatus,
            flt.BankruptcyStatusDate AS BKEndDate,
            ROW_NUMBER() OVER(PARTITION BY bd.LoanID, bd.CurrentProcessDate ORDER BY flt.BankruptcyStatusDate DESC) AS RowNum 
        FROM {{ source('edw', 'fact_loan_trail') }} AS flt
        JOIN _base_data AS bd 
            ON bd.LoanID = flt.LoanID
        WHERE flt.BankruptcyStatus IN ('CLOSED', 'DISMISS', 'WITHDRAWN', 'TERMINATED')
    ) AS sub
    WHERE sub.RowNum = 1
),

_extensions AS (
    SELECT
        flt.LoanID,
        flt.ExtensionOfferDate AS ExtensionStartDate
    FROM {{ source('edw', 'fact_loan_trail') }} AS flt
    WHERE flt.LoanID IN (SELECT bd.LoanID FROM _base_data AS bd)
        AND flt.ExtensionOfferDate IS NOT NULL
    GROUP BY 1, 2
),

_settlements AS (
    SELECT
        flt.LoanID,
        flt.SettlementStartDate AS SettlementStartDate,
        flt.SettlementEndDate AS SettlementEndDate
    FROM {{ source('edw', 'fact_loan_trail') }} AS flt
    WHERE flt.LoanID IN (SELECT bd.LoanID FROM _base_data AS bd)
        AND flt.SettlementStartDate IS NOT NULL
    GROUP BY 1, 2, 3
),

_payment_drops AS (
    SELECT * FROM ( 
        SELECT
            enr.LoanId,
            bd.CurrentProcessDate, 
            pdd.PaymentDropStartDate,
            pdd.HigherPaymentStartDate,
            ROW_NUMBER() OVER(PARTITION BY enr.LoanId, bd.CurrentProcessDate ORDER BY pdd.PaymentDropStartDate DESC) AS RowNum 
        FROM {{ source('LoanModPrograms', 'Enrollment') }} AS enr
        JOIN {{ source('LoanModPrograms', 'PaymentDropDetail') }} AS pdd
            ON pdd.EnrollmentId = enr.EnrollmentId
        JOIN _base_data AS bd 
            ON bd.LoanID = enr.LoanId 
            AND DATE_DIFF(CAST(pdd.PaymentDropStartDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) <= 120
        WHERE enr.AcceptedDate IS NOT NULL
            AND enr.EnrollmentStatusID NOT IN (5, 7, 8, 9)
    ) AS sub
    WHERE sub.RowNum = 1
)

SELECT 
    bd.*, 
    dld.ChargeOffDate, 
    CASE 
        WHEN dld.ChargeOffDate > bd.CurrentProcessDate 
            AND DATE_DIFF(CAST(dld.ChargeOffDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), MONTH) <= 4 
        THEN 1 
        ELSE 0 
    END AS IndCO,
    dld.CustomerDeceasedDate AS DeceasedDate,
    CASE WHEN DATE_DIFF(CAST(dld.CustomerDeceasedDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) <= 0 THEN 1 ELSE 0 END AS IndDeceased,
    CASE WHEN bd.IsCeaseAndDesist IS TRUE THEN 1 ELSE 0 END AS IndCD,
    CASE WHEN bd.IsFraud IS TRUE THEN 1 ELSE 0 END AS IndFraud,
    CASE WHEN bd.IsInSCRA IS TRUE THEN 1 ELSE 0 END AS IndSCRA,
    MAX(CASE WHEN bks.BKStartDate IS NOT NULL AND (bke.BKEndDate IS NULL OR bke.BKEndDate >= bd.CurrentProcessDate) THEN 1 ELSE 0 END) AS IndBK,
    MAX(CASE WHEN DATE_DIFF(CAST(ext.ExtensionStartDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) <= 120 THEN 1 ELSE 0 END) AS IndExt,
    MAX(CASE 
            WHEN DATE_DIFF(CAST(stl.SettlementStartDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) <= 120 
                AND (DATE_DIFF(CAST(stl.SettlementEndDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) >= 0 OR stl.SettlementEndDate IS NULL) 
            THEN 1 
            ELSE 0 
        END) AS IndSettle,
    MAX(CASE WHEN pmd.PaymentDropStartDate IS NOT NULL AND (DATE_DIFF(CAST(pmd.HigherPaymentStartDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) >= 0 OR pmd.HigherPaymentStartDate IS NULL) THEN 1 ELSE 0 END) AS IndPD
FROM _base_data AS bd
LEFT JOIN _dim_loan_data AS dld ON bd.LoanID = dld.LoanID 
LEFT JOIN _bankruptcy_start AS bks ON bd.LoanID = bks.LoanID AND bd.CurrentProcessDate = bks.CurrentProcessDate 
LEFT JOIN _bankruptcy_end AS bke ON bd.LoanID = bke.LoanID AND bd.CurrentProcessDate = bke.CurrentProcessDate AND bks.BKStartDate < bke.BKEndDate
LEFT JOIN _extensions AS ext ON bd.LoanID = ext.LoanID
LEFT JOIN _settlements AS stl ON bd.LoanID = stl.LoanID
LEFT JOIN _payment_drops AS pmd ON bd.LoanID = pmd.LoanID AND bd.CurrentProcessDate = pmd.CurrentProcessDate 
GROUP BY ALL
