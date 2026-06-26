{{ config(
    materialized='table',
    alias='collection_pl_post_dq_emailsms_var2'
) }}

WITH _base_population AS (
    SELECT 
        pdp.LoanID, 
        pdp.IndividualKey,
        pdp.CurrentProcessDate 
    FROM {{ ref('collection_pl_post_dq_pop_var2') }} AS pdp
),

-- Step 1: Get PL specific communications prior to CurrentProcessDate
_comms_activity AS (
    SELECT
        bp.LoanID,
        bp.CurrentProcessDate,
        fcs.SendID,
        fcs.SendType,
        DATE(fcs.SignalDateTime) AS SendDate,
        fcs.ClickCount,
        -- Time Window Flags
        CASE WHEN DATE(fcs.SignalDateTime) >= DATE_SUB(bp.CurrentProcessDate, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS Is30DayInd,
        CASE WHEN DATE(fcs.SignalDateTime) >= DATE_SUB(bp.CurrentProcessDate, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS Is90DayInd,
        CASE WHEN DATE(fcs.SignalDateTime) >= DATE_SUB(bp.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 ELSE 0 END AS Is12MthInd
    FROM _base_population AS bp
    INNER JOIN {{ source('edw', 'fact_comms_send') }} AS fcs
        ON fcs.IndividualKey = bp.IndividualKey
        AND DATE(fcs.SignalDateTime) < bp.CurrentProcessDate
        AND DATE(fcs.SignalDateTime) >= DATE_SUB(bp.CurrentProcessDate, INTERVAL 365 DAY)
    WHERE 
        (
            fcs.SendType = 'Email'
            AND fcs.MarketingStrategy = 'Borrower'
            AND LOWER(fcs.CampaignName) NOT LIKE '%webinar%'
            AND LOWER(fcs.CampaignName) NOT LIKE '%abandonment%'
            AND LOWER(fcs.CampaignName) NOT LIKE '%dxabandon%'
            AND fcs.CampaignName <> 'EverestSeed'
            AND (
                (
                    fcs.ChannelID IN ('86921', '106942')
                    AND (fcs.CampaignName LIKE '%PL_%' OR fcs.CampaignName LIKE '%OpsEmail-DPD%')
                )
                OR fcs.MarketingProgram IN ('Notification', 'Activation', 'Engagement', 'Onboarding', 'Welcome')
            )
        )
        OR fcs.SendType = 'SMS'
        OR fcs.SendType = 'Push'
),

-- Email Features
_email_features AS (
    SELECT
        ca.LoanID,
        ca.CurrentProcessDate,
        COUNT(CASE WHEN ca.SendType = 'Email' AND ca.Is30DayInd = 1 THEN ca.SendID END) AS EmailSent30DayCount,
        COUNT(CASE WHEN ca.SendType = 'Email' AND ca.Is90DayInd = 1 THEN ca.SendID END) AS EmailSent90DayCount,
        SAFE_DIVIDE(
            SUM(CASE WHEN ca.SendType = 'Email' AND ca.Is30DayInd = 1 AND ca.ClickCount > 0 THEN 1 ELSE 0 END),
            COUNT(CASE WHEN ca.SendType = 'Email' AND ca.Is30DayInd = 1 THEN ca.SendID END)
        ) AS EmailClickRate30DayAmt,
        SAFE_DIVIDE(
            SUM(CASE WHEN ca.SendType = 'Email' AND ca.Is90DayInd = 1 AND ca.ClickCount > 0 THEN 1 ELSE 0 END),
            COUNT(CASE WHEN ca.SendType = 'Email' AND ca.Is90DayInd = 1 THEN ca.SendID END)
        ) AS EmailClickRate90DayAmt,
        DATE_DIFF(
            ca.CurrentProcessDate,
            MAX(CASE WHEN ca.SendType = 'Email' AND ca.ClickCount > 0 THEN ca.SendDate END),
            DAY
        ) AS DaysSinceLastEmailClickNum
    FROM _comms_activity AS ca
    GROUP BY 1, 2
),

-- SMS Features
_sms_features AS (
    SELECT
        ca.LoanID,
        ca.CurrentProcessDate,
        MAX(CASE WHEN ca.SendType = 'SMS' AND ca.Is12MthInd = 1 THEN 1 ELSE 0 END) AS HasReceivedSMS12MthInd,
        COUNT(CASE WHEN ca.SendType = 'SMS' AND ca.Is30DayInd = 1 THEN ca.SendID END) AS SMSSent30DayCount,
        COUNT(CASE WHEN ca.SendType = 'SMS' AND ca.Is90DayInd = 1 THEN ca.SendID END) AS SMSSent90DayCount,
        SAFE_DIVIDE(
            SUM(CASE WHEN ca.SendType = 'SMS' AND ca.Is90DayInd = 1 AND ca.ClickCount > 0 THEN 1 ELSE 0 END),
            COUNT(CASE WHEN ca.SendType = 'SMS' AND ca.Is90DayInd = 1 THEN ca.SendID END)
        ) AS SMSClickRate90DayAmt,
        DATE_DIFF(
            ca.CurrentProcessDate,
            MAX(CASE WHEN ca.SendType = 'SMS' AND ca.ClickCount > 0 THEN ca.SendDate END),
            DAY
        ) AS DaysSinceLastSMSClickNum,
        MAX(CASE WHEN ca.SendType = 'SMS' AND ca.ClickCount > 0 THEN 1 ELSE 0 END) AS HasEverClickedSMSInd
    FROM _comms_activity AS ca
    GROUP BY 1, 2
),

-- Push Features
_push_features AS (
    SELECT
        ca.LoanID,
        ca.CurrentProcessDate,
        MAX(CASE WHEN ca.SendType = 'Push' THEN 1 ELSE 0 END) AS HasEverReceivedPushInd,
        COUNT(CASE WHEN ca.SendType = 'Push' AND ca.Is30DayInd = 1 THEN ca.SendID END) AS PushSent30DayCount,
        DATE_DIFF(
            ca.CurrentProcessDate,
            MAX(CASE WHEN ca.SendType = 'Push' THEN ca.SendDate END),
            DAY
        ) AS DaysSinceLastPushNum
    FROM _comms_activity AS ca
    GROUP BY 1, 2
)

-- Combined Features
SELECT
    TO_HEX(SHA1(CONCAT(CAST(bp.LoanID AS STRING), CAST(bp.CurrentProcessDate AS STRING)))) AS FKEmailSMSIdentityID,
    bp.LoanID,
    bp.CurrentProcessDate,
    -- Email
    COALESCE(ef.EmailSent30DayCount, 0) AS EmailSent30DayCount,
    COALESCE(ef.EmailSent90DayCount, 0) AS EmailSent90DayCount,
    ef.EmailClickRate30DayAmt,
    ef.EmailClickRate90DayAmt,
    ef.DaysSinceLastEmailClickNum,
    -- SMS
    COALESCE(sf.HasReceivedSMS12MthInd, 0) AS HasReceivedSMS12MthInd,
    COALESCE(sf.SMSSent30DayCount, 0) AS SMSSent30DayCount,
    COALESCE(sf.SMSSent90DayCount, 0) AS SMSSent90DayCount,
    sf.SMSClickRate90DayAmt,
    sf.DaysSinceLastSMSClickNum,
    COALESCE(sf.HasEverClickedSMSInd, 0) AS HasEverClickedSMSInd,
    -- Push
    COALESCE(pf.HasEverReceivedPushInd, 0) AS HasEverReceivedPushInd,
    COALESCE(pf.PushSent30DayCount, 0) AS PushSent30DayCount,
    pf.DaysSinceLastPushNum
FROM _base_population AS bp
LEFT JOIN _email_features AS ef 
    ON bp.LoanID = ef.LoanID 
    AND bp.CurrentProcessDate = ef.CurrentProcessDate
LEFT JOIN _sms_features AS sf 
    ON bp.LoanID = sf.LoanID 
    AND bp.CurrentProcessDate = sf.CurrentProcessDate
LEFT JOIN _push_features AS pf 
    ON bp.LoanID = pf.LoanID 
    AND bp.CurrentProcessDate = pf.CurrentProcessDate
