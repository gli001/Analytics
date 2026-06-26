{{ config(
    materialized='table',
    alias='collection_pl_post_dq_pymt_del'
) }}

WITH _base_population AS (
    SELECT 
        bd.LoanID, 
        bd.CurrentProcessDate 
    FROM {{ ref('collection_pl_post_dq_pop_v2') }} AS bd
),

_payments_summary AS (
    SELECT 
        sub.LoanID, 
        sub.CurrentProcessDate,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -30 THEN sub.PaymentAmt ELSE 0 END) AS TotalPaymentLast30DayAmt,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -30 THEN 1 ELSE 0 END) AS PaymentLast30DayCount,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -60 THEN sub.PaymentAmt ELSE 0 END) AS TotalPaymentLast60DayAmt,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -60 THEN 1 ELSE 0 END) AS PaymentLast60DayCount,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -90 THEN sub.PaymentAmt ELSE 0 END) AS TotalPaymentLast90DayAmt,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -90 THEN 1 ELSE 0 END) AS PaymentLast90DayCount
    FROM (
        SELECT 
            bp.LoanID, 
            bp.CurrentProcessDate,
            lp.TransactionEffectiveDate, 
            lp.Amount AS PaymentAmt
        FROM {{ source('Circleone', 'LoanPayment') }} AS lp
        JOIN {{ source('Circleone', 'LoanPaymentType') }} AS lpt
            ON lpt.LoanPaymentTypeID = lp.LoanPaymentTypeID
        JOIN {{ source('Circleone', 'LoanPaymentCategory') }} AS lpc
            ON lpc.LoanPaymentCategoryID = lp.LoanPaymentCategoryID
        JOIN _base_population AS bp
            ON bp.LoanID = lp.LoanID 
        WHERE lp.LoanPaymentTypeID IN (1, 2, 3, 12)
            AND lp.LoanPaymentCategoryID IN (1, 4)
            AND lp.OntarioPreviousSplitID IS NULL
            AND lp.LoanPaymentOutcomeTypeID IN (1, 2, 3)
            AND DATE_DIFF(CAST(lp.TransactionEffectiveDate AS DATE), CAST(bp.CurrentProcessDate AS DATE), DAY) >= -90 
            AND CAST(lp.CreatedDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE) 
            AND CAST(lp.TransactionEffectiveDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE)
    ) AS sub
    GROUP BY 1, 2
),

_last_payment_detail AS (
    SELECT 
        sub.LoanID, 
        sub.CurrentProcessDate,
        DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.TransactionEffectiveDate AS DATE), DAY) AS DaysSinceLastPaymentNum
    FROM (
        SELECT 
            bp.LoanID, 
            bp.CurrentProcessDate,
            lp.TransactionEffectiveDate,
            ROW_NUMBER() OVER(PARTITION BY bp.LoanID, bp.CurrentProcessDate ORDER BY lp.TransactionEffectiveDate DESC) AS RowNum
        FROM {{ source('Circleone', 'LoanPayment') }} AS lp
        JOIN _base_population AS bp
            ON bp.LoanID = lp.LoanID
        WHERE lp.LoanPaymentTypeID IN (1, 2, 3, 12)
            AND lp.LoanPaymentCategoryID IN (1, 4)
            AND lp.OntarioPreviousSplitID IS NULL
            AND lp.LoanPaymentOutcomeTypeID IN (1, 2, 3)
            AND CAST(lp.CreatedDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE) 
            AND CAST(lp.TransactionEffectiveDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE)
    ) AS sub
    WHERE sub.RowNum = 1
),

_reversal_payments_summary AS (
    SELECT 
        sub.LoanID, 
        sub.CurrentProcessDate,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -30 THEN sub.PaymentReverseAmt ELSE 0 END) AS TotalPaymentReversalLast30DayAmt,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -30 THEN 1 ELSE 0 END) AS PaymentReversalLast30DayCount,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -60 THEN sub.PaymentReverseAmt ELSE 0 END) AS TotalPaymentReversalLast60DayAmt,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -60 THEN 1 ELSE 0 END) AS PaymentReversalLast60DayCount,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -90 THEN sub.PaymentReverseAmt ELSE 0 END) AS TotalPaymentReversalLast90DayAmt,
        SUM(CASE WHEN DATE_DIFF(CAST(sub.TransactionEffectiveDate AS DATE), CAST(sub.CurrentProcessDate AS DATE), DAY) >= -90 THEN 1 ELSE 0 END) AS PaymentReversalLast90DayCount
    FROM (
        SELECT 
            bp.LoanID, 
            bp.CurrentProcessDate,
            lp.TransactionEffectiveDate, 
            lp.Amount AS PaymentReverseAmt
        FROM {{ source('Circleone', 'LoanPayment') }} AS lp
        JOIN _base_population AS bp
            ON bp.LoanID = lp.LoanID
        WHERE lp.LoanPaymentTypeID IN (6, 7, 8, 9, 13, 25, 26, 27, 28, 34, 35, 36)
            AND lp.LoanPaymentCategoryID IN (1, 3, 4)
            AND DATE_DIFF(CAST(lp.TransactionEffectiveDate AS DATE), CAST(bp.CurrentProcessDate AS DATE), DAY) >= -90 
            AND CAST(lp.CreatedDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE) 
            AND CAST(lp.TransactionEffectiveDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE)
    ) AS sub
    GROUP BY 1, 2
),

