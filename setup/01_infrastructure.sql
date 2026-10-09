-- =============================================================================
-- PE_ASSISTANT: Production Engineering AI Advisor
-- Script 01: Infrastructure — Database, Schemas, Warehouses, Stages, File Formats
-- =============================================================================
-- Prerequisites: SYSADMIN role (or equivalent with CREATE DATABASE privilege)
-- =============================================================================

USE ROLE SYSADMIN;

-- Database
CREATE DATABASE IF NOT EXISTS PE_POC;

-- Schemas
CREATE SCHEMA IF NOT EXISTS PE_POC.RAW_VOLVE;
CREATE SCHEMA IF NOT EXISTS PE_POC.CURATED;
CREATE SCHEMA IF NOT EXISTS PE_POC.KNOWLEDGE;
CREATE SCHEMA IF NOT EXISTS PE_POC.AGENTS;

-- Warehouses
CREATE WAREHOUSE IF NOT EXISTS PE_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Cortex Search indexing and general queries';

-- Use an existing warehouse or create one for Cortex Analyst SQL execution
-- CREATE WAREHOUSE IF NOT EXISTS WH_TEST
--     WAREHOUSE_SIZE = 'SMALL'
--     AUTO_SUSPEND = 60
--     AUTO_RESUME = TRUE;

-- Stages
CREATE STAGE IF NOT EXISTS PE_POC.RAW_VOLVE.DATA_STAGE
    COMMENT = 'Stage for Volve source CSV files'
    DIRECTORY = (ENABLE = TRUE);

CREATE STAGE IF NOT EXISTS PE_POC.KNOWLEDGE.DOC_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Stage for knowledge documents - SSE encryption for AI_PARSE_DOCUMENT compatibility'
    DIRECTORY = (ENABLE = TRUE);

CREATE STAGE IF NOT EXISTS PE_POC.AGENTS.EVAL_CONFIG_STAGE;

-- File Formats
CREATE FILE FORMAT IF NOT EXISTS PE_POC.RAW_VOLVE.CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    NULL_IF = ('', 'NULL', 'null')
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    MULTI_LINE = TRUE;

CREATE FILE FORMAT IF NOT EXISTS PE_POC.RAW_VOLVE.LAS_RAW_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = 'NONE'
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 0
    TRIM_SPACE = FALSE
    MULTI_LINE = TRUE;
