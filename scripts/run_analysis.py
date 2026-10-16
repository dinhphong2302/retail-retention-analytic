"""Run every query in sql/ against data/retail.db and save the results to outputs/*.csv."""
import sqlite3
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "retail.db"
OUT = ROOT / "outputs"


def run(path: Path, con) -> pd.DataFrame:
    df = pd.read_sql_query(path.read_text(encoding="utf-8"), con)
    df.to_csv(OUT / f"{path.stem}.csv", index=False)
    return df


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    pd.set_option("display.width", 220)
    pd.set_option("display.max_columns", 20)
    only = sys.argv[1:]
    con = sqlite3.connect(DB)
    try:
        for path in sorted((ROOT / "sql").glob("*.sql")):
            if only and not any(o in path.stem for o in only):
                continue
            df = run(path, con)
            print(f"\n=== {path.stem} ({len(df)} rows)")
            print(df.to_string(index=False, max_rows=40))
    finally:
        con.close()
