-- =============================================================================
-- PE_ASSISTANT: Production Engineering AI Advisor
-- Script 05: Knowledge Pipeline — Document parsing, chunking, knowledge graph
-- =============================================================================
-- Run after: 04_curated_layer.sql
-- Requires: PDF documents uploaded to @PE_POC.KNOWLEDGE.DOC_STAGE
-- =============================================================================

USE SCHEMA PE_POC.KNOWLEDGE;

-- ---------------------------------------------------------------------------
-- Document registry
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE SOURCES (
    DOC_ID VARCHAR NOT NULL DEFAULT UUID_STRING(),
    TITLE VARCHAR,
    DOC_TYPE VARCHAR,
    STAGE_PATH VARCHAR,
    LICENCE_NOTE VARCHAR,
    LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    REFERENCE VARCHAR,
    PRIMARY KEY (DOC_ID)
);

-- Seed the source documents (update STAGE_PATH to match your filenames)
INSERT INTO SOURCES (TITLE, DOC_TYPE, STAGE_PATH, LICENCE_NOTE, REFERENCE) VALUES
('Volve Plan for Utility and Development', 'PUD', '@PE_POC.RAW_VOLVE.DATA_STAGE/Volve PUD .pdf', 'Equinor open data - CC BY-NC-SA 4.0', 'Equinor Volve PUD, Licence 046, Feb 2005'),
('Well Summary F-1', 'WELL_REPORT', '@PE_POC.RAW_VOLVE.DATA_STAGE/WellSummary F-1.pdf', 'Equinor open data - CC BY-NC-SA 4.0', 'Equinor Volve Well Final Summary — 15/9-F-1'),
('Well Summary F-9', 'WELL_REPORT', '@PE_POC.RAW_VOLVE.DATA_STAGE/Well Summary F-9.pdf', 'Equinor open data - CC BY-NC-SA 4.0', 'Equinor Volve Well Final Summary — 15/9-F-9'),
('Well Summary F-12', 'WELL_REPORT', '@PE_POC.RAW_VOLVE.DATA_STAGE/Well Summary F-12.pdf', 'Equinor open data - CC BY-NC-SA 4.0', 'Equinor Volve Well Final Summary — 15/9-F-12'),
('Well Summary F-14', 'WELL_REPORT', '@PE_POC.RAW_VOLVE.DATA_STAGE/Well Summary F-14.pdf', 'Equinor open data - CC BY-NC-SA 4.0', 'Equinor Volve Well Final Summary — 15/9-F-14'),
('Petroleum Reservoir Dynamics', 'TEXTBOOK', '@PE_POC.RAW_VOLVE.DATA_STAGE/Petroleum Reservoir Dynamics.pdf', 'CC BY - LSU Open Textbook', 'LSU Open Textbook (CC BY)'),
('Production Forecasting - Decline Curve Analysis', 'SPE_PAPER', '@PE_POC.RAW_VOLVE.DATA_STAGE/Production forecasting decline curve analysis.pdf', 'PetroWiki/SPE open content', 'SPE PetroWiki — DCA; Arps (1945); Fetkovich (1980) DOI: 10.2118/28628-PA'),
('Solution Gas Drive Reservoirs', 'SPE_PAPER', '@PE_POC.RAW_VOLVE.DATA_STAGE/Solution gas drive reservoirs.pdf', 'PetroWiki/SPE open content', 'SPE PetroWiki — Solution Gas Drive Reservoirs'),
('Water Flooding', 'SPE_PAPER', '@PE_POC.RAW_VOLVE.DATA_STAGE/Water Flooding.pdf', 'PetroWiki/SPE open content', 'SPE PetroWiki — Waterflooding'),
('Water and Gas Coning', 'SPE_PAPER', '@PE_POC.RAW_VOLVE.DATA_STAGE/Water_And_Gas_Coning.pdf', 'PetroWiki/SPE open content', 'SPE PetroWiki PW-1061; DOI: 10.2118/PW1061');

