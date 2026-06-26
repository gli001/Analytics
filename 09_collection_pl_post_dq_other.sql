{{ config(
    materialized='table',
    alias='collection_pl_post_dq_other_var2'
) }}

-- 1. Origination Attributes
WITH _origination_attributes AS (
    SELECT 
        bp.LoanID, 
        bp.CurrentProcessDate,
        dl.OriginalAmountBorrowed AS OriginalAmountBorrowedAmt,
        dl.OriginationDate,
        dl.RatingCode,
        dl.TermYears,
        dl.IsJointApplication AS IsJointApplicationInd, 
        dl.PriorLoanCount,
        DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(dl.OriginationDate AS DATE), MONTH) AS MOBAmt
    FROM {{ ref('collection_pl_post_dq_pop_var2') }} AS bp
    LEFT JOIN {{ source('edw', 'dim_loan') }} AS dl 
        ON bp.LoanID = dl.LoanID
),

-- 2. Due Date Change (DDC) features
_due_date_change_features AS (
    SELECT 
        bp.LoanID, 
        bp.CurrentProcessDate,
        COUNTIF(DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(enr.NewDueDateEffectiveFrom AS DATE), MONTH) <= 6) AS DueDateChangeLast6MthCount,
        COUNTIF(DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(enr.NewDueDateEffectiveFrom AS DATE), MONTH) <= 12) AS DueDateChangeLast12MthCount,
        COUNTIF(DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(enr.NewDueDateEffectiveFrom AS DATE), MONTH) <= 24) AS DueDateChangeLast24MthCount,
        MAX(CASE WHEN enr.NewDueDateEffectiveFrom IS NOT NULL THEN 1 ELSE 0 END) AS EverDDCInd,
        DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), MAX(CAST(enr.NewDueDateEffectiveFrom AS DATE)), DAY) AS DaysSinceLastDDCNon
    FROM {{ ref('collection_pl_post_dq_pop_var2') }} AS bp
    LEFT JOIN {{ source('LoanModPrograms', 'Enrollment') }} AS enr 
        ON bp.LoanID = enr.LoanId 
        AND CAST(enr.CreatedDate AS DATE) < bp.CurrentProcessDate 
        AND CAST(enr.NewDueDateEffectiveFrom AS DATE) < bp.CurrentProcessDate
        AND enr.ProgramID = 2 -- Due Date Change
        AND enr.AcceptedDate IS NOT NULL
        AND enr.EnrollmentStatusID NOT IN (5, 6, 7, 8, 9)
    GROUP BY 1, 2
),

-- 3. Payment Drop (PD) features
_payment_drop_features AS (
    SELECT 
        sub.LoanID, 
        sub.CurrentProcessDate, 
        CASE WHEN MAX(sub.PaymentDropStartDate) IS NULL THEN 0 ELSE 1 END AS EverPDInd,
        DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), MAX(CAST(sub.HigherPaymentStartDate AS DATE)), DAY) AS DaysSinceLastPDGraduatedNum,
        DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), MAX(CAST(sub.PaymentDropStartDate AS DATE)), DAY) AS DaysSinceLastPDStartedNum
    FROM (
        SELECT
            bp.LoanID, 
            bp.CurrentProcessDate,
            pdd.PaymentDropStartDate,
            pdd.HigherPaymentStartDate
        FROM {{ ref('collection_pl_post_dq_pop_var2') }} AS bp
        LEFT JOIN {{ source('LoanModPrograms', 'Enrollment') }} AS enr 
            ON bp.LoanID = enr.LoanId 
            AND enr.AcceptedDate IS NOT NULL
            AND enr.EnrollmentStatusID NOT IN (5, 7, 8, 9)
        LEFT JOIN {{ source('LoanModPrograms', 'PaymentDropDetail') }} AS pdd
            ON pdd.EnrollmentId = enr.EnrollmentId 
            AND DATE_DIFF(CAST(pdd.PaymentDropStartDate AS DATE), CAST(bp.CurrentProcessDate AS DATE), DAY) < 0
    ) AS sub
    GROUP BY 1, 2
),

