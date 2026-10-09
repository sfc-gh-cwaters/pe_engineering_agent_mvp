# PE_ASSISTANT — Production Engineering AI Advisor

An AI-powered production engineering advisor built on Snowflake Cortex, using the open-source Equinor Volve oil field dataset. The agent combines structured production data, petrophysical reservoir characterization, a knowledge graph of engineering principles, and a technical document corpus to answer questions about well performance, diagnose production issues, and provide engineering recommendations with traceable citations.

## What It Does

Ask natural language questions about oil field production. The agent:

- Retrieves production data (rates, pressures, water cut, GOR) via Cortex Analyst
- Applies diagnostic frameworks from a knowledge graph of petroleum engineering concepts
- Cites specific documents, page numbers, and DOI/SPE references
- Distinguishes what the evidence supports from what it can't confirm

**Example questions:**
- "What is causing the rising water cut in well 15/9-F-14?"
- "Compare the production performance of all Volve wells"
- "Is well 15/9-F-1C showing signs of pressure depletion?"
- "How do you distinguish water coning from channeling?"

## Prerequisites

- Snowflake account with Cortex Agents enabled
- `SYSADMIN` role (or equivalent privileges)
- Cross-region inference enabled (`ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';`)
- `SNOWFLAKE.CORTEX_AGENT_USER` database role granted to your role

## Data

This project uses the **Equinor Volve field** open dataset:

1. **Production data** — Daily and monthly production CSVs from the [Equinor Volve data portal](https://www.equinor.com/energy/volve-data-sharing)
2. **Well logs** — LAS 2.0 petrophysical log files (PHIF, SW, VSH, KLOGH, BVW)
3. **Well header** — NCS wellbore registry from [SODIR FactPages](https://factpages.sodir.no/)
4. **Technical documents** — Volve PUD, well final summary reports, SPE PetroWiki papers, LSU reservoir dynamics textbook (all open/CC licensed)

## Deployment

### Step 1: Create infrastructure

```sql
-- Run setup scripts in order
-- 01: Database, schemas, warehouses, stages, file formats
@setup/01_infrastructure.sql

-- 02: Raw data table definitions
@setup/02_raw_data_tables.sql

-- 03: LAS file parser stored procedure
@setup/03_load_procedures.sql
```

### Step 2: Upload and load data

```sql
-- Upload Volve CSV files
PUT file:///path/to/Volve_production_daily.csv @PE_POC.RAW_VOLVE.DATA_STAGE;
PUT file:///path/to/Volve_production_monthly.csv @PE_POC.RAW_VOLVE.DATA_STAGE;
PUT file:///path/to/wellbore_exploration_all.csv @PE_POC.RAW_VOLVE.DATA_STAGE;

-- Load CSVs
COPY INTO PE_POC.RAW_VOLVE.PRODUCTION_DAILY
  FROM @PE_POC.RAW_VOLVE.DATA_STAGE/Volve_production_daily.csv
  FILE_FORMAT = PE_POC.RAW_VOLVE.CSV_FORMAT;

COPY INTO PE_POC.RAW_VOLVE.PRODUCTION_MONTHLY
  FROM @PE_POC.RAW_VOLVE.DATA_STAGE/Volve_production_monthly.csv
  FILE_FORMAT = PE_POC.RAW_VOLVE.CSV_FORMAT;

COPY INTO PE_POC.RAW_VOLVE.WELL_HEADER
  FROM @PE_POC.RAW_VOLVE.DATA_STAGE/wellbore_exploration_all.csv
  FILE_FORMAT = PE_POC.RAW_VOLVE.CSV_FORMAT;

-- Upload and load LAS files
PUT file:///path/to/*.LAS @PE_POC.RAW_VOLVE.DATA_STAGE;
CALL PE_POC.RAW_VOLVE.LOAD_LAS_FILES();

-- Upload PDFs to knowledge stage
PUT file:///path/to/*.pdf @PE_POC.RAW_VOLVE.DATA_STAGE;
COPY FILES INTO @PE_POC.KNOWLEDGE.DOC_STAGE
  FROM @PE_POC.RAW_VOLVE.DATA_STAGE PATTERN='.*\\.pdf';
```

### Step 3: Build curated layer

```sql
-- 04: Curated tables, views, domain knowledge
@setup/04_curated_layer.sql

-- Seed domain knowledge entries (synonyms, business rules, metric formulas)
-- See the PRODUCTION_DOMAIN_KNOWLEDGE table in 04_curated_layer.sql
```

### Step 4: Build knowledge pipeline

```sql
-- 05: Document parsing, chunking, knowledge graph extraction
@setup/05_knowledge_pipeline.sql

-- Parse documents (requires PDFs in DOC_STAGE)
-- Run extraction procedure:
CALL PE_POC.KNOWLEDGE.EXTRACT_CONCEPTS_SERIAL(500);

-- Load nodes and edges from extraction staging (see comments in script)
-- Refresh CONCEPT_PROFILES_TABLE
```

### Step 5: Create search services and agent

```sql
-- 06: Cortex Search services
@setup/06_cortex_search_services.sql

-- 07: Semantic view
@setup/07_semantic_view.sql

-- 08: Agent
@setup/08_agent.sql
```

### Step 6: Test

Open Snowflake Intelligence (CoWork) and select "Production Engineering Advisor", or test via SQL:

```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'PE_POC.AGENTS.PE_ASSISTANT',
    '{"messages":[{"role":"user","content":[{"type":"text","text":"What is the cumulative oil production for each Volve well?"}]}]}',
    TRUE
);
```

## Architecture

The agent uses 4 tools:

| Tool | Type | Purpose |
|---|---|---|
| **domain_knowledge** | Cortex Search | Resolves petroleum jargon to column names |
| **production_analyst** | Cortex Analyst | Natural language → SQL over production data |
| **engineering_principles** | Cortex Search | Diagnostic concepts from knowledge graph |
| **engineering_literature** | Cortex Search | Document passages with page-level citations |

See [pe_assistant_architecture.md](pe_assistant_architecture.md) for the full design document.

## Project Structure

```
pe-assistant/
├── README.md                              This file
├── pe_assistant_architecture.md           Comprehensive design document
├── setup/
│   ├── 01_infrastructure.sql              Database, schemas, warehouses, stages
│   ├── 02_raw_data_tables.sql             RAW_VOLVE table definitions
│   ├── 03_load_procedures.sql             LAS file parser procedure
│   ├── 04_curated_layer.sql               Curated views, domain knowledge
│   ├── 05_knowledge_pipeline.sql          Document parsing, knowledge graph
│   ├── 06_cortex_search_services.sql      Cortex Search services
│   ├── 07_semantic_view.sql               Semantic view + VQRs
│   └── 08_agent.sql                       CREATE AGENT
└── cortex_project/
    ├── cortex-project.yaml                Cortex project manifest
    ├── PE_ASSISTANT.agent.yaml            Agent YAML spec
    └── PRODUCTION_PERFORMANCE.sv.yaml     Semantic view YAML spec
```

## License

- **Volve data**: Equinor open data — CC BY-NC-SA 4.0
- **SPE PetroWiki content**: Society of Petroleum Engineers — open access
- **LSU Reservoir Dynamics textbook**: CC BY
- **This project code**: MIT