-- ---------------------------------------------------------------------------
-- Parsed documents (page-level text from AI_PARSE_DOCUMENT)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE PARSED_DOCUMENTS (
    DOC_ID VARCHAR,
    FILENAME VARCHAR,
    PAGE_NUMBER NUMBER,
    PAGE_TEXT VARCHAR,
    PARSED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Parse all registered PDFs using AI_PARSE_DOCUMENT
-- NOTE: PDFs must be in a stage with SSE encryption (DOC_STAGE)
-- Copy PDFs from DATA_STAGE to DOC_STAGE first:
--   COPY FILES INTO @PE_POC.KNOWLEDGE.DOC_STAGE
--     FROM @PE_POC.RAW_VOLVE.DATA_STAGE PATTERN='.*\\.pdf';
-- Then parse:
--   INSERT INTO PARSED_DOCUMENTS (DOC_ID, FILENAME, PAGE_NUMBER, PAGE_TEXT)
--   SELECT s.DOC_ID, d.RELATIVE_PATH, d.PAGE_NUMBER, d.PAGE_CONTENT
--   FROM @PE_POC.KNOWLEDGE.DOC_STAGE (PATTERN => '.*\\.pdf') d
--   CROSS JOIN LATERAL (
--     SELECT * FROM TABLE(AI_PARSE_DOCUMENT(
--       BUILD_SCOPED_FILE_URL(@PE_POC.KNOWLEDGE.DOC_STAGE, d.RELATIVE_PATH),
--       'LAYOUT'
--     ))
--   ) p
--   JOIN PE_POC.KNOWLEDGE.SOURCES s
--     ON d.RELATIVE_PATH ILIKE '%' || SPLIT_PART(s.STAGE_PATH, '/', -1);

-- ---------------------------------------------------------------------------
-- Document chunks (for Cortex Search: Engineering Literature)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE DOC_CHUNKS (
    CHUNK_ID VARCHAR NOT NULL DEFAULT UUID_STRING(),
    DOC_ID VARCHAR,
    TITLE VARCHAR,
    DOC_TYPE VARCHAR,
    CHUNK_INDEX NUMBER,
    CHUNK_TEXT VARCHAR,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PAGE_NUMBER NUMBER,
    REFERENCE VARCHAR,
    PRIMARY KEY (CHUNK_ID)
);

-- Chunking logic: ~1000 chars per chunk with 200-char overlap
-- INSERT INTO DOC_CHUNKS (DOC_ID, TITLE, DOC_TYPE, CHUNK_INDEX, CHUNK_TEXT, PAGE_NUMBER, REFERENCE)
-- SELECT
--     p.DOC_ID, s.TITLE, s.DOC_TYPE,
--     p.PAGE_NUMBER AS CHUNK_INDEX,
--     p.PAGE_TEXT AS CHUNK_TEXT,
--     p.PAGE_NUMBER,
--     s.REFERENCE
-- FROM PARSED_DOCUMENTS p
-- JOIN SOURCES s ON p.DOC_ID = s.DOC_ID
-- WHERE LENGTH(p.PAGE_TEXT) > 50;

-- ---------------------------------------------------------------------------
-- Knowledge graph tables
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE EXTRACTION_STAGING (
    DOC_ID VARCHAR,
    DOC_TITLE VARCHAR,
    EXTRACTION_RAW VARIANT,
    EXTRACTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE EXTRACTED_CONCEPTS (
    EXTRACTION_ID VARCHAR DEFAULT UUID_STRING(),
    DOC_ID VARCHAR,
    FILENAME VARCHAR,
    PAGE_RANGE VARCHAR,
    RAW_EXTRACTION VARIANT,
    EXTRACTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE NODES (
    NODE_ID VARCHAR NOT NULL DEFAULT UUID_STRING(),
    NODE_TYPE VARCHAR,
    NAME VARCHAR NOT NULL,
    CANONICAL_NAME VARCHAR,
    DEFINITION VARCHAR,
    PROPERTIES VARIANT,
    NAME_EMBEDDING VECTOR(FLOAT, 1024),
    SOURCE_DOC_ID VARCHAR,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (NODE_ID)
);

CREATE OR REPLACE TABLE EDGES (
    EDGE_ID VARCHAR NOT NULL DEFAULT UUID_STRING(),
    SOURCE_NODE_ID VARCHAR NOT NULL,
    TARGET_NODE_ID VARCHAR NOT NULL,
    EDGE_TYPE VARCHAR,
    METADATA VARIANT,
    SOURCE_DOC_ID VARCHAR,
    VALIDATION_STATUS VARCHAR DEFAULT 'PENDING',
    PRIMARY KEY (EDGE_ID)
);

-- ---------------------------------------------------------------------------
-- Concept profiles view (assembles GraphRAG profiles from nodes + edges)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW CONCEPT_PROFILES AS
WITH outbound_edges AS (
    SELECT
        e.SOURCE_NODE_ID AS node_id,
        src.NAME AS source_name,
        e.EDGE_TYPE,
        tgt.NAME AS target_name,
        e.METADATA:conditions::VARCHAR AS conditions
    FROM EDGES e
    JOIN NODES src ON e.SOURCE_NODE_ID = src.NODE_ID
    JOIN NODES tgt ON e.TARGET_NODE_ID = tgt.NODE_ID
),
inbound_edges AS (
    SELECT
        e.TARGET_NODE_ID AS node_id,
        tgt.NAME AS target_name,
        e.EDGE_TYPE,
        src.NAME AS source_name,
        e.METADATA:conditions::VARCHAR AS conditions
    FROM EDGES e
    JOIN NODES src ON e.SOURCE_NODE_ID = src.NODE_ID
    JOIN NODES tgt ON e.TARGET_NODE_ID = tgt.NODE_ID
),
profiles AS (
    SELECT
        n.NODE_ID, n.NAME, n.NODE_TYPE, n.DEFINITION, n.CANONICAL_NAME,
        n.NAME || ' (' || COALESCE(n.NODE_TYPE, 'CONCEPT') || '). ' ||
        COALESCE(n.DEFINITION, '') || ' ' ||
        COALESCE(
            (SELECT LISTAGG(
                source_name || ' ' || LOWER(REPLACE(EDGE_TYPE, '_', ' ')) || ' ' || target_name ||
                CASE WHEN conditions IS NOT NULL AND conditions != '' THEN ' [' || conditions || ']' ELSE '' END || '.',
                ' '
            ) WITHIN GROUP (ORDER BY EDGE_TYPE)
            FROM outbound_edges oe WHERE oe.node_id = n.NODE_ID),
            ''
        ) || ' ' ||
        COALESCE(
            (SELECT LISTAGG(
                source_name || ' ' || LOWER(REPLACE(EDGE_TYPE, '_', ' ')) || ' ' || target_name ||
                CASE WHEN conditions IS NOT NULL AND conditions != '' THEN ' [' || conditions || ']' ELSE '' END || '.',
                ' '
            ) WITHIN GROUP (ORDER BY EDGE_TYPE)
            FROM inbound_edges ie WHERE ie.node_id = n.NODE_ID),
            ''
        ) AS PROFILE_TEXT
    FROM NODES n
)
SELECT NODE_ID, NAME, NODE_TYPE, DEFINITION, CANONICAL_NAME, PROFILE_TEXT
FROM profiles
WHERE LENGTH(PROFILE_TEXT) > 50;

-- Materialize with source document attribution
CREATE OR REPLACE TABLE CONCEPT_PROFILES_TABLE AS
SELECT
    cp.NODE_ID, cp.NAME, cp.NODE_TYPE, cp.DEFINITION, cp.CANONICAL_NAME, cp.PROFILE_TEXT,
    s.TITLE AS SOURCE_TITLE,
    s.DOC_TYPE AS SOURCE_DOC_TYPE,
    s.REFERENCE AS SOURCE_REFERENCE
FROM CONCEPT_PROFILES cp
JOIN NODES n ON cp.NODE_ID = n.NODE_ID
LEFT JOIN SOURCES s ON n.SOURCE_DOC_ID = s.DOC_ID;

-- ---------------------------------------------------------------------------
-- Concept extraction procedure (LLM-powered)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE EXTRACT_CONCEPTS_SERIAL(MAX_PAGES NUMBER DEFAULT 50)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
import time, re, json
from snowflake.snowpark import Session

def extract_json_from_text(text):
    if not text: return None
    match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
    if match: return match.group(1)
    match = re.search(r'(\{[^{}]*"concepts"[^{}]*\[.*?\].*?\})', text, re.DOTALL)
    if match: return match.group(1)
    text = text.strip()
    if text.startswith('{'): return text
    return None

def main(session: Session, max_pages: int) -> str:
    pages = session.sql(f"""
        SELECT pd.DOC_ID, pd.FILENAME, pd.PAGE_NUMBER, LEFT(pd.PAGE_TEXT, 1500) AS PAGE_TEXT
        FROM PE_POC.KNOWLEDGE.PARSED_DOCUMENTS pd
        JOIN PE_POC.KNOWLEDGE.SOURCES s ON pd.DOC_ID = s.DOC_ID
        WHERE LENGTH(pd.PAGE_TEXT) > 300
        AND s.DOC_TYPE IN ('SPE_PAPER', 'WELL_REPORT', 'PUD')
        ORDER BY pd.FILENAME, pd.PAGE_NUMBER
        LIMIT {max_pages}
    """).collect()
    processed = 0; errors = 0; skipped = 0
    for page in pages:
        doc_id = page['DOC_ID']
        filename = page['FILENAME']
        page_num = page['PAGE_NUMBER']
        text = page['PAGE_TEXT'] or ''
        text_esc = text.replace("\\", "\\\\").replace("'", "''")
        prompt = 'Extract petroleum engineering concepts and relationships as JSON only. Return ONLY the JSON object. Format: {"concepts":[{"name":"","type":"CONCEPT|METHOD|PHENOMENON","definition":""}],"relationships":[{"subject":"","predicate":"CAUSES|INDICATES|USED_FOR|APPLICABLE_WHEN","object":"","conditions":""}]}. Text: ' + text_esc
        prompt_esc = prompt.replace("'", "''")
        try:
            result = session.sql(f"""
                SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b', '{prompt_esc}') AS resp
            """).collect()
            resp = result[0]['RESP'] if result else ''
            json_str = extract_json_from_text(resp)
            if json_str:
                try:
                    json.loads(json_str)
                    json_esc = json_str.replace("\\", "\\\\").replace("'", "''")
                    title_esc = f"{filename} - Page {page_num}".replace("'", "''")
                    session.sql(f"""
                        INSERT INTO PE_POC.KNOWLEDGE.EXTRACTION_STAGING (DOC_ID, DOC_TITLE, EXTRACTION_RAW)
                        SELECT '{doc_id}', '{title_esc}', PARSE_JSON('{json_esc}')
                    """).collect()
                    processed += 1
                except: skipped += 1
            else: skipped += 1
        except Exception as e:
            errors += 1
            if errors > 10:
                return f"Stopped: {processed} ok, {skipped} skipped, {errors} errors. Last: {str(e)[:200]}"
        time.sleep(0.3)
    return f"Done: {processed} extracted, {skipped} skipped, {errors} errors, {len(pages)} total."
$$;

-- ---------------------------------------------------------------------------
-- After running extraction, load nodes and edges from EXTRACTION_STAGING:
-- ---------------------------------------------------------------------------
-- INSERT INTO NODES (NODE_TYPE, NAME, DEFINITION, SOURCE_DOC_ID,
--     NAME_EMBEDDING)
-- SELECT DISTINCT
--     c.value:type::VARCHAR,
--     c.value:name::VARCHAR,
--     c.value:definition::VARCHAR,
--     es.DOC_ID,
--     SNOWFLAKE.CORTEX.EMBED_TEXT_1024('snowflake-arctic-embed-m-v1.5', c.value:name::VARCHAR)
-- FROM EXTRACTION_STAGING es,
--     LATERAL FLATTEN(input => es.EXTRACTION_RAW:concepts) c
-- WHERE c.value:name IS NOT NULL;
--
-- INSERT INTO EDGES (SOURCE_NODE_ID, TARGET_NODE_ID, EDGE_TYPE, METADATA, SOURCE_DOC_ID)
-- SELECT
--     src.NODE_ID, tgt.NODE_ID,
--     r.value:predicate::VARCHAR,
--     OBJECT_CONSTRUCT('conditions', r.value:conditions::VARCHAR),
--     es.DOC_ID
-- FROM EXTRACTION_STAGING es,
--     LATERAL FLATTEN(input => es.EXTRACTION_RAW:relationships) r
-- JOIN NODES src ON UPPER(src.NAME) = UPPER(r.value:subject::VARCHAR)
-- JOIN NODES tgt ON UPPER(tgt.NAME) = UPPER(r.value:object::VARCHAR)
-- WHERE r.value:subject IS NOT NULL AND r.value:object IS NOT NULL;
--
-- Then deduplicate nodes using vector similarity on NAME_EMBEDDING
-- and refresh CONCEPT_PROFILES_TABLE.
