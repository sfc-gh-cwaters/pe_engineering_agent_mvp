-- =============================================================================
-- PE_ASSISTANT: Production Engineering AI Advisor
-- Script 03: Load Procedures — LAS file parser
-- =============================================================================
-- Run after: 02_raw_data_tables.sql + uploading data files to DATA_STAGE
-- =============================================================================

USE SCHEMA PE_POC.RAW_VOLVE;

-- LAS 2.0 file parser: reads LAS files from stage, extracts headers,
-- curve definitions, and log data into the LAS_* tables.
-- Usage: CALL LOAD_LAS_FILES();
CREATE OR REPLACE PROCEDURE LOAD_LAS_FILES(
    STAGE_PATH VARCHAR DEFAULT '@PE_POC.RAW_VOLVE.DATA_STAGE',
    FILE_PATTERN VARCHAR DEFAULT '.*\\.LAS'
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
import re
import json
from snowflake.snowpark import Session

def parse_las_content(lines):
    sections = {'version': {}, 'well': {}, 'curves': [], 'parameters': {}, 'other': '', 'data_start_line': None}
    current_section = None
    for i, raw_line in enumerate(lines):
        line = raw_line.rstrip('\r\n') if raw_line else ''
        if not line or line.strip() == '' or line.strip() == 'None':
            continue
        if line.strip().startswith('#'):
            continue
        if line.startswith('~V') or line.startswith('~v'):
            current_section = 'version'; continue
        elif line.startswith('~W') or line.startswith('~w'):
            current_section = 'well'; continue
        elif line.startswith('~C') or line.startswith('~c'):
            current_section = 'curve'; continue
        elif line.startswith('~P') or line.startswith('~p'):
            current_section = 'parameter'; continue
        elif line.startswith('~O') or line.startswith('~o'):
            current_section = 'other'; continue
        elif line.startswith('~A') or line.startswith('~a'):
            sections['data_start_line'] = i + 1
            break
        if current_section == 'version':
            parsed = parse_mnemonic_line(line)
            if parsed: sections['version'][parsed['mnemonic']] = parsed
        elif current_section == 'well':
            parsed = parse_mnemonic_line(line)
            if parsed: sections['well'][parsed['mnemonic']] = parsed
        elif current_section == 'curve':
            parsed = parse_curve_line(line)
            if parsed: sections['curves'].append(parsed)
        elif current_section == 'parameter':
            parsed = parse_mnemonic_line(line)
            if parsed: sections['parameters'][parsed['mnemonic']] = parsed
        elif current_section == 'other':
            sections['other'] += line + '\n'
    return sections

def parse_mnemonic_line(line):
    match = re.match(r'\s*(\w+)\s*\.\s*(\S*)\s+(.*?)\s*:\s*(.*)', line)
    if match:
        return {'mnemonic': match.group(1).upper().strip(), 'unit': match.group(2).strip(),
                'value': match.group(3).strip(), 'description': match.group(4).strip()}
    match2 = re.match(r'\s*(\w+)\s*\.\s*(.*?)\s*:\s*(.*)', line)
    if match2:
        return {'mnemonic': match2.group(1).upper().strip(), 'unit': '',
                'value': match2.group(2).strip(), 'description': match2.group(3).strip()}
    return None

def parse_curve_line(line):
    match = re.match(r'\s*(\S+)\s*\.\s*(\S*)\s+(.*?)\s*:\s*(.*)', line)
    if match:
        return {'mnemonic': match.group(1).upper().strip(), 'unit': match.group(2).strip(),
                'api_code': match.group(3).strip(), 'description': match.group(4).strip()}
    return None

def get_well_value(well_dict, keys):
    for k in keys:
        if k in well_dict:
            val = well_dict[k]['value']
            if val and val.upper() not in ('UNKNOWN', ''):
                return val
    return None

def safe_float(val):
    if val is None: return None
    try: return float(val)
    except (ValueError, TypeError): return None

def escape_sql(val):
    if val is None: return None
    return val.replace("'", "''").replace("\\", "\\\\")

def main(session: Session, stage_path: str, file_pattern: str) -> str:
    files_df = session.sql(f"LIST {stage_path} PATTERN='{file_pattern}'").collect()
    if not files_df:
        return "No LAS files found matching pattern."
    files_loaded = 0
    errors = []
    for file_row in files_df:
        filename = file_row['name']
        short_name = filename.split('/')[-1] if '/' in filename else filename
        try:
            lines_df = session.sql(f"""
                SELECT $1 AS line FROM {stage_path}/{short_name}
                (FILE_FORMAT => 'PE_POC.RAW_VOLVE.LAS_RAW_FORMAT')
                ORDER BY METADATA$FILE_ROW_NUMBER
            """).collect()
            lines = [row['LINE'] if row['LINE'] else '' for row in lines_df]
            sections = parse_las_content(lines)
            well = sections['well']
            version = sections['version']
            curves = sections['curves']
            params = sections['parameters']
            null_value = safe_float(get_well_value(well, ['NULL']))
            if null_value is None: null_value = -999.25
            strt = safe_float(get_well_value(well, ['STRT']))
            stop = safe_float(get_well_value(well, ['STOP']))
            step = safe_float(get_well_value(well, ['STEP']))
            strt_unit = well.get('STRT', {}).get('unit', '')
            well_name = get_well_value(well, ['WELL'])
            field_name = get_well_value(well, ['FLD', 'FIELD'])
            company = get_well_value(well, ['COMP', 'COMPANY'])
            las_version = get_well_value(version, ['VERS'])
            wrap = get_well_value(version, ['WRAP'])
            params_json = {}
            for k, v in params.items():
                params_json[k] = {'value': v['value'], 'unit': v['unit'], 'description': v['description']}
            data_start = sections['data_start_line']
            if data_start is None:
                errors.append(f"{short_name}: No ~A section found"); continue
            curve_mnemonics = [c['mnemonic'] for c in curves]
            num_curves = len(curve_mnemonics)
            data_rows = []
            for line_idx in range(data_start, len(lines)):
                line = lines[line_idx]
                if not line or line.strip() == '' or line.strip() == 'None': continue
                values = line.split()
                if len(values) >= num_curves:
                    data_rows.append([safe_float(v) for v in values[:num_curves]])
            num_data_rows = len(data_rows)
            def sq(v):
                if v is None: return 'NULL'
                return "'" + escape_sql(str(v)) + "'"
            def nf(v):
                if v is None: return 'NULL'
                return str(v)
            params_str = escape_sql(json.dumps(params_json)) if params_json else '{}'
            header_sql = f"""
                INSERT INTO PE_POC.RAW_VOLVE.LAS_HEADERS (
                    FILENAME, LAS_VERSION, WRAP, STRT, STOP, STEP, NULL_VALUE, STRT_UNIT,
                    WELL_NAME, FIELD_NAME, COMPANY,
                    PARAMETERS, NUM_CURVES, NUM_DATA_ROWS
                ) SELECT
                    {sq(short_name)}, {sq(las_version)}, {sq(wrap)},
                    {nf(strt)}, {nf(stop)}, {nf(step)}, {nf(null_value)}, {sq(strt_unit)},
                    {sq(well_name)}, {sq(field_name)}, {sq(company)},
                    PARSE_JSON('{params_str}'), {num_curves}, {num_data_rows}
            """
            session.sql(header_sql).collect()
            file_id_row = session.sql(f"""
                SELECT LAS_FILE_ID FROM PE_POC.RAW_VOLVE.LAS_HEADERS
                WHERE FILENAME = {sq(short_name)} ORDER BY LOADED_AT DESC LIMIT 1
            """).collect()
            file_id = file_id_row[0]['LAS_FILE_ID']
            for idx, curve in enumerate(curves):
                session.sql(f"""
                    INSERT INTO PE_POC.RAW_VOLVE.LAS_CURVES
                    (LAS_FILE_ID, CURVE_INDEX, MNEMONIC, UNIT, API_CODE, DESCRIPTION)
                    VALUES ({file_id}, {idx}, {sq(curve['mnemonic'])},
                            {sq(curve.get('unit', ''))}, {sq(curve.get('api_code', ''))},
                            {sq(curve.get('description', ''))})
                """).collect()
            batch_size = 1000
            insert_rows = []
            for row_data in data_rows:
                depth = row_data[0]
                if depth is None: continue
                for col_idx in range(1, min(len(row_data), num_curves)):
                    val = row_data[col_idx]
                    if val is not None and abs(val - null_value) < 0.001: val = None
                    mnem = curve_mnemonics[col_idx]
                    insert_rows.append((file_id, depth, mnem, val))
                if len(insert_rows) >= batch_size:
                    values_str = ','.join([
                        f"({r[0]},{r[1]},'{r[2]}',{r[3] if r[3] is not None else 'NULL'})"
                        for r in insert_rows])
                    session.sql(f"INSERT INTO PE_POC.RAW_VOLVE.LAS_LOG_DATA (LAS_FILE_ID, DEPTH, MNEMONIC, VALUE) VALUES {values_str}").collect()
                    insert_rows = []
            if insert_rows:
                values_str = ','.join([
                    f"({r[0]},{r[1]},'{r[2]}',{r[3] if r[3] is not None else 'NULL'})"
                    for r in insert_rows])
                session.sql(f"INSERT INTO PE_POC.RAW_VOLVE.LAS_LOG_DATA (LAS_FILE_ID, DEPTH, MNEMONIC, VALUE) VALUES {values_str}").collect()
            files_loaded += 1
        except Exception as e:
            errors.append(f"{short_name}: {str(e)}")
    result = f"Loaded {files_loaded} LAS file(s)."
    if errors:
        result += f" Errors ({len(errors)}): " + '; '.join(errors)
    return result
$$;
