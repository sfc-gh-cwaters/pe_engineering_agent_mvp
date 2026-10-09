# PE_ASSISTANT — Production Engineering AI Advisor

**Volve Oil Field (Equinor, 2008–2016) | Snowflake Cortex**

| | |
|---|---|
| **Agent** | `PE_POC.AGENTS.PE_ASSISTANT` |
| **Platform** | 100% Snowflake-native (Cortex Agent, Cortex Analyst, Cortex Search) |
| **Access** | Snowflake Intelligence (CoWork) or Cortex Agents REST API |
| **Dataset** | Equinor Volve field — open-source North Sea production data |

---

## 1. Purpose and Scope

PE_ASSISTANT is an AI-powered production engineering advisor built on Snowflake Cortex. It combines structured production data, petrophysical reservoir characterization, a knowledge graph of petroleum engineering principles, and a technical document corpus to answer questions about well performance, diagnose production issues, and provide engineering recommendations grounded in actual field data and source citations.

### Target Users

Production engineers, reservoir engineers, and petroleum engineering teams who need to:

- Access production performance data through natural language without writing SQL
- Cross-reference production trends with reservoir properties
- Apply engineering diagnostic frameworks to observed well behavior
- Get structured analysis with traceable citations (document, page number, DOI/SPE reference)

### Capabilities

| Capability | Example Question |
|---|---|
| Production data retrieval | "What is the cumulative oil for well F-12?" |
| Trend analysis | "How has water cut evolved for F-14?" |
| Reservoir characterization | "Compare porosity and permeability across wells" |
| Cross-domain correlation | "Do reservoir properties explain why F-12 outperforms F-14?" |
| Engineering diagnostics | "Is F-1C showing signs of pressure depletion?" |
| Mechanism identification | "What indicators distinguish coning from channeling?" |
| Literature reference | "What does the PUD say about drainage strategy?" |

### Boundaries

- Provides analysis and advisory; does not make operational decisions
- Uses historical Volve data (2007–2016); does not access real-time data
- Does not perform numerical simulation (reservoir sim, finite-difference modeling)
- Does not know undocumented field context (control room events, verbal handoffs)

---

## 2. Architecture