_last_reversal_payment_detail AS (
    SELECT 
        sub.LoanID, 
        sub.CurrentProcessDate,
        DATE_DIFF(CAST(sub.CurrentProcessDate AS DATE), CAST(sub.TransactionEffectiveDate AS DATE), DAY) AS DaysSinceLastReversalPaymentNum
    FROM (
        SELECT 
            bp.LoanID, 
            bp.CurrentProcessDate,
            lp.TransactionEffectiveDate,
            ROW_NUMBER() OVER(PARTITION BY bp.LoanID, bp.CurrentProcessDate ORDER BY lp.TransactionEffectiveDate DESC) AS RowNum
        FROM {{ source('Circleone', 'LoanPayment') }} AS lp
        JOIN _base_population AS bp
            ON bp.LoanID = lp.LoanID
        WHERE lp.LoanPaymentTypeID IN (6, 7, 8, 9, 13, 25, 26, 27, 28, 34, 35, 36)
            AND lp.LoanPaymentCategoryID IN (1, 3, 4)
            AND CAST(lp.CreatedDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE) 
            AND CAST(lp.TransactionEffectiveDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE)
    ) AS sub
    WHERE sub.RowNum = 1
),

_autopay_history AS (
    SELECT 
        bp.LoanID,
        bp.CurrentProcessDate,
        MAX(CASE WHEN flt.IsAutoACHOff = TRUE THEN 1 ELSE 0 END) AS EverCancelledAutoPayInd,
        MAX(CASE WHEN flt.IsAutoACHOff = TRUE AND flt.CurrentProcessDate BETWEEN DATE_SUB(bp.CurrentProcessDate, INTERVAL 30 DAY) AND bp.CurrentProcessDate THEN 1 ELSE 0 END) AS CancelledAutoPayLast30DayInd,
        MAX(CASE WHEN flt.IsAutoACHOff = TRUE AND flt.CurrentProcessDate BETWEEN DATE_SUB(bp.CurrentProcessDate, INTERVAL 60 DAY) AND bp.CurrentProcessDate THEN 1 ELSE 0 END) AS CancelledAutoPayLast60DayInd,
        MAX(CASE WHEN flt.IsAutoACHOff = TRUE AND flt.CurrentProcessDate BETWEEN DATE_SUB(bp.CurrentProcessDate, INTERVAL 90 DAY) AND bp.CurrentProcessDate THEN 1 ELSE 0 END) AS CancelledAutoPayLast90DayInd
    FROM {{ source('edw', 'fact_loan_trail') }} AS flt 
    JOIN _base_population AS bp
        ON flt.LoanID = bp.LoanID
        AND flt.CurrentProcessDate <= bp.CurrentProcessDate
    GROUP BY 1, 2
),

_payment_history_surplus AS (
    SELECT 
        lp.LoanID,
        lp.TransactionEffectiveDate,
        lp.Amount AS ActualPaymentAmt,
        flt.ScheduledMonthlyPaymentAmount AS MinDueAmt,
        CASE 
            WHEN lp.Amount > flt.ScheduledMonthlyPaymentAmount 
            THEN lp.Amount - flt.ScheduledMonthlyPaymentAmount 
            ELSE 0 
        END AS OverpaymentSurplusAmt
    FROM {{ source('Circleone', 'LoanPayment') }} AS lp
    JOIN {{ source('edw', 'fact_loan_trail') }} AS flt
        ON lp.LoanID = flt.LoanID 
        AND CAST(lp.TransactionEffectiveDate AS DATE) = flt.CurrentProcessDate
    WHERE lp.LoanPaymentTypeID IN (1, 2, 3, 12) 
        AND lp.LoanPaymentCategoryID IN (1, 4)
        AND lp.LoanPaymentOutcomeTypeID IN (1, 2, 3)
        AND lp.OntarioPreviousSplitID IS NULL
        AND flt.ScheduledMonthlyPaymentAmount > 0
),

