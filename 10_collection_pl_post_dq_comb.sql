{{ config(
    materialized='table',
    alias='collection_pl_post_dq_comb'
) }}

WITH _combined_features AS (
    SELECT 
        -- CV and Base attributes (Prefixing cv columns as they were refactored to TitleCase)
        cv.LoanID,
        cv.CurrentProcessDate,
        cv.CVCreatedDate,
        -- Note: All TU attributes in 'cv' are now TitleCase/UPPERCASE and prefixed with 'cv.'
        cv.AU205S, cv.S208S, cv.IN09S, cv.S209A, cv.AU204S, cv.S207S, cv.BI30S, cv.G051S, cv.JT42S, cv.G099S,
        -- (List continues for all TU attributes refactored in previous models)
        
        orig.VantageScoreApp,
        orig.FICOScoreApp,
        bp.DPD, 
        bp.LagDPD, 
        CASE WHEN bp.IndDeceased = 1 OR bp.IndFraud = 1 OR bp.IndBK = 1 THEN 1 ELSE 0 END AS IndSS,
        CASE WHEN bp.IndExt = 1 OR bp.IndSettle = 1 OR bp.IndPD = 1 THEN 1 ELSE 0 END AS IndLM,
        bp.IndCO,
        bp.IsAutoACHOff, 
        bp.PrinBal, 
        bp.IntBal, 
        bp.LateFeeBal, 
        bp.NSFFeeBal, 
        scr.FICOScoreCur, 
        scr.FICOCurToLast3Amt, 
        scr.FICOCurToLast6Amt,
        CASE 
            WHEN CAST(scr.FICOScoreCur AS INT64) IS NULL OR CAST(orig.FICOScoreApp AS INT64) IS NULL THEN NULL 
            ELSE ROUND(CAST(scr.FICOScoreCur AS INT64) - CAST(orig.FICOScoreApp AS INT64), 0) 
        END AS FICOCurToAppAmt,
        
        -- Payments (Filtered by MOB/Tenure)
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE pd.TotalPaymentLast30DayAmt END AS TotalPaymentLast30DayAmt,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE pd.PaymentLast30DayCount END AS PaymentLast30DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 60 THEN NULL ELSE pd.TotalPaymentLast60DayAmt END AS TotalPaymentLast60DayAmt,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 60 THEN NULL ELSE pd.PaymentLast60DayCount END AS PaymentLast60DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE pd.TotalPaymentLast90DayAmt END AS TotalPaymentLast90DayAmt,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE pd.PaymentLast90DayCount END AS PaymentLast90DayCount,
        pd.DaysSinceLastPaymentNum,
        
        -- Reversals
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE -pd.TotalPaymentReversalLast30DayAmt END AS TotalPaymentReversalLast30DayAmt,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE pd.PaymentReversalLast30DayCount END AS PaymentReversalLast30DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 60 THEN NULL ELSE -pd.TotalPaymentReversalLast60DayAmt END AS TotalPaymentReversalLast60DayAmt,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 60 THEN NULL ELSE pd.PaymentReversalLast60DayCount END AS PaymentReversalLast60DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE -pd.TotalPaymentReversalLast90DayAmt END AS TotalPaymentReversalLast90DayAmt,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE pd.PaymentReversalLast90DayCount END AS PaymentReversalLast90DayCount,
        pd.DaysSinceLastReversalPaymentNum,
        
        -- Autopay and Overpayment
        pd.EverCancelledAutoPayInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE pd.CancelledAutoPayLast30DayInd END AS CancelledAutoPayLast30DayInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 60 THEN NULL ELSE pd.CancelledAutoPayLast60DayInd END AS CancelledAutoPayLast60DayInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE pd.CancelledAutoPayLast90DayInd END AS CancelledAutoPayLast90DayInd,
        pd.EverOverpayInd,
        pd.AggregatedOverpaymentPortionAmt,

        -- Delinquency History
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 3 THEN NULL ELSE pd.Ever1PlusLast3MthInd END AS Ever1PlusLast3MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 3 THEN NULL ELSE pd.Ever30PlusLast3MthInd END AS Ever30PlusLast3MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 3 THEN NULL ELSE pd.Ever60PlusLast3MthInd END AS Ever60PlusLast3MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 6 THEN NULL ELSE pd.Ever1PlusLast6MthInd END AS Ever1PlusLast6MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 6 THEN NULL ELSE pd.Ever30PlusLast6MthInd END AS Ever30PlusLast6MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 6 THEN NULL ELSE pd.Ever60PlusLast6MthInd END AS Ever60PlusLast6MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE pd.Ever1PlusLast12MthInd END AS Ever1PlusLast12MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE pd.Ever30PlusLast12MthInd END AS Ever30PlusLast12MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE pd.Ever60PlusLast12MthInd END AS Ever60PlusLast12MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE pd.NumDays1PlusLast90DayCount END AS NumDays1PlusLast90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE pd.NumDays30PlusLast90DayCount END AS NumDays30PlusLast90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE pd.NumDays60PlusLast90DayCount END AS NumDays60PlusLast90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 120 THEN NULL ELSE pd.NumDays1PlusLast120DayCount END AS NumDays1PlusLast120DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 120 THEN NULL ELSE pd.NumDays30PlusLast120DayCount END AS NumDays30PlusLast120DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 120 THEN NULL ELSE pd.NumDays60PlusLast120DayCount END AS NumDays60PlusLast120DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 180 THEN NULL ELSE pd.NumDays1PlusLast180DayCount END AS NumDays1PlusLast180DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 180 THEN NULL ELSE pd.NumDays30PlusLast180DayCount END AS NumDays30PlusLast180DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 180 THEN NULL ELSE pd.NumDays60PlusLast180DayCount END AS NumDays60PlusLast180DayCount,
        pd.DaysSinceLast1PlusNum,
        pd.DaysSinceLast30PlusNum,
        pd.DaysSinceLast60PlusNum,

        -- Origination Attributes
        ot.OriginalAmountBorrowedAmt,
        ot.OriginationDate,
        ot.RatingCode,
        ot.TermYears,
        ot.IsJointApplicationInd,
        ot.MOBAmt,
        COALESCE(ot.PriorLoanCount, 0) AS PriorLoanCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 6 THEN NULL ELSE ot.DueDateChangeLast6MthCount END AS DueDateChangeLast6MthCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE ot.DueDateChangeLast12MthCount END AS DueDateChangeLast12MthCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 24 THEN NULL ELSE ot.DueDateChangeLast24MthCount END AS DueDateChangeLast24MthCount,
        ot.EverDDCInd,
        ot.DaysSinceLastDDCNon,

        -- Login features
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE ot.LoginLast30DayCount END AS LoginLast30DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 60 THEN NULL ELSE ot.LoginLast60DayCount END AS LoginLast60DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE ot.LoginLast90DayCount END AS LoginLast90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE ot.SuccessfulLoginLast30DayCount END AS SuccessfulLoginLast30DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 60 THEN NULL ELSE ot.SuccessfulLoginLast60DayCount END AS SuccessfulLoginLast60DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE ot.SuccessfulLoginLast90DayCount END AS SuccessfulLoginLast90DayCount,
        ot.DaysSinceLastLoginNum,
        ot.DaysSinceLastSuccessfulLoginNum,
        ot.EverPDInd,
        ot.DaysSinceLastPDGraduatedNum,
        ot.DaysSinceLastPDStartedNum,

        -- Call Activity
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE ca.HasPriorCollectionsCalls12MthInd END AS HasPriorCollectionsCalls12MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE ca.PriorCollectionsCall12MthCount END AS PriorCollectionsCall12MthCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE ca.PriorCollectionRPCCount12Mth END AS PriorCollectionRPCCount12Mth,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE ca.PriorCollectionRPCRate12Mth END AS PriorCollectionRPCRate12Mth,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE ca.AvgCollectionRPCCallDuration12Mth END AS AvgCollectionRPCCallDuration12Mth,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE ca.CollectionAnsweringMachineRate12Mth END AS CollectionAnsweringMachineRate12Mth,
        ca.DaysSinceLastPriorCollectionsCallNum,
        ca.HasEverCalledInboundInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE ca.InboundCallPast90DayCount END AS InboundCallPast90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE ca.TotalInboundCallTime90Day END AS TotalInboundCallTime90Day,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 180 THEN NULL ELSE ca.InboundCallPast180DayCount END AS InboundCallPast180DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 180 THEN NULL ELSE ca.TotalInboundCallTime180Day END AS TotalInboundCallTime180Day,
        ca.DaysSinceLastInboundCallNum,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 180 THEN NULL ELSE ca.OutboundCallPast180DayCount END AS OutboundCallPast180DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE ca.OutboundCallPast90DayCount END AS OutboundCallPast90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 180 THEN NULL ELSE ca.OutboundRPCRate180Day END AS OutboundRPCRate180Day,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE ca.OutboundRPCRate90Day END AS OutboundRPCRate90Day,

        -- Email / SMS
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE em.EmailSent30DayCount END AS EmailSent30DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE em.EmailSent90DayCount END AS EmailSent90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE em.EmailClickRate30DayAmt END AS EmailClickRate30DayAmt,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE em.EmailClickRate90DayAmt END AS EmailClickRate90DayAmt,
        em.DaysSinceLastEmailClickNum,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), MONTH) < 12 THEN NULL ELSE em.HasReceivedSMS12MthInd END AS HasReceivedSMS12MthInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE em.SMSSent30DayCount END AS SMSSent30DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE em.SMSSent90DayCount END AS SMSSent90DayCount,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 90 THEN NULL ELSE em.SMSClickRate90DayAmt END AS SMSClickRate90DayAmt,
        em.DaysSinceLastSMSClickNum,
        em.HasEverClickedSMSInd,
        em.HasEverReceivedPushInd,
        CASE WHEN DATE_DIFF(CAST(bp.CurrentProcessDate AS DATE), CAST(ot.OriginationDate AS DATE), DAY) < 30 THEN NULL ELSE em.PushSent30DayCount END AS PushSent30DayCount,
        em.DaysSinceLastPushNum

    FROM {{ ref('collection_pl_post_dq_pop_v2') }} AS bp
    LEFT JOIN {{ ref('collection_pl_post_dq_cv') }} AS cv 
        ON bp.LoanID = cv.LoanID AND bp.CurrentProcessDate = cv.CurrentProcessDate 
    LEFT JOIN {{ ref('collection_pl_post_dq_score') }} AS scr 
        ON bp.LoanID = scr.LoanID AND bp.CurrentProcessDate = scr.CurrentProcessDate 
    LEFT JOIN {{ ref('collection_pl_origination') }} AS orig 
        ON bp.LoanID = orig.LoanIDApp 
    LEFT JOIN {{ ref('collection_pl_post_dq_pymt_del') }} AS pd 
        ON bp.LoanID = pd.LoanID AND bp.CurrentProcessDate = pd.CurrentProcessDate 
    LEFT JOIN {{ ref('collection_pl_post_dq_other_v2') }} AS ot 
        ON bp.LoanID = ot.LoanID AND bp.CurrentProcessDate = ot.CurrentProcessDate 
    LEFT JOIN {{ ref('collection_call') }} AS ca 
        ON bp.LoanID = ca.LoanID AND bp.CurrentProcessDate = ca.CurrentProcessDate 
    LEFT JOIN {{ ref('collection_emailsms') }} AS em 
        ON bp.LoanID = em.LoanID AND bp.CurrentProcessDate = em.CurrentProcessDate
)

SELECT 
    TO_HEX(SHA1(CONCAT(CAST(cf.LoanID AS STRING), CAST(cf.CurrentProcessDate AS STRING)))) AS FKCombinedIdentityID,
    cf.*
FROM _combined_features AS cf