### System Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     USER (Production Engineer)                      │
│              Asks question via CoWork chat interface                 │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PE_ASSISTANT (Cortex Agent)                       │
│                                                                     │
│  Orchestration: Vocabulary → Data → Principles → Literature →       │
│                 Evidence Gate → Synthesis                            │
│                                                                     │
├──────────────┬──────────────┬──────────────────┬────────────────────┤
│   Tool 1     │   Tool 2     │      Tool 3      │      Tool 4       │
│              │              │                  │                     │
│  Cortex      │  Cortex      │  Cortex Search   │  Cortex Search     │
│  Search      │  Analyst     │  (Literature)    │  (Principles)      │
│  (Domain     │              │                  │                     │
│  Knowledge)  │  Natural     │  1,540 document  │  471 concept       │
│              │  language    │  chunks from     │  profiles with     │
│  75 domain   │  → SQL       │  10 source docs  │  diagnostic        │
│  vocabulary  │  queries     │                  │  frameworks        │
│  entries     │              │                  │                     │
├──────────────┼──────────────┼──────────────────┼────────────────────┤
│              │              │                  │                     │
│  PRODUCTION_ │  Semantic    │  DOC_CHUNKS      │  CONCEPT_PROFILES  │
│  DOMAIN_     │  View:       │  table           │  _TABLE            │
│  KNOWLEDGE   │  PRODUCTION_ │  + PAGE_NUMBER   │  (knowledge graph) │
│  table       │  PERFORMANCE │  + REFERENCE     │  + SOURCE_TITLE    │
│              │              │                  │  + SOURCE_REFERENCE │
│  Synonyms,   │  ┌────────┐  │  ┌────────────┐  │                     │
│  business    │  │PROD    │  │  │ Volve PUD  │  │  ┌────────┐ ┌────┐ │
│  rules,      │  │DAILY   │  │  │ Well Rpts  │  │  │ NODES  │─│EDGE│ │
│  metric      │  ├────────┤  │  │ SPE Papers │  │  │ (487)  │ │(762│ │
│  formulas    │  │PETRO   │  │  │ Textbook   │  │  └────────┘ └────┘ │
│              │  │PHYSICS │  │  └────────────┘  │                     │
│              │  └────────┘  │                  │                     │
└──────────────┴──────────────┴──────────────────┴────────────────────┘
```

### Component Summary

| Component | Type | Location | Role |
|---|---|---|---|
| PE_ASSISTANT | Cortex Agent | `PE_POC.AGENTS.PE_ASSISTANT` | Orchestrator — classifies questions, selects tools, synthesizes answers |
| Domain Knowledge | Cortex Search Service | `PE_POC.CURATED.PRODUCTION_CONTEXT_SEARCH` | Resolves petroleum jargon to column names, retrieves business rules and metric formulas |
| Production Analyst | Cortex Analyst + Semantic View | `PE_POC.CURATED.PRODUCTION_PERFORMANCE` | Natural language to SQL against production and petrophysics data |
| Engineering Literature | Cortex Search Service | `PE_POC.KNOWLEDGE.ENGINEERING_LITERATURE` | Retrieves document passages with page numbers and DOI/SPE references |
| Engineering Principles | Cortex Search Service | `PE_POC.KNOWLEDGE.ENGINEERING_PRINCIPLES` | Retrieves structured diagnostic reasoning frameworks with source attribution |

---

## 3. Agent Configuration

The agent is defined declaratively in YAML (`PE_ASSISTANT.agent.yaml`) and deployed to Snowflake via `CREATE AGENT` or the Cortex project framework.

**Orchestration model:** Auto (Snowflake-managed model selection)

**System instructions** direct the agent to act as a production engineering advisor with direct access to production data, domain vocabulary, engineering principles, and technical literature. The agent gathers evidence, applies engineering principles only when the evidence supports them, and writes cited answers.

**Orchestration instructions** enforce a principled diagnostic workflow:

1. **Classify the question** — factual, conceptual, or diagnostic/prescriptive
2. **Vocabulary resolution** — search `domain_knowledge` to resolve jargon, synonyms, and business rules before any data query
3. **Gather evidence** — query `production_analyst` using resolved vocabulary (data before hypotheses)
4. **Retrieve engineering concepts** — search `engineering_principles` for candidate mechanisms and diagnostic criteria
5. **Evidence gate** — check each candidate against the data: APPLICABLE, RULED OUT, DIFFERENTIAL, or UNTESTED
6. **Synthesis** — search `engineering_literature` for citations; apply only those principles whose conditions are met; include a mandatory References table

**Response instructions** require structured engineering analysis with traceable citations:

1. Conclusion or differential (2–3 sentences)
2. Evidence used — data values with units, grain, time range, sources
3. Applied concepts — each with the criterion met and a citation
4. What was ruled out and what couldn't be tested
5. What evidence would resolve remaining uncertainty
6. Recommendations or advisory statement
7. **References table** — Source, Type, Page, Reference (DOI/SPE), Context Used

---

## 4. Tool Specifications

### Tool 1: Domain Knowledge (Cortex Search)

Resolves petroleum jargon into correct column names and retrieves business rules, unit conventions, and metric formulas before any data query. This mandatory first step ensures the agent maps user terminology (e.g., "WC", "DHP", "water cut") to the correct semantic view columns.

**Search service:** `PE_POC.CURATED.PRODUCTION_CONTEXT_SEARCH`
**Search column:** `CONTEXT_PROFILE`
**Attributes:** `ENTRY_TYPE`, `SUB_DOMAIN`, `DOMAIN_NAME`, `SEMANTIC_VIEWS`
**Source table:** `PE_POC.CURATED.PRODUCTION_DOMAIN_KNOWLEDGE` (75 active entries)
**Embedding model:** `snowflake-arctic-embed-m-v1.5`
**Target lag:** 1 minute
**Max results per query:** 10

**Entry types:**

| Entry Type | Content |
|---|---|
| COLUMN_DESC | Column descriptions with units and usage guidance |
| TABLE_DESC | Table descriptions with grain and join information |
| SYNONYM | Jargon-to-column mappings (WC→WATER_CUT, DHP→AVG_DHP_BARA) |
| METRIC | Derived metric formulas (cumulative oil, PI, VRR, drawdown) |
| BUSINESS_RULE | Mandatory filters, unit conventions, data quality notes |

### Tool 2: Production Analyst (Cortex Analyst + Semantic View)

Translates natural language into SQL queries against production and petrophysics data using the `PRODUCTION_PERFORMANCE` semantic view.

**Semantic view:** `PE_POC.CURATED.PRODUCTION_PERFORMANCE`
**Execution environment:** Warehouse `WH_TEST`

**Underlying tables:**

| Table | Schema | Records | Content |
|---|---|---|---|
| `PRODUCTION_DAILY` | CURATED | 15,634 | Daily oil/gas/water rates, pressures, temperatures, choke, water cut, GOR, drawdown, well status (7 wellbores) |
| `PETROPHYSICS_LOGS_TABLE` | CURATED | 34,404 | Per-depth porosity, permeability, water saturation, shale volume, HC saturation, net flag (5 wells) |
| `PETROPHYSICS_WELL_SUMMARY_TABLE` | CURATED | 5 | Per-well net-to-gross, average porosity, permeability, and saturation in net pay |

**Verified Queries (VQRs):**

1. Daily oil, gas, and water production by well over time for producing wells
2. Cumulative production correlated with reservoir properties (porosity, permeability)
3. Pressure drawdown trend and its relationship to oil production rate
4. Average production performance for each producing well

### Tool 3: Engineering Literature (Cortex Search)

Searches 1,540 text chunks (~1,000 characters each, 200-character overlap) extracted from 10 source documents. Results include page-level citations and formal references.

**Search service:** `PE_POC.KNOWLEDGE.ENGINEERING_LITERATURE`
**Search column:** `CHUNK_TEXT`
**Attributes:** `TITLE`, `DOC_TYPE`, `PAGE_NUMBER`, `REFERENCE`
**Embedding model:** `snowflake-arctic-embed-m-v1.5`
**Target lag:** 1 day
**Max results per query:** 5

### Tool 4: Engineering Principles (Cortex Search + Knowledge Graph)

Searches structured concept profiles derived from a knowledge graph. Each profile includes definition, applicability conditions, diagnostic indicators, related concepts, and source document attribution.

**Search service:** `PE_POC.KNOWLEDGE.ENGINEERING_PRINCIPLES`
**Search column:** `PROFILE_TEXT`
**Attributes:** `NAME`, `NODE_TYPE`, `SOURCE_TITLE`, `SOURCE_DOC_TYPE`, `SOURCE_REFERENCE`
**Embedding model:** `snowflake-arctic-embed-m-v1.5`
**Target lag:** 1 day
**Max results per query:** 5

---

## 5. Knowledge Graph

The knowledge graph encodes petroleum engineering concepts and their relationships, extracted from the same 10 source documents used for the literature corpus. It provides structured diagnostic reasoning frameworks rather than raw text fragments.

### Construction Pipeline

1. **Document parsing** — 10 PDFs processed with `AI_PARSE_DOCUMENT`, producing 459 page-level text records
2. **Chunking** — parsed text split into 1,540 overlapping chunks for the literature corpus
3. **Concept extraction** — LLM-powered extraction (llama3.1-8b via `CORTEX.COMPLETE`) identifies concepts and relationships from each page
4. **Entity resolution** — duplicate concepts merged using vector similarity on `NAME_EMBEDDING` (1024-dimensional vectors from `snowflake-arctic-embed-m-v1.5`), reducing raw extractions to 487 canonical nodes
5. **Profile generation** — `CONCEPT_PROFILES` view assembles per-node text combining name, type, definition, and all inbound/outbound relationships as natural language sentences; materialized to `CONCEPT_PROFILES_TABLE` (471 profiles) with source document attribution

### Graph Statistics

| Metric | Count |
|---|---|
| Nodes | 487 |
| Edges | 762 |
| Concept profiles (materialized) | 471 |
| Source documents | 10 |

### Node Types

| Node Type | Count | Description |
|---|---|---|
| PARAMETER | 248 | Measurable quantities (pressure, rate, saturation, etc.) |
| PHENOMENON | 153 | Observable behaviors (coning, channeling, depletion, etc.) |
| METHOD | 57 | Engineering techniques (decline analysis, material balance, etc.) |
| DIAGNOSTIC | 7 | Diagnostic frameworks and criteria |
| Other | 22 | Persons, equations, locations, properties |

### Relationship Types (Top 5)

| Relationship | Count | Example |
|---|---|---|
| INDICATES | 194 | "Rising WOR indicates water coning" |
| USED_FOR | 189 | "Decline curve analysis is used for production forecasting" |
| CAUSES | 99 | "Pressure depletion causes GOR increase" |
| APPLICABLE_WHEN | 80 | "Coning diagnosis applicable when WOR rises with stable GOR" |
| MITIGATED_BY | 48 | "Coning mitigated by rate reduction" |

### Profile Example

> "Water coning (PHENOMENON). A type of coning where bottomwater infiltrates the perforation zone in the near-wellbore area and reduces oil production. WOC indicates Water coning [the point at which water and oil are in contact]. Critical Oil Rate indicates Water coning [when the rate of oil production is below a certain threshold]."

---

## 6. Citation Traceability

Every answer that uses engineering knowledge includes a mandatory **References table** with traceable citations.

### What the agent cites

| Source Tool | Available Citation Metadata |
|---|---|
| Engineering Literature | `TITLE` (document name), `DOC_TYPE` (PUD/WELL_REPORT/SPE_PAPER/TEXTBOOK), `PAGE_NUMBER` (source page), `REFERENCE` (DOI, SPE paper number) |
| Engineering Principles | `NAME` (concept name), `SOURCE_TITLE` (document the concept was extracted from), `SOURCE_DOC_TYPE`, `SOURCE_REFERENCE` (DOI/SPE) |

### Example References table

| Source | Type | Page | Reference | Context Used |
|---|---|---|---|---|
| Water and Gas Coning | SPE_PAPER | 1 | DOI: 10.2118/PW1061 | Coning definition, rate-sensitivity criterion |
| Water and Gas Coning | SPE_PAPER | 4 | DOI: 10.2118/PW1061 | Critical rate formula (Chaperon method) |
| Volve PUD | PUD | 22 | Equinor Volve PUD, Licence 046 | Drainage strategy, waterflood description |
| Water coning (concept) | Engineering principle | — | Derived from SPE PW-1061 | Diagnostic indicators and applicability conditions |

### How it works

- **DOC_CHUNKS** stores `PAGE_NUMBER` mapped from `PARSED_DOCUMENTS` (87% exact match via text containment, 13% estimated from chunk index)
- **SOURCES** stores `REFERENCE` with DOI/SPE identifiers for all 10 documents
- **CONCEPT_PROFILES_TABLE** stores `SOURCE_TITLE`, `SOURCE_DOC_TYPE`, `SOURCE_REFERENCE` joined from `NODES` → `SOURCES`
- The Cortex Search services expose these as attributes, and the agent's response instructions mandate their inclusion in every answer

---

## 7. Data Sources

### Production Data (Volve Field, Equinor)

The Volve field operated from 2008 to 2016 on the Norwegian Continental Shelf. Equinor released the complete dataset as open-source.

**Production coverage by wellbore:**

| Wellbore | First Date | Last Date | Records | Type |
|---|---|---|---|---|
| 15/9-F-1 C | 2014-04-07 | 2016-04-21 | 746 | Oil Producer |
| 15/9-F-11 | 2013-07-08 | 2016-09-17 | 1,165 | Oil Producer |
| 15/9-F-12 | 2008-02-12 | 2016-09-17 | 3,056 | Oil Producer |
| 15/9-F-14 | 2008-02-12 | 2016-09-17 | 3,056 | Oil Producer |
| 15/9-F-15 D | 2014-01-12 | 2016-09-17 | 978 | Oil Producer |
| 15/9-F-4 | 2007-09-01 | 2016-12-01 | 3,327 | Water Injector |
| 15/9-F-5 | 2007-09-01 | 2016-09-18 | 3,306 | Oil Producer |

### Knowledge Sources

| Document | Type | Reference |
|---|---|---|
| Volve Plan for Utility and Development | PUD | Equinor Volve PUD, Licence 046, Feb 2005 |
| Well Summary F-1 | Well Report | Equinor Volve Well Final Summary |
| Well Summary F-9 | Well Report | Equinor Volve Well Final Summary |
| Well Summary F-12 | Well Report | Equinor Volve Well Final Summary |
| Well Summary F-14 | Well Report | Equinor Volve Well Final Summary |
| Petroleum Reservoir Dynamics | Textbook | LSU Open Textbook (CC BY) |
| Production Forecasting — DCA | SPE Paper | DOI: 10.2118/28628-PA |
| Solution Gas Drive Reservoirs | SPE Paper | SPE PetroWiki |
| Water Flooding | SPE Paper | SPE PetroWiki |
| Water and Gas Coning | SPE Paper | DOI: 10.2118/PW1061 |

---

## 8. Database Schema Layout

**Database:** `PE_POC`

### RAW_VOLVE Schema (Source Data)

| Object | Type | Records | Purpose |
|---|---|---|---|
| `PRODUCTION_DAILY` | Table (transient) | 15,634 | Raw daily production records |
| `PRODUCTION_MONTHLY` | Table (transient) | 527 | Monthly aggregates |
| `WELL_HEADER` | Table (transient) | 9,807 | Full NCS wellbore registry |
| `LAS_HEADERS` | Table | 5 | Petrophysical file metadata |
| `LAS_CURVES` | Table | 42 | Curve definitions per file |
| `LAS_LOG_DATA` | Table | 267,282 | Normalized log measurements |
| `DATA_STAGE` | Internal Stage | — | Production CSVs, well header CSV, LAS files, PDFs |

### CURATED Schema (Analytics-Ready)

| Object | Type | Records | Purpose |
|---|---|---|---|
| `PRODUCTION_DAILY` | Table | 15,634 | Curated daily production with derived columns |
| `PETROPHYSICS_LOGS_TABLE` | Table | 34,404 | Pivoted log data per depth |
| `PETROPHYSICS_WELL_SUMMARY_TABLE` | Table | 5 | Per-well reservoir property averages |
| `WELL_HEADER` | Table | 7 | Curated well header for Volve production wells |
| `PRODUCTION_DOMAIN_KNOWLEDGE` | Table | 75 | Vocabulary entries for the domain knowledge tool |
| `PRODUCTION_PERFORMANCE` | Semantic View | — | 3 tables, 4 VQRs, joined on WELLBORE_NAME |
| `PRODUCTION_CONTEXT_SEARCH` | Cortex Search Service | 75 rows | Domain vocabulary search |

### KNOWLEDGE Schema (Knowledge Graph + Document Corpus)

| Object | Type | Records | Purpose |
|---|---|---|---|
| `SOURCES` | Table | 10 | Document registry with DOI/SPE references |
| `PARSED_DOCUMENTS` | Table | 459 | Page-level text from AI_PARSE_DOCUMENT |
| `DOC_CHUNKS` | Table | 1,540 | Chunks with page numbers and references |
| `NODES` | Table | 487 | Deduplicated engineering concepts |
| `EDGES` | Table | 762 | Typed relationships between nodes |
| `CONCEPT_PROFILES_TABLE` | Table | 471 | Materialized profiles with source attribution |
| `ENGINEERING_LITERATURE` | Cortex Search Service | 1,540 rows | Document corpus search |
| `ENGINEERING_PRINCIPLES` | Cortex Search Service | 471 rows | Concept profile search |

### AGENTS Schema

| Object | Type | Purpose |
|---|---|---|
| `PE_ASSISTANT` | Cortex Agent | Production engineering advisor (4 tools) |
| `PE_ASSISTANT_EVAL_DATA` | Table (20 rows) | Evaluation dataset |
| `EVAL_CONFIG_STAGE` | Internal Stage | Evaluation configuration artifacts |

---

## 9. Diagnostic Workflow

### Step-by-Step Process

**Step 1: Classify the Question.** The agent determines whether the question is factual (data only), conceptual (engineering knowledge only), or diagnostic (data + engineering interpretation).

**Step 1a: Resolve Vocabulary.** The agent searches domain_knowledge to map user terminology to correct column names, units, and business rules.

**Step 2: Gather Evidence.** The agent queries production_analyst for field data using the resolved vocabulary. Data is gathered before forming any engineering hypotheses.

**Step 3: Retrieve Engineering Concepts.** The agent searches engineering_principles for candidate mechanisms with applicability conditions, discriminating observations, and excluding criteria.

**Step 4: Evidence Gate.** For each candidate mechanism, the agent checks against the data:
- **APPLICABLE** — all required conditions met (apply it, cite the source)
- **RULED OUT** — an excluding condition is met
- **DIFFERENTIAL** — two candidates can't be separated with available evidence
- **UNTESTED** — required evidence is missing

**Step 5: Gather Literature Support.** The agent searches engineering_literature for detailed citations supporting the applied concepts.

**Step 6: Synthesize.** The agent writes the structured response with data, applied concepts, ruled-out items, and a mandatory References table with page numbers and DOI/SPE citations.

### Workflow Variations by Question Type

| Question Type | Steps Used | Typical Latency |
|---|---|---|
| Simple data lookup | 1 → 1a → 2 → 6 | 10–20 seconds |
| Trend analysis | 1 → 1a → 2 → 6 | 20–40 seconds |
| Cross-domain correlation | 1 → 1a → 2 → 3 → 5 → 6 | 30–60 seconds |
| Full diagnostic | 1 → 1a → 2 → 3 → 4 → 5 → 6 | 45–90 seconds |

---

## 10. Design Rationale

### Why Four Separate Tools?

Each tool serves a different cognitive function in engineering reasoning:

| Tool | Cognitive Function | Analogy |
|---|---|---|
| Domain Knowledge | Vocabulary resolution — "What does this term map to?" | Consulting the field glossary before opening the database |
| Production Analyst | Fact retrieval — "What do the numbers say?" | Opening your production database |
| Engineering Literature | Context retrieval — "What are the details?" | Reading the well file or a technical paper |
| Engineering Principles | Framework retrieval — "What could explain this?" | Consulting a diagnostic checklist |

Merging them into a single search would dilute retrieval quality. A search for "water coning" would return both diagnostic criteria and unrelated paragraphs about completion depths.

### Why a Knowledge Graph Instead of Plain Document Search?

Standard document search (RAG) returns text fragments containing the search terms. The knowledge graph adds a structured reasoning layer:

- **Plain RAG:** "...water coning occurs when viscous forces exceed gravity..." (a definition fragment)
- **Knowledge graph profile:** the definition + applicability conditions + diagnostic indicators + what to distinguish it from + related concepts

The agent receives a complete diagnostic framework, not just a vocabulary definition.

### Orchestration Philosophy: Data Before Hypotheses

1. Resolve terminology first (what column is "water cut"?)
2. Gather the evidence before forming hypotheses
3. Retrieve the diagnostic framework to interpret the evidence
4. Check the data against the framework — apply only what the evidence supports
5. Always state what was ruled out and what couldn't be tested

---

## 11. Evaluation

The agent is evaluated using Snowflake's built-in AI evaluation framework with a dataset of 20 production engineering questions. Evaluation has been conducted across 6 iterative rounds.

### Current Metrics

| Metric | Score |
|---|---|
| Answer Correctness | 0.83 |
| Tool Execution Accuracy | 0.97 |

### Score Distribution (Answer Correctness)

| Score | Count |
|---|---|
| 1.0 (Perfect) | 14 questions |
| 0.67 (Partial) | 4 questions |
| 0.33 (Low) | 2 questions |
| 0.0 (Failed) | 0 questions |

---

## 12. Access and Usage

| Item | Detail |
|---|---|
| **Interface** | Snowflake Intelligence (CoWork) — select "Production Engineering Advisor" |
| **Requirements** | Snowflake account with default role and warehouse; CORTEX_AGENT_USER database role |
| **Response time** | 10–20s for data lookups; 45–90s for full diagnostics |
| **Agent location** | `PE_POC.AGENTS.PE_ASSISTANT` |
| **Domain knowledge** | `PE_POC.CURATED.PRODUCTION_CONTEXT_SEARCH` |
| **Semantic view** | `PE_POC.CURATED.PRODUCTION_PERFORMANCE` |
| **Literature search** | `PE_POC.KNOWLEDGE.ENGINEERING_LITERATURE` |
| **Principles search** | `PE_POC.KNOWLEDGE.ENGINEERING_PRINCIPLES` |

---

## Appendix A: Deployment Structure

```
pe-assistant/
├── README.md                              Quick start guide
├── pe_assistant_architecture.md           This document
├── setup/
│   ├── 01_infrastructure.sql              Database, schemas, warehouses, stages
│   ├── 02_raw_data_tables.sql             RAW_VOLVE table definitions
│   ├── 03_load_procedures.sql             LAS file parser procedure
│   ├── 04_curated_layer.sql               Views, materialized tables, domain knowledge
│   ├── 05_knowledge_pipeline.sql          Document parsing, chunking, knowledge graph
│   ├── 06_cortex_search_services.sql      All 3 Cortex Search services
│   ├── 07_semantic_view.sql               PRODUCTION_PERFORMANCE semantic view
│   └── 08_agent.sql                       CREATE AGENT PE_ASSISTANT
└── cortex_project/
    ├── cortex-project.yaml                Project manifest
    ├── PE_ASSISTANT.agent.yaml            Agent specification (YAML)
    └── PRODUCTION_PERFORMANCE.sv.yaml     Semantic view specification (YAML)
```

## Appendix B: Data Lineage

```
Equinor Open Data (Volve)
    │
    ├─ Production CSVs ──→ RAW_VOLVE.PRODUCTION_DAILY ──→ CURATED.PRODUCTION_DAILY ─┐
    │                      RAW_VOLVE.PRODUCTION_MONTHLY                              │
    │                      RAW_VOLVE.WELL_HEADER ──→ CURATED.WELL_HEADER             │
    │                                                                                 │
    ├─ LAS Files ────────→ RAW_VOLVE.LAS_HEADERS                                    │
    │                      RAW_VOLVE.LAS_CURVES                                      ├→ Semantic View
    │                      RAW_VOLVE.LAS_LOG_DATA ──→ CURATED.PETROPHYSICS_LOGS ─┐   │  PRODUCTION_
    │                                                  CURATED.PETRO_LOGS_TABLE   │   │  PERFORMANCE
    │                                                  CURATED.PETRO_WELL_SUMMARY ┘   │
    │                                                                                 │
    │  Domain Knowledge ─→ CURATED.PRODUCTION_DOMAIN_KNOWLEDGE ──→ Cortex Search:     │
    │  (synonyms, rules,     (75 entries)                          PRODUCTION_         │
    │   metric formulas)                                           CONTEXT_SEARCH      │
    │                                                                                 │
    ├─ PDFs ─────────────→ KNOWLEDGE.PARSED_DOCUMENTS                                │
    │  (PUD, well reports,   │                                                        │
    │   SPE papers,          ├→ KNOWLEDGE.DOC_CHUNKS ──→ Cortex Search:
    │   textbook)            │  (+ PAGE_NUMBER,           ENGINEERING_LITERATURE
    │                        │   + REFERENCE)
    │                        │
    │                        └→ KNOWLEDGE.EXTRACTION_STAGING
    │                             │
    │                             ├→ KNOWLEDGE.NODES ─┐
    │                             └→ KNOWLEDGE.EDGES ─┤
    │                                                  │
    │                                                  └→ KNOWLEDGE.CONCEPT_PROFILES_TABLE
    │                                                     (+ SOURCE_TITLE, SOURCE_REFERENCE)
    │                                                       │
    │                                                       └→ Cortex Search:
    │                                                          ENGINEERING_PRINCIPLES
    │
    └─ All paths feed into PE_ASSISTANT (Cortex Agent)
```
