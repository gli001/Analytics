{{ config(
    materialized='table',
    alias='collection_pl_post_dq_call_var2'
) }}

WITH _base_population AS (
    SELECT 
        pdp.LoanID, 
        pdp.CurrentProcessDate 
    FROM {{ ref('collection_pl_post_dq_pop_var2') }} AS pdp
),

-- Get all call activity prior to snapshot date (unnest CallDetail)
_call_activity AS (
    SELECT
        bp.LoanID,
        bp.CurrentProcessDate,
        fvcl.CallDate,
        det.CampaignCategoryName,
        det.CallDirection,
        det.LvResult AS LVResult,
        det.CallTime,
        det.IsRPC AS IsRPC,
        -- Flag for PL collections call
        CASE WHEN det.CampaignCategoryName = 'PLCollections' THEN 1 ELSE 0 END AS IsPLCollectionsCall,
        -- Flag for inbound call
        CASE WHEN det.CallDirection = 'INBOUND' THEN 1 ELSE 0 END AS IsInboundCall,
        -- Flag for outbound calls (comprehensive)
        CASE 
            WHEN det.CallDirection IN ('OUTBOUND', 'MANUAL', 'HCI', 'SCHEDULE_CALL_BACK') 
            THEN 1 ELSE 0 
        END AS IsOutboundCall,
        -- Flag for answering machine
        CASE WHEN LOWER(det.LvResult) LIKE '%answering machine%' THEN 1 ELSE 0 END AS IsAnsweringMachine
    FROM _base_population AS bp
    INNER JOIN {{ source('edw', 'fact_voice_call_livevox') }} AS fvcl
        ON fvcl.LoanID = bp.LoanID
        AND fvcl.CallDate < bp.CurrentProcessDate
    CROSS JOIN UNNEST(fvcl.CallDetail) AS det
),

-- Prior Collections History Features (12 month window)
_prior_collections_features AS (
    SELECT
        ca.LoanID,
        ca.CurrentProcessDate,
        MAX(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 ELSE 0 END) AS HasPriorCollectionsCalls12MthInd,
        COUNT(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 END) AS PriorCollectionsCall12MthCount,
        COUNT(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.IsRPC = TRUE AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 END) AS PriorCollectionRPCCount12Mth,
        SAFE_DIVIDE(
            COUNT(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.IsRPC = TRUE AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 END),
            COUNT(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 END)
        ) AS PriorCollectionRPCRate12Mth,
        AVG(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.IsRPC = TRUE AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN ca.CallTime END) AS AvgCollectionRPCCallDuration12Mth,
        DATE_DIFF(ca.CurrentProcessDate, MAX(CASE WHEN ca.IsPLCollectionsCall = 1 THEN ca.CallDate END), DAY) AS DaysSinceLastPriorCollectionsCallNum,
        SAFE_DIVIDE(
            COUNT(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.IsAnsweringMachine = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 END),
            COUNT(CASE WHEN ca.IsPLCollectionsCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 365 DAY) THEN 1 END)
        ) AS CollectionAnsweringMachineRate12Mth
    FROM _call_activity AS ca
    GROUP BY 1, 2
),

-- Inbound Call Features (90 and 180 day windows)
_inbound_call_features AS (
    SELECT
        ca.LoanID,
        ca.CurrentProcessDate,
        MAX(ca.IsInboundCall) AS HasEverCalledInboundInd,
        -- 90 Day Inbound
        COUNT(CASE WHEN ca.IsInboundCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 90 DAY) THEN 1 END) AS InboundCallPast90DayCount,
        SUM(CASE WHEN ca.IsInboundCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 90 DAY) THEN ca.CallTime / 60.0 END) AS TotalInboundCallTime90Day,
        -- 180 Day Inbound
        COUNT(CASE WHEN ca.IsInboundCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 180 DAY) THEN 1 END) AS InboundCallPast180DayCount,
        SUM(CASE WHEN ca.IsInboundCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 180 DAY) THEN ca.CallTime / 60.0 END) AS TotalInboundCallTime180Day,
        DATE_DIFF(ca.CurrentProcessDate, MAX(CASE WHEN ca.IsInboundCall = 1 THEN ca.CallDate END), DAY) AS DaysSinceLastInboundCallNum
    FROM _call_activity AS ca
    GROUP BY 1, 2
),

