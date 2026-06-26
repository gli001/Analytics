{{ config(
    materialized='table',
    alias='collection_pl_post_dq_score'
) }}

WITH _credit_report_current AS (
    SELECT * FROM (
        SELECT 
            bd.LoanID, 
            bd.CurrentProcessDate, 
            pr.ExternalCreditReportId AS ExternalCreditReportIDCur, 
            pr.CreatedDate AS CBDateCur, 
            CAST(pr.FICOScore AS INT64) AS FICOScoreCur,
            ROW_NUMBER() OVER(
                PARTITION BY bd.LoanID, bd.CurrentProcessDate 
                ORDER BY pr.CreatedDate DESC
            ) AS RowNum 
        FROM {{ ref('collection_pl_post_dq_cv') }} AS bd
        LEFT JOIN {{ source('PortFolioMgmt', 'PortfolioReport') }} AS pr 
            ON bd.LoanID = pr.LoanId 
            AND DATE_DIFF(CAST(pr.CreatedDate AS DATE), CAST(bd.CurrentProcessDate AS DATE), DAY) < 0
    ) AS sub
    WHERE sub.RowNum = 1
),

_credit_report_last_1_mth AS (
    SELECT * FROM (
        SELECT 
            bd.LoanID, 
            bd.CurrentProcessDate, 
            pr.ExternalCreditReportId AS ExternalCreditReportIDLast1, 
            pr.CreatedDate AS CBDateLast1, 
            pr.FICOScore AS FICOScoreLast1,
            ROW_NUMBER() OVER(
                PARTITION BY bd.LoanID, bd.CurrentProcessDate 
                ORDER BY pr.CreatedDate DESC
            ) AS RowNum 
        FROM {{ ref('collection_pl_post_dq_cv') }} AS bd
        LEFT JOIN {{ source('PortFolioMgmt', 'PortfolioReport') }} AS pr 
            ON bd.LoanID = pr.LoanId 
            AND DATE_DIFF(CAST(pr.CreatedDate AS DATE), CAST(bd.CBDate AS DATE), MONTH) = -1
    ) AS sub
    WHERE sub.RowNum = 1
),

_credit_report_last_2_mth AS (
    SELECT * FROM (
        SELECT 
            bd.LoanID, 
            bd.CurrentProcessDate, 
            pr.ExternalCreditReportId AS ExternalCreditReportIDLast2, 
            pr.CreatedDate AS CBDateLast2, 
            pr.FICOScore AS FICOScoreLast2,
            ROW_NUMBER() OVER(
                PARTITION BY bd.LoanID, bd.CurrentProcessDate 
                ORDER BY pr.CreatedDate DESC
            ) AS RowNum 
        FROM {{ ref('collection_pl_post_dq_cv') }} AS bd
        LEFT JOIN {{ source('PortFolioMgmt', 'PortfolioReport') }} AS pr 
            ON bd.LoanID = pr.LoanId 
            AND DATE_DIFF(CAST(pr.CreatedDate AS DATE), CAST(bd.CBDate AS DATE), MONTH) = -2
    ) AS sub
    WHERE sub.RowNum = 1
),

_credit_report_last_3_mth AS (
    SELECT * FROM (
        SELECT 
            bd.LoanID, 
            bd.CurrentProcessDate, 
            pr.ExternalCreditReportId AS ExternalCreditReportIDLast3, 
            pr.CreatedDate AS CBDateLast3, 
            pr.FICOScore AS FICOScoreLast3,
            ROW_NUMBER() OVER(
                PARTITION BY bd.LoanID, bd.CurrentProcessDate 
                ORDER BY pr.CreatedDate DESC
            ) AS RowNum 
        FROM {{ ref('collection_pl_post_dq_cv') }} AS bd
        LEFT JOIN {{ source('PortFolioMgmt', 'PortfolioReport') }} AS pr 
            ON bd.LoanID = pr.LoanId 
            AND DATE_DIFF(CAST(pr.CreatedDate AS DATE), CAST(bd.CBDate AS DATE), MONTH) = -3
    ) AS sub
    WHERE sub.RowNum = 1
),

_credit_report_last_4_mth AS (
    SELECT * FROM (
        SELECT 
            bd.LoanID, 
            bd.CurrentProcessDate, 
            pr.ExternalCreditReportId AS ExternalCreditReportIDLast4, 
            pr.CreatedDate AS CBDateLast4, 
            pr.FICOScore AS FICOScoreLast4,
            ROW_NUMBER() OVER(
                PARTITION BY bd.LoanID, bd.CurrentProcessDate 
                ORDER BY pr.CreatedDate DESC
            ) AS RowNum 
        FROM {{ ref('collection_pl_post_dq_cv') }} AS bd
        LEFT JOIN {{ source('PortFolioMgmt', 'PortfolioReport') }} AS pr 
            ON bd.LoanID = pr.LoanId 
            AND DATE_DIFF(CAST(pr.CreatedDate AS DATE), CAST(bd.CBDate AS DATE), MONTH) = -4
    ) AS sub
    WHERE sub.RowNum = 1
),

