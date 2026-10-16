"""Quick profile of the raw Online Retail II workbook. Caches both sheets to a CSV for faster reruns."""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW_XLSX = ROOT / "data" / "raw" / "online_retail_II.xlsx"
RAW_CSV = ROOT / "data" / "raw" / "online_retail_II.csv.gz"


def load_raw() -> pd.DataFrame:
    if RAW_CSV.exists():
        return pd.read_csv(RAW_CSV, dtype={"Invoice": str, "StockCode": str}, parse_dates=["InvoiceDate"])
    sheets = pd.read_excel(RAW_XLSX, sheet_name=None, dtype={"Invoice": str, "StockCode": str})
    df = pd.concat(sheets.values(), ignore_index=True)
    df.to_csv(RAW_CSV, index=False, compression="gzip")
    return df


if __name__ == "__main__":
    df = load_raw()
    print(df.shape)
    print(df.dtypes)
    print(df.head())
    print("date range:", df.InvoiceDate.min(), "->", df.InvoiceDate.max())
    print("null customer:", df["Customer ID"].isna().mean().round(4))
    print("cancel invoices:", df.Invoice.str.startswith("C").mean().round(4))
    print("qty<=0:", (df.Quantity <= 0).mean().round(4), " price<=0:", (df.Price <= 0).mean().round(4))
    print("exact dup rows:", df.duplicated().sum())
    print("customers:", df["Customer ID"].nunique(), " products:", df.StockCode.nunique(), " countries:", df.Country.nunique())
    non_num = df.loc[~df.StockCode.str.match(r"^\d{5}"), "StockCode"].value_counts().head(30)
    print("non-standard stock codes:\n", non_num)
    print(df.Country.value_counts().head(10))