-- Outbound Call Features (90 and 180 day window)
_outbound_call_features AS (
    SELECT
        ca.LoanID,
        ca.CurrentProcessDate,
        COUNT(CASE WHEN ca.IsOutboundCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 180 DAY) THEN 1 END) AS OutboundCallPast180DayCount,
        COUNT(CASE WHEN ca.IsOutboundCall = 1 AND ca.IsRPC = TRUE AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 180 DAY) THEN 1 END) AS OutboundRPCPast180DayCount,
        COUNT(CASE WHEN ca.IsOutboundCall = 1 AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 90 DAY) THEN 1 END) AS OutboundCallPast90DayCount,
        COUNT(CASE WHEN ca.IsOutboundCall = 1 AND ca.IsRPC = TRUE AND ca.CallDate >= DATE_SUB(ca.CurrentProcessDate, INTERVAL 90 DAY) THEN 1 END) AS OutboundRPCPast90DayCount
    FROM _call_activity AS ca
    GROUP BY 1, 2
),

-- Combined Features
_call_features_combined AS (
    SELECT
        bp.LoanID,
        bp.CurrentProcessDate,
        -- Collections
        COALESCE(pcf.HasPriorCollectionsCalls12MthInd, 0) AS HasPriorCollectionsCalls12MthInd,
        COALESCE(pcf.PriorCollectionsCall12MthCount, 0) AS PriorCollectionsCall12MthCount,
        COALESCE(pcf.PriorCollectionRPCCount12Mth, 0) AS PriorCollectionRPCCount12Mth,
        pcf.PriorCollectionRPCRate12Mth,
        pcf.AvgCollectionRPCCallDuration12Mth,
        pcf.DaysSinceLastPriorCollectionsCallNum,
        pcf.CollectionAnsweringMachineRate12Mth,
        -- Inbound
        COALESCE(icf.HasEverCalledInboundInd, 0) AS HasEverCalledInboundInd,
        COALESCE(icf.InboundCallPast90DayCount, 0) AS InboundCallPast90DayCount,
        COALESCE(icf.TotalInboundCallTime90Day, 0) AS TotalInboundCallTime90Day,
        COALESCE(icf.InboundCallPast180DayCount, 0) AS InboundCallPast180DayCount,
        COALESCE(icf.TotalInboundCallTime180Day, 0) AS TotalInboundCallTime180Day,
        icf.DaysSinceLastInboundCallNum,
        -- Outbound 90D, 180D
        COALESCE(ocf.OutboundCallPast180DayCount, 0) AS OutboundCallPast180DayCount,
        COALESCE(ocf.OutboundCallPast90DayCount, 0) AS OutboundCallPast90DayCount,
        SAFE_DIVIDE(ocf.OutboundRPCPast180DayCount, ocf.OutboundCallPast180DayCount) AS OutboundRPCRate180Day,
        SAFE_DIVIDE(ocf.OutboundRPCPast90DayCount, ocf.OutboundCallPast90DayCount) AS OutboundRPCRate90Day
    FROM _base_population AS bp
    LEFT JOIN _prior_collections_features AS pcf 
        ON bp.LoanID = pcf.LoanID 
        AND bp.CurrentProcessDate = pcf.CurrentProcessDate
    LEFT JOIN _inbound_call_features AS icf 
        ON bp.LoanID = icf.LoanID 
        AND bp.CurrentProcessDate = icf.CurrentProcessDate
    LEFT JOIN _outbound_call_features AS ocf 
        ON bp.LoanID = ocf.LoanID 
        AND bp.CurrentProcessDate = ocf.CurrentProcessDate
)

-- Final Output
SELECT
    TO_HEX(SHA1(CONCAT(CAST(bp.LoanID AS STRING), CAST(bp.CurrentProcessDate AS STRING)))) AS FKCallIdentityID,
    bp.LoanID,
    bp.CurrentProcessDate,
    cfc.HasPriorCollectionsCalls12MthInd,
    cfc.PriorCollectionsCall12MthCount,
    cfc.PriorCollectionRPCCount12Mth,
    cfc.PriorCollectionRPCRate12Mth,
    cfc.AvgCollectionRPCCallDuration12Mth,
    cfc.DaysSinceLastPriorCollectionsCallNum,
    cfc.CollectionAnsweringMachineRate12Mth,
    cfc.HasEverCalledInboundInd,
    cfc.InboundCallPast90DayCount,
    cfc.TotalInboundCallTime90Day,
    cfc.InboundCallPast180DayCount,
    cfc.TotalInboundCallTime180Day,
    cfc.DaysSinceLastInboundCallNum,
    cfc.OutboundCallPast180DayCount,
    cfc.OutboundRPCRate180Day,
    cfc.OutboundCallPast90DayCount,
    cfc.OutboundRPCRate90Day
FROM _base_population AS bp
LEFT JOIN _call_features_combined AS cfc 
    ON bp.LoanID = cfc.LoanID
    AND bp.CurrentProcessDate = cfc.CurrentProcessDate
