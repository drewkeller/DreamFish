from dotenv import load_dotenv
import json
import os
import re
import sys
from datetime import date
from pathlib import Path
import pandas as pd

load_dotenv()

'''
Options for output format:
  * csv     - Plain CSV
  * logfmt  - Logfmt Viewer compatible format in CSV
  * jsonl   - JSON Lines format
'''
output_formats = [
    { "value": "csv",    "extension": "csv" },
    { "value": "logfmt", "extension": "log" },
    { "value": "jsonl",  "extension": "jsonl" }
]
OUTPUT_FORMAT = "jsonl"

# 1. Fetch Environment Variables
WOW_DIR_RAW = os.environ.get("WOW_DIR")
ADDON_NAME = os.environ.get("ADDON_NAME")

# Verify environment properties are loaded
if not WOW_DIR_RAW or not ADDON_NAME:
    print("Error: Missing required environment variables.")
    print(f"  WOW_DIR: {WOW_DIR_RAW}")
    print(f"  ADDON_NAME: {ADDON_NAME}")
    print("\nPlease set them via terminal before running this script:")
    print("  export WOW_DIR=\"C:\\Program Files (x86)\\World of Warcraft\\_retail_\"")
    print("  export ADDON_NAME=\"MyAddon\"")
    sys.exit(1)

# Construct base folder path to Account tracking matrices
WOW_DIR = Path(WOW_DIR_RAW)
WTF_ACCOUNT_DIR = WOW_DIR / "WTF" / "Account"

def get_output_file():
    for fmt in output_formats:
        if fmt["value"] == OUTPUT_FORMAT:
            return f"{ADDON_NAME}Log.{fmt['extension']}"
    return f"{ADDON_NAME}Log.log"

# Regex parsing string matching standard format token signatures:
# "TIMESTAMP: [LEVEL][SOURCE] MESSAGE"
LOG_PATTERN = re.compile(
    r'^\s*"(?P<timestamp>\d{2}:\d{2}:\d{2}\.\d{3}):\s*(?:\[(?P<level>[^\]]+)\])?(?:\[(?P<source>[^\]]+)\])?\s*(?P<message>.*?)"\s*,?\s*$'
)

def find_saved_variables_file():
    """Traverses WTF directory structures using pathlib's folder scanning features."""
    if not WTF_ACCOUNT_DIR.exists():
        print(f"Error: Target path folder does not exist: {WTF_ACCOUNT_DIR}")
        return None

    for account_path in WTF_ACCOUNT_DIR.iterdir():
        if account_path.is_dir():
            target_file = account_path / "SavedVariables" / f"{ADDON_NAME}.lua"
            if target_file.exists():
                return target_file
    return None

def extract_wow_log_to_csv():
    input_file = find_saved_variables_file()

    if not input_file:
        print(f"Error: Could not find live active files named '{ADDON_NAME}.lua' in your WTF database structure.")
        return

    print(f"Found active database source file at: {input_file}")
    parsed_rows = []
    in_log_block = False

    # Target label structure hook string assignment pattern match setup
    log_start_marker = f"{ADDON_NAME}Log = {{"

    with input_file.open("r", encoding="utf-8") as file:
        for line in file:
            if log_start_marker in line:
                in_log_block = True
                continue
            if in_log_block and line.strip() == "}":
                in_log_block = False
                break

            if in_log_block:
                match = LOG_PATTERN.match(line)
                if match:
                    gd = match.groupdict()
                    parsed_rows.append({
                        "Timestamp": gd["timestamp"],
                        "Level": gd["level"] if gd["level"] else "NONE",
                        "Source": gd["source"] if gd["source"] else "CORE",
                        "Message": gd["message"].strip()
                    })
                else:
                    fallback_match = re.match(r'^\s*"(?P<timestamp>\d{2}:\d{2}:\d{2}\.\d{3}):\s*(?P<message>.*?)"\s*,?\s*$', line)
                    if fallback_match:
                        fd = fallback_match.groupdict()
                        parsed_rows.append({
                            "Timestamp": fd["timestamp"],
                            "Level": "NONE",
                            "Source": "CORE",
                            "Message": fd["message"].strip()
                        })

    if not parsed_rows:
        print(f"Extraction halted: Log values inside '{ADDON_NAME}Log' appear empty.")
        return

    df = pd.DataFrame(parsed_rows)
    output_file = get_output_file()
    if OUTPUT_FORMAT == "logfmt":
        today_str = date.today().isoformat()
        with open(output_file, "w", encoding="utf-8") as f:
            for _, row in df.iterrows():
                f.write(
                    f'time={today_str}T{row["Timestamp"]} level={row["Level"]} source="{row["Source"]}" msg="{row["Message"]}"\n'
                )
    elif OUTPUT_FORMAT == "jsonl":
        today_str = date.today().isoformat()
        with open(output_file, "w", encoding="utf-8") as f:
            for _, row in df.iterrows():
                entry = {
                    "time": f"{today_str}T{row['Timestamp']}",
                    "level": row["Level"],
                    "source": row["Source"],
                    "msg": row["Message"]
                }
                f.write(f"{json.dumps(entry)}\n")
    elif OUTPUT_FORMAT == "csv":
        df.to_csv(output_file, index=False)
    else:
        valid_formats = ", ".join([f"'{fmt['value']}'" for fmt in output_formats])
        print(f"Error: Unsupported OUTPUT_FORMAT: {OUTPUT_FORMAT!r}. Use one of: {valid_formats}.")
        return
    print(f"Success! Extracted {len(df)} records directly out into: '{output_file}'")

if __name__ == "__main__":
    extract_wow_log_to_csv()