_historical_aggregates AS (
    SELECT 
        bp.LoanID,
        bp.CurrentProcessDate,
        MAX(CASE WHEN phs.ActualPaymentAmt > phs.MinDueAmt THEN TRUE ELSE FALSE END) AS EverOverpayInd,
        SUM(phs.OverpaymentSurplusAmt) AS TotalPastOverpaymentSurplusAmt,
        SUM(phs.MinDueAmt) AS TotalPastMinDueObligationsAmt
    FROM _base_population AS bp
    LEFT JOIN _payment_history_surplus AS phs
        ON bp.LoanID = phs.LoanID
        AND CAST(phs.TransactionEffectiveDate AS DATE) < CAST(bp.CurrentProcessDate AS DATE)
    GROUP BY 1, 2
),

_trail_history_base AS (
    SELECT 
        bp.LoanID, 
        bp.CurrentProcessDate AS PopulationDate,
        flt.ObservationDate, 
        flt.DPD,
        LAG(flt.DPD, 1) OVER (PARTITION BY flt.LoanID ORDER BY flt.ObservationDate) AS LagDPD
    FROM _base_population AS bp
    JOIN {{ source('edw', 'fact_loan_trail') }} AS flt 
        ON bp.LoanID = flt.LoanID
    WHERE flt.ObservationDate < bp.CurrentProcessDate
),

_delinquency_features AS (
    SELECT 
        thb.PopulationDate, 
        thb.LoanID,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 3 AND thb.DPD >= 1 THEN 1 ELSE 0 END) AS Ever1PlusLast3MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 3 AND thb.DPD >= 30 THEN 1 ELSE 0 END) AS Ever30PlusLast3MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 3 AND thb.DPD >= 60 THEN 1 ELSE 0 END) AS Ever60PlusLast3MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 6 AND thb.DPD >= 1 THEN 1 ELSE 0 END) AS Ever1PlusLast6MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 6 AND thb.DPD >= 30 THEN 1 ELSE 0 END) AS Ever30PlusLast6MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 6 AND thb.DPD >= 60 THEN 1 ELSE 0 END) AS Ever60PlusLast6MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 12 AND thb.DPD >= 1 THEN 1 ELSE 0 END) AS Ever1PlusLast12MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 12 AND thb.DPD >= 30 THEN 1 ELSE 0 END) AS Ever30PlusLast12MthInd,
        MAX(CASE WHEN DATE_DIFF(thb.PopulationDate, thb.ObservationDate, MONTH) <= 12 AND thb.DPD >= 60 THEN 1 ELSE 0 END) AS Ever60PlusLast12MthInd,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 90 AND thb.DPD >= 1) AS NumDays1PlusLast90DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 90 AND thb.DPD >= 30) AS NumDays30PlusLast90DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 90 AND thb.DPD >= 60) AS NumDays60PlusLast90DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 120 AND thb.DPD >= 1) AS NumDays1PlusLast120DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 120 AND thb.DPD >= 30) AS NumDays30PlusLast120DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 120 AND thb.DPD >= 60) AS NumDays60PlusLast120DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 180 AND thb.DPD >= 1) AS NumDays1PlusLast180DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 180 AND thb.DPD >= 30) AS NumDays30PlusLast180DayCount,
        COUNTIF(DATE_DIFF(thb.PopulationDate, thb.ObservationDate, DAY) <= 180 AND thb.DPD >= 60) AS NumDays60PlusLast180DayCount,
        DATE_DIFF(thb.PopulationDate, MAX(CASE WHEN thb.DPD > 0 AND thb.DPD < 10 AND thb.LagDPD = 0 THEN thb.ObservationDate END), DAY) AS DaysSinceLast1PlusNum,
        DATE_DIFF(thb.PopulationDate, MAX(CASE WHEN thb.DPD >= 30 AND thb.LagDPD <= 29 THEN thb.ObservationDate END), DAY) AS DaysSinceLast30PlusNum,
        DATE_DIFF(thb.PopulationDate, MAX(CASE WHEN thb.DPD >= 60 AND thb.LagDPD <= 59 THEN thb.ObservationDate END), DAY) AS DaysSinceLast60PlusNum
    FROM _trail_history_base AS thb
    GROUP BY 1, 2
)

