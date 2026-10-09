-- =============================================================================
-- PE_ASSISTANT: Production Engineering AI Advisor
-- Script 06: Cortex Search Services
-- =============================================================================
-- Run after: 05_knowledge_pipeline.sql + populating all tables
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Domain Knowledge Search (vocabulary resolution)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE PE_POC.CURATED.PRODUCTION_CONTEXT_SEARCH
    ON CONTEXT_PROFILE
    ATTRIBUTES ENTRY_TYPE, SUB_DOMAIN, DOMAIN_NAME, SEMANTIC_VIEWS
    WAREHOUSE = PE_WH
    TARGET_LAG = '1 minute'
    COMMENT = 'Semantic search over production domain knowledge for vocabulary resolution'
    AS (
        SELECT
            ENTRY_ID, ENTRY_TYPE, SUB_DOMAIN, DOMAIN_NAME, NAME, CONTENT,
            CONTEXT_PROFILE, SEMANTIC_VIEWS, CATEGORY, PROPERTIES
        FROM PE_POC.CURATED.PRODUCTION_DOMAIN_KNOWLEDGE
        WHERE ACTIVE_IND = 'Y'
          AND CONTEXT_PROFILE IS NOT NULL
    );

-- ---------------------------------------------------------------------------
-- 2. Engineering Literature (document corpus with page-level citations)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE PE_POC.KNOWLEDGE.ENGINEERING_LITERATURE
    ON CHUNK_TEXT
    ATTRIBUTES TITLE, DOC_TYPE, PAGE_NUMBER, REFERENCE
    WAREHOUSE = PE_WH
    TARGET_LAG = '1 day'
    COMMENT = 'Document corpus search with page-level citations and DOI/SPE references'
    AS (
        SELECT CHUNK_ID, CHUNK_TEXT, TITLE, DOC_TYPE, PAGE_NUMBER, REFERENCE
        FROM PE_POC.KNOWLEDGE.DOC_CHUNKS
    );

-- ---------------------------------------------------------------------------
-- 3. Engineering Principles (knowledge graph concepts with source attribution)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE PE_POC.KNOWLEDGE.ENGINEERING_PRINCIPLES
    ON PROFILE_TEXT
    ATTRIBUTES NAME, NODE_TYPE, SOURCE_TITLE, SOURCE_DOC_TYPE, SOURCE_REFERENCE
    WAREHOUSE = PE_WH
    TARGET_LAG = '1 day'
    COMMENT = 'Concept profile search with source document attribution'
    AS (
        SELECT NODE_ID, PROFILE_TEXT, NAME, NODE_TYPE,
               SOURCE_TITLE, SOURCE_DOC_TYPE, SOURCE_REFERENCE
        FROM PE_POC.KNOWLEDGE.CONCEPT_PROFILES_TABLE
    );
