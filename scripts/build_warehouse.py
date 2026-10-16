"""Clean Online Retail II and load it into a SQLite star schema.

Tables
  fact_sales    one row per invoice line (sales and cancellations)
  dim_customer  one row per customer, with acquisition cohort
  dim_product   one row per stock code, with a non-product flag
  dim_date      calendar 2009-12-01 .. 2011-12-31
  etl_log       how many rows each cleaning rule removed or flagged
"""
import sqlite3
from pathlib import Path

import pandas as pd

from profile_raw import load_raw

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "retail.db"

# Postage, fees, manual adjustments, samples, gift vouchers, test lines: not merchandise.
NON_PRODUCT_CODES = {"POST", "DOT", "M", "C2", "D", "S", "BANK CHARGES", "ADJUST", "AMAZONFEE",
                     "PADS", "CRUK", "B"}
NON_PRODUCT_PREFIXES = ("TEST", "GIFT_", "ADJUST")


def is_non_product(code: str) -> bool:
    c = code.upper().strip()
    return c in NON_PRODUCT_CODES or c.startswith(NON_PRODUCT_PREFIXES)


def clean(raw: pd.DataFrame) -> tuple[pd.DataFrame, list[tuple[str, int]]]:
    log = [("raw rows", len(raw))]
    df = raw.rename(columns={"Invoice": "invoice_no", "StockCode": "stock_code", "Description": "description",
                             "Quantity": "quantity", "InvoiceDate": "invoice_ts", "Price": "unit_price",
                             "Customer ID": "customer_id", "Country": "country"})

    before = len(df)
    df = df.drop_duplicates()
    log.append(("dropped: exact duplicate lines", before - len(df)))

    df["is_cancellation"] = df.invoice_no.str.startswith("C").astype(int)

    # Non-cancellation lines with qty <= 0 or price <= 0 are stock write-offs and bad-debt entries, not sales.
    bad = (df.is_cancellation == 0) & ((df.quantity <= 0) | (df.unit_price <= 0))
    log.append(("dropped: non-cancel lines with qty<=0 or price<=0", int(bad.sum())))
    df = df[~bad]

    bad = df.unit_price < 0
    log.append(("dropped: negative price lines", int(bad.sum())))
    df = df[~bad]

    df["stock_code"] = df.stock_code.str.strip().str.upper()
    df["is_non_product"] = df.stock_code.map(is_non_product).astype(int)
    log.append(("flagged: non-product lines (postage, fees, adjustments)", int(df.is_non_product.sum())))

    log.append(("kept, customer id missing (guest checkout)", int(df.customer_id.isna().sum())))
    df["customer_id"] = df.customer_id.astype("Int64")
    df["revenue"] = (df.quantity * df.unit_price).round(2)
    df["date_key"] = df.invoice_ts.dt.strftime("%Y%m%d").astype(int)
    log.append(("clean rows loaded", len(df)))
    return df.reset_index(drop=True), log