_credit_report_last_5_mth AS (
    SELECT * FROM (
        SELECT 
            bd.LoanID, 
            bd.CurrentProcessDate, 
            pr.ExternalCreditReportId AS ExternalCreditReportIDLast5, 
            pr.CreatedDate AS CBDateLast5, 
            pr.FICOScore AS FICOScoreLast5,
            ROW_NUMBER() OVER(
                PARTITION BY bd.LoanID, bd.CurrentProcessDate 
                ORDER BY pr.CreatedDate DESC
            ) AS RowNum 
        FROM {{ ref('collection_pl_post_dq_cv') }} AS bd
        LEFT JOIN {{ source('PortFolioMgmt', 'PortfolioReport') }} AS pr 
            ON bd.LoanID = pr.LoanId 
            AND DATE_DIFF(CAST(pr.CreatedDate AS DATE), CAST(bd.CBDate AS DATE), MONTH) = -5
    ) AS sub
    WHERE sub.RowNum = 1
),

_credit_report_last_6_mth AS (
    SELECT * FROM (
        SELECT 
            bd.LoanID, 
            bd.CurrentProcessDate, 
            pr.ExternalCreditReportId AS ExternalCreditReportIDLast6, 
            pr.CreatedDate AS CBDateLast6, 
            pr.FICOScore AS FICOScoreLast6,
            ROW_NUMBER() OVER(
                PARTITION BY bd.LoanID, bd.CurrentProcessDate 
                ORDER BY pr.CreatedDate DESC
            ) AS RowNum 
        FROM {{ ref('collection_pl_post_dq_cv') }} AS bd
        LEFT JOIN {{ source('PortFolioMgmt', 'PortfolioReport') }} AS pr 
            ON bd.LoanID = pr.Id 
            AND DATE_DIFF(CAST(pr.CreatedDate AS DATE), CAST(bd.CBDate AS DATE), MONTH) = -6
    ) AS sub
    WHERE sub.RowNum = 1
)

SELECT 
    TO_HEX(SHA1(CONCAT(CAST(crc.LoanID AS STRING), CAST(crc.CurrentProcessDate AS STRING)))) AS FKPostDQScoreIdentityID,
    crc.LoanID,
    crc.CurrentProcessDate,
    crc.ExternalCreditReportIDCur,
    crc.CBDateCur,
    crc.FICOScoreCur,
    m1.ExternalCreditReportIDLast1,
    m1.CBDateLast1,
    m1.FICOScoreLast1,
    m2.ExternalCreditReportIDLast2,
    m2.CBDateLast2,
    m2.FICOScoreLast2,
    m3.ExternalCreditReportIDLast3,
    m3.CBDateLast3,
    m3.FICOScoreLast3,
    m4.ExternalCreditReportIDLast4,
    m4.CBDateLast4,
    m4.FICOScoreLast4,
    m5.ExternalCreditReportIDLast5,
    m5.CBDateLast5,
    m5.FICOScoreLast5,
    m6.ExternalCreditReportIDLast6,
    m6.CBDateLast6,
    m6.FICOScoreLast6,
    -- Most recent FICO compared to average of score in last 3 months
    CASE 
        WHEN crc.FICOScoreCur IS NULL 
            OR m1.FICOScoreLast1 IS NULL 
            OR m2.FICOScoreLast2 IS NULL 
            OR m3.FICOScoreLast3 IS NULL 
        THEN NULL 
        ELSE ROUND(crc.FICOScoreCur - (m1.FICOScoreLast1 + m2.FICOScoreLast2 + m3.FICOScoreLast3) / 3, 0) 
    END AS FICOCurToLast3Amt,
    -- Most recent FICO compared to average of score in last 6 months
    CASE 
        WHEN crc.FICOScoreCur IS NULL 
            OR m1.FICOScoreLast1 IS NULL 
            OR m2.FICOScoreLast2 IS NULL 
            OR m3.FICOScoreLast3 IS NULL 
            OR m4.FICOScoreLast4 IS NULL 
            OR m5.FICOScoreLast5 IS NULL 
            OR m6.FICOScoreLast6 IS NULL 
        THEN NULL 
        ELSE ROUND(crc.FICOScoreCur - (m1.FICOScoreLast1 + m2.FICOScoreLast2 + m3.FICOScoreLast3 + m4.FICOScoreLast4 + m5.FICOScoreLast5 + m6.FICOScoreLast6) / 6, 0) 
    END AS FICOCurToLast6Amt
FROM _credit_report_current AS crc
LEFT JOIN _credit_report_last_1_mth AS m1 
    ON crc.LoanID = m1.LoanID AND crc.CurrentProcessDate = m1.CurrentProcessDate
LEFT JOIN _credit_report_last_2_mth AS m2 
    ON crc.LoanID = m2.LoanID AND crc.CurrentProcessDate = m2.CurrentProcessDate
LEFT JOIN _credit_report_last_3_mth AS m3 
    ON crc.LoanID = m3.LoanID AND crc.CurrentProcessDate = m3.CurrentProcessDate
LEFT JOIN _credit_report_last_4_mth AS m4 
    ON crc.LoanID = m4.LoanID AND crc.CurrentProcessDate = m4.CurrentProcessDate
LEFT JOIN _credit_report_last_5_mth AS m5 
    ON crc.LoanID = m5.LoanID AND crc.CurrentProcessDate = m5.CurrentProcessDate
LEFT JOIN _credit_report_last_6_mth AS m6 
    ON crc.LoanID = m6.LoanID AND crc.CurrentProcessDate = m6.CurrentProcessDate