SELECT 
    TO_HEX(SHA1(CONCAT(CAST(bp.LoanID AS STRING), CAST(bp.CurrentProcessDate AS STRING)))) AS FKPaymentDelinquencyIdentityID,
    bp.LoanID, 
    bp.CurrentProcessDate,
    COALESCE(ps.TotalPaymentLast30DayAmt, 0) AS TotalPaymentLast30DayAmt,
    COALESCE(ps.TotalPaymentLast60DayAmt, 0) AS TotalPaymentLast60DayAmt,
    COALESCE(ps.TotalPaymentLast90DayAmt, 0) AS TotalPaymentLast90DayAmt,
    COALESCE(ps.PaymentLast30DayCount, 0) AS PaymentLast30DayCount,
    COALESCE(ps.PaymentLast60DayCount, 0) AS PaymentLast60DayCount,
    COALESCE(ps.PaymentLast90DayCount, 0) AS PaymentLast90DayCount,
    lpd.DaysSinceLastPaymentNum,
    COALESCE(rps.TotalPaymentReversalLast30DayAmt, 0) AS TotalPaymentReversalLast30DayAmt,
    COALESCE(rps.TotalPaymentReversalLast60DayAmt, 0) AS TotalPaymentReversalLast60DayAmt,
    COALESCE(rps.TotalPaymentReversalLast90DayAmt, 0) AS TotalPaymentReversalLast90DayAmt,
    COALESCE(rps.PaymentReversalLast30DayCount, 0) AS PaymentReversalLast30DayCount,
    COALESCE(rps.PaymentReversalLast60DayCount, 0) AS PaymentReversalLast60DayCount,
    COALESCE(rps.PaymentReversalLast90DayCount, 0) AS PaymentReversalLast90DayCount,
    lrpd.DaysSinceLastReversalPaymentNum,
    COALESCE(ah.EverCancelledAutoPayInd, 0) AS EverCancelledAutoPayInd,
    COALESCE(ah.CancelledAutoPayLast30DayInd, 0) AS CancelledAutoPayLast30DayInd,
    COALESCE(ah.CancelledAutoPayLast60DayInd, 0) AS CancelledAutoPayLast60DayInd,
    COALESCE(ah.CancelledAutoPayLast90DayInd, 0) AS CancelledAutoPayLast90DayInd,
    COALESCE(ha.EverOverpayInd, FALSE) AS EverOverpayInd,
    CASE 
        WHEN ha.EverOverpayInd = TRUE 
        THEN SAFE_DIVIDE(ha.TotalPastOverpaymentSurplusAmt, ha.TotalPastMinDueObligationsAmt)
        ELSE 0 
    END AS AggregatedOverpaymentPortionAmt,
    df.Ever1PlusLast3MthInd,
    df.Ever30PlusLast3MthInd,
    df.Ever60PlusLast3MthInd,
    df.Ever1PlusLast6MthInd,
    df.Ever30PlusLast6MthInd,
    df.Ever60PlusLast6MthInd,
    df.Ever1PlusLast12MthInd,
    df.Ever30PlusLast12MthInd,
    df.Ever60PlusLast12MthInd,
    df.NumDays1PlusLast90DayCount,
    df.NumDays30PlusLast90DayCount,
    df.NumDays60PlusLast90DayCount,
    df.NumDays1PlusLast120DayCount,
    df.NumDays30PlusLast120DayCount,
    df.NumDays60PlusLast120DayCount,
    df.NumDays1PlusLast180DayCount,
    df.NumDays30PlusLast180DayCount,
    df.NumDays60PlusLast180DayCount,
    df.DaysSinceLast1PlusNum,
    df.DaysSinceLast30PlusNum,
    df.DaysSinceLast60PlusNum
FROM _base_population AS bp
LEFT JOIN _payments_summary AS ps 
    ON bp.LoanID = ps.LoanID AND bp.CurrentProcessDate = ps.CurrentProcessDate
LEFT JOIN _last_payment_detail AS lpd 
    ON bp.LoanID = lpd.LoanID AND bp.CurrentProcessDate = lpd.CurrentProcessDate
LEFT JOIN _reversal_payments_summary AS rps 
    ON bp.LoanID = rps.LoanID AND bp.CurrentProcessDate = rps.CurrentProcessDate
LEFT JOIN _last_reversal_payment_detail AS lrpd 
    ON bp.LoanID = lrpd.LoanID AND bp.CurrentProcessDate = lrpd.CurrentProcessDate
LEFT JOIN _delinquency_features AS df 
    ON bp.LoanID = df.LoanID AND bp.CurrentProcessDate = df.PopulationDate
LEFT JOIN _autopay_history AS ah 
    ON bp.LoanID = ah.LoanID AND bp.CurrentProcessDate = ah.CurrentProcessDate
LEFT JOIN _historical_aggregates AS ha 
    ON bp.LoanID = ha.LoanID AND bp.CurrentProcessDate = ha.CurrentProcessDate