def build_dims(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    sales = df[(df.is_cancellation == 0) & (df.is_non_product == 0) & df.customer_id.notna()]

    first = sales.groupby("customer_id").invoice_ts.min()
    home = (df[df.customer_id.notna()].groupby(["customer_id", "country"]).size()
            .reset_index(name="n").sort_values("n", ascending=False)
            .drop_duplicates("customer_id").set_index("customer_id").country)
    dim_customer = pd.DataFrame({"customer_key": home.index.astype(int), "country": home.values})
    dim_customer["first_purchase_date"] = dim_customer.customer_key.map(first).dt.strftime("%Y-%m-%d")
    dim_customer["cohort_month"] = dim_customer.customer_key.map(first).dt.strftime("%Y-%m")

    desc = (df.dropna(subset=["description"]).groupby(["stock_code", "description"]).size()
            .reset_index(name="n").sort_values("n", ascending=False).drop_duplicates("stock_code"))
    dim_product = (df[["stock_code", "is_non_product"]].drop_duplicates("stock_code")
                   .merge(desc[["stock_code", "description"]], on="stock_code", how="left")
                   .rename(columns={"stock_code": "product_key"}))

    days = pd.date_range("2009-12-01", "2011-12-31", freq="D")
    dim_date = pd.DataFrame({
        "date_key": days.strftime("%Y%m%d").astype(int),
        "date": days.strftime("%Y-%m-%d"),
        "year": days.year,
        "quarter": days.quarter,
        "month": days.month,
        "year_month": days.strftime("%Y-%m"),
        "iso_week": days.isocalendar().week.values,
        "day_of_week": days.day_name(),
        "is_weekend": (days.dayofweek >= 5).astype(int),
    })
    return dim_customer, dim_product, dim_date


DDL = """
DROP TABLE IF EXISTS fact_sales; DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_product; DROP TABLE IF EXISTS dim_date; DROP TABLE IF EXISTS etl_log;

CREATE TABLE dim_date (
  date_key INTEGER PRIMARY KEY, date TEXT, year INTEGER, quarter INTEGER, month INTEGER,
  year_month TEXT, iso_week INTEGER, day_of_week TEXT, is_weekend INTEGER);
CREATE TABLE dim_customer (
  customer_key INTEGER PRIMARY KEY, country TEXT, first_purchase_date TEXT, cohort_month TEXT);
CREATE TABLE dim_product (
  product_key TEXT PRIMARY KEY, description TEXT, is_non_product INTEGER);
CREATE TABLE fact_sales (
  line_id INTEGER PRIMARY KEY, invoice_no TEXT NOT NULL, invoice_ts TEXT NOT NULL,
  date_key INTEGER NOT NULL REFERENCES dim_date(date_key),
  customer_key INTEGER REFERENCES dim_customer(customer_key),
  product_key TEXT NOT NULL REFERENCES dim_product(product_key),
  country TEXT, quantity INTEGER, unit_price REAL, revenue REAL,
  is_cancellation INTEGER, is_non_product INTEGER);
CREATE TABLE etl_log (step TEXT, row_count INTEGER);
"""

INDEXES = """
CREATE INDEX ix_fact_date ON fact_sales(date_key);
CREATE INDEX ix_fact_customer ON fact_sales(customer_key);
CREATE INDEX ix_fact_invoice ON fact_sales(invoice_no);
CREATE INDEX ix_fact_product ON fact_sales(product_key);
"""


def main():
    df, log = clean(load_raw())
    dim_customer, dim_product, dim_date = build_dims(df)
    fact = pd.DataFrame({
        "invoice_no": df.invoice_no,
        "invoice_ts": df.invoice_ts.dt.strftime("%Y-%m-%d %H:%M:%S"),
        "date_key": df.date_key,
        "customer_key": df.customer_id,
        "product_key": df.stock_code,
        "country": df.country,
        "quantity": df.quantity,
        "unit_price": df.unit_price,
        "revenue": df.revenue,
        "is_cancellation": df.is_cancellation,
        "is_non_product": df.is_non_product,
    })

    DB.unlink(missing_ok=True)
    con = sqlite3.connect(DB)
    try:
        con.executescript(DDL)
        dim_date.to_sql("dim_date", con, if_exists="append", index=False)
        dim_customer.to_sql("dim_customer", con, if_exists="append", index=False)
        dim_product.to_sql("dim_product", con, if_exists="append", index=False)
        fact.to_sql("fact_sales", con, if_exists="append", index=False, chunksize=50_000)
        pd.DataFrame(log, columns=["step", "row_count"]).to_sql("etl_log", con, if_exists="append", index=False)
        con.executescript(INDEXES)
        con.commit()
    finally:
        con.close()

    for step, n in log:
        print(f"{n:>10,}  {step}")
    print(f"customers {len(dim_customer):,}  products {len(dim_product):,}  dates {len(dim_date):,}")


if __name__ == "__main__":
    main()