-- 4. Login Activity using Borrower Events
_login_activity_features AS (
    SELECT 
        sub.LoanID, 
        sub.CurrentProcessDate,
        SUM(CASE WHEN sub.LoginDate IS NULL THEN 0 WHEN DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.LoginDate AS DATE), DAY) <= 30 THEN 1 ELSE 0 END) AS LoginLast30DayCount,
        SUM(CASE WHEN sub.LoginDate IS NULL THEN 0 WHEN DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.LoginDate AS DATE), DAY) <= 60 THEN 1 ELSE 0 END) AS LoginLast60DayCount,
        SUM(CASE WHEN sub.LoginDate IS NULL THEN 0 WHEN DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.LoginDate AS DATE), DAY) <= 90 THEN 1 ELSE 0 END) AS LoginLast90DayCount,
        SUM(CASE WHEN sub.LoginDate IS NULL THEN 0 WHEN DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.LoginDate AS DATE), DAY) <= 30 AND sub.PasswordMatch = 1 THEN 1 ELSE 0 END) AS SuccessfulLoginLast30DayCount,
        SUM(CASE WHEN sub.LoginDate IS NULL THEN 0 WHEN DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.LoginDate AS DATE), DAY) <= 60 AND sub.PasswordMatch = 1 THEN 1 ELSE 0 END) AS SuccessfulLoginLast60DayCount,
        SUM(CASE WHEN sub.LoginDate IS NULL THEN 0 WHEN DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.LoginDate AS DATE), DAY) <= 90 AND sub.PasswordMatch = 1 THEN 1 ELSE 0 END) AS SuccessfulLoginLast90DayCount,
        DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), MAX(CAST(sub.LoginDate AS DATE)), DAY) AS DaysSinceLastLoginNum,
        DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), MAX(CASE WHEN sub.PasswordMatch = 1 THEN CAST(sub.LoginDate AS DATE) ELSE NULL END), DAY) AS DaysSinceLastSuccessfulLoginNum
    FROM ( 
        SELECT 
            bp.LoanID, 
            bp.CurrentProcessDate,
            la.CreatedDate AS LoginDate,
            la.PasswordMatch
        FROM {{ ref('collection_pl_post_dq_pop_var2') }} AS bp
        LEFT JOIN {{ source('Circleone', 'Loans') }} AS cl 
            ON bp.LoanID = cl.LoanID
        LEFT JOIN {{ source('IDVSession', 'LoginAttempt') }} AS la
            ON la.UserID = cl.BorrowerID 
            AND CAST(la.CreatedDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE)
    ) AS sub
    GROUP BY 1, 2
)

-- Final Output
SELECT 
    TO_HEX(SHA1(CONCAT(CAST(oa.LoanID AS STRING), CAST(oa.CurrentProcessDate AS STRING)))) AS FKOtherPostDQIdentityID,
    oa.LoanID,
    oa.CurrentProcessDate,
    oa.OriginalAmountBorrowedAmt,
    oa.OriginationDate,
    oa.RatingCode,
    oa.TermYears,
    oa.IsJointApplicationInd,
    oa.PriorLoanCount,
    oa.MOBAmt,
    ddc.DueDateChangeLast6MthCount,
    ddc.DueDateChangeLast12MthCount,
    ddc.DueDateChangeLast24MthCount,
    ddc.EverDDCInd,
    ddc.DaysSinceLastDDCNon,
    laf.LoginLast30DayCount,
    laf.LoginLast60DayCount,
    laf.LoginLast90DayCount,
    laf.SuccessfulLoginLast30DayCount,
    laf.SuccessfulLoginLast60DayCount,
    laf.SuccessfulLoginLast90DayCount,
    laf.DaysSinceLastLoginNum,
    laf.DaysSinceLastSuccessfulLoginNum,
    pdf.EverPDInd,
    pdf.DaysSinceLastPDGraduatedNum,
    pdf.DaysSinceLastPDStartedNum
FROM _origination_attributes AS oa 
LEFT JOIN _due_date_change_features AS ddc 
    ON oa.LoanID = ddc.LoanID 
    AND oa.CurrentProcessDate = ddc.CurrentProcessDate
LEFT JOIN _login_activity_features AS laf 
    ON oa.LoanID = laf.LoanID 
    AND oa.CurrentProcessDate = laf.CurrentProcessDate
LEFT JOIN _payment_drop_features AS pdf 
    ON oa.LoanID = pdf.LoanID 
    AND oa.CurrentProcessDate = pdf.CurrentProcessDate
