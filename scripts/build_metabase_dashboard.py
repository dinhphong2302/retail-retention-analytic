"""Set up a local Metabase (http://127.0.0.1:3000) and build the retention dashboard through its REST API.

First run: creates a local admin account with a random password and stores it in
tools/metabase-admin.local.json (git-ignored). Later runs reuse that file.
Every card is a native SQL question that reads the files in sql/.
"""
import json
import secrets
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
MB = "http://127.0.0.1:3000"
CREDS = ROOT / "tools" / "metabase-admin.local.json"
DB_PATH = str(ROOT / "data" / "retail.db")
DASHBOARD_NAME = "Customer Retention & Revenue Health"


def sql(name: str) -> str:
    return (ROOT / "sql" / name).read_text(encoding="utf-8").strip().rstrip(";")


def wrap(name: str, where: str) -> str:
    return f"SELECT * FROM (\n{sql(name)}\n) WHERE {where}"


def wait_ready():
    for _ in range(120):
        try:
            if requests.get(f"{MB}/api/health", timeout=5).json().get("status") == "ok":
                return
        except requests.RequestException:
            pass
        time.sleep(5)
    sys.exit("Metabase did not become healthy in 10 minutes")


def session() -> requests.Session:
    s = requests.Session()
    props = s.get(f"{MB}/api/session/properties").json()
    token = props.get("setup-token")
    if token and not props.get("has-user-setup"):
        creds = {"email": "admin@retail-analytics.local", "password": secrets.token_urlsafe(18) + "9a"}
        r = s.post(f"{MB}/api/setup", json={
            "token": token,
            "user": {"first_name": "Local", "last_name": "Admin", "site_name": "Retail Analytics", **creds},
            "prefs": {"site_name": "Retail Analytics", "site_locale": "en", "allow_tracking": False},
        })
        r.raise_for_status()
        CREDS.write_text(json.dumps(creds, indent=2), encoding="utf-8")
    creds = json.loads(CREDS.read_text(encoding="utf-8"))
    r = s.post(f"{MB}/api/session", json={"username": creds["email"], "password": creds["password"]})
    r.raise_for_status()
    s.headers["X-Metabase-Session"] = r.json()["id"]
    return s


def database_id(s: requests.Session) -> int:
    for db in s.get(f"{MB}/api/database").json()["data"]:
        if db["engine"] == "sqlite" and db["details"].get("db") == DB_PATH:
            return db["id"]
    r = s.post(f"{MB}/api/database", json={"engine": "sqlite", "name": "Retail warehouse (SQLite)",
                                           "details": {"db": DB_PATH}})
    r.raise_for_status()
    return r.json()["id"]


def heat(columns):
    return [{"columns": columns, "type": "range", "colors": ["#FFFFFF", "#2F7FD8"],
             "min_type": "custom", "min_value": 0, "max_type": "custom", "max_value": 45,
             "operator": "=", "highlight_row": False, "id": 0}]


def cards(db: int) -> list[dict]:
    def q(name, query, display, viz=None, description=None):
        return {"name": name, "display": display, "description": description,
                "visualization_settings": viz or {},
                "dataset_query": {"type": "native", "native": {"query": query}, "database": db}}

    kpi = wrap("01_monthly_kpis.sql", "is_partial_month = 0")
    return [
        q("Monthly gross revenue (£)", kpi, "line",
          {"graph.dimensions": ["year_month"], "graph.metrics": ["gross_revenue"],
           "graph.show_values": False, "graph.y_axis.title_text": "£"}),
        q("Active customers: new vs returning", kpi, "bar",
          {"graph.dimensions": ["year_month"], "graph.metrics": ["new_customers", "returning_customers"],
           "stackable.stack_type": "stacked"}),
        q("Cancellation rate by month (%)", kpi, "line",
          {"graph.dimensions": ["year_month"], "graph.metrics": ["cancel_rate_pct"]},
          "Spikes in 2011-01 and 2011-12 come from single orders; see the drill-down."),
        q("Cancellation spikes: largest cancelled line per month",
          "SELECT year_month, description, quantity, cancelled_value, share_of_month_cancellations_pct FROM (\n"
          + sql("09_cancellation_drilldown.sql") + "\n) WHERE rn = 1", "table"),
        q("YoY revenue bridge: customers × frequency × AOV (£)", sql("07_revenue_bridge_yoy.sql"), "bar",
          {"graph.dimensions": ["year_month"],
           "graph.metrics": ["customer_effect", "frequency_effect", "aov_effect"],
           "stackable.stack_type": "stacked"},
          "Additive decomposition of the YoY change in identified-customer revenue."),
        q("Cohort retention (% of cohort buying in month N)", sql("12_cohort_retention_matrix.sql"), "table",
          {"table.column_formatting": heat(["M1", "M2", "M3", "M4", "M5", "M6", "M9", "M12"])}),
        q("Repeat-purchase funnel (cohorts 2010-01 to 2011-06)", sql("03_repeat_purchase_funnel.sql"), "funnel",
          {"funnel.dimension": "stage", "funnel.metric": "customers"}),
        q("Days from 1st to 2nd order", sql("04_time_to_second_order.sql"), "bar",
          {"graph.dimensions": ["bucket"], "graph.metrics": ["pct"]}),
        q("Next-quarter churn: new vs returning (%)", sql("05_quarterly_churn.sql"), "bar",
          {"graph.dimensions": ["quarter", "customer_type"], "graph.metrics": ["churn_rate_pct"]}),
        q("RFM segments (last 12 months)", sql("06_rfm_segments.sql"), "table"),
        q("Revenue change by country, Jan–Nov 2011 vs 2010 (£)", sql("08_country_contribution.sql"), "row",
          {"graph.dimensions": ["country"], "graph.metrics": ["change"]}),
        q("EIRE decline by account", sql("10_eire_concentration.sql"), "table"),
    ]


HEADLINE = """## Customer Retention & Revenue Health — Online Retail II (Dec 2009 – Dec 2011)
**Revenue from identified customers was flat YoY (Dec 2010–Nov 2011: −£106k, −1.3%), but the mix underneath shifted.** Customers ordered less often \
(frequency effect −£217k, negative in 10 of 12 months), while bigger baskets offset most of it (AOV effect +£147k). \
New-customer acquisition fell 37% (Jul–Nov 2011 vs 2010), and in 2011 49–60% of new customers churned the following quarter, against ~35% of returning ones."""

NOTES = """**What to act on**
1. **Second-order nudge at day 30–60.** 58% of second orders happen within 90 days of the first; after that the window mostly closes.
2. **Reactivate "At risk".** 642 customers (15%) with £805k of 12-month revenue have not ordered for ~139 days on average.
3. **Account risk in EIRE.** One account explains 75% of the market's −24% decline; two accounts make 91% of EIRE revenue.
4. **Don't chase the cancellation spikes.** 84% (Jan 2011) and 97% (Dec 2011) of cancelled value are single bulk orders; the underlying rate is ~1.5–3%."""


def text_card(text, row, col, w, h):
    return {"id": None, "card_id": None, "row": row, "col": col, "size_x": w, "size_y": h,
            "parameter_mappings": [],
            "visualization_settings": {"text": text, "virtual_card": {
                "name": None, "display": "text", "visualization_settings": {}, "dataset_query": {},
                "archived": False}}}


def main():
    wait_ready()
    s = session()
    db = database_id(s)
    s.post(f"{MB}/api/database/{db}/sync_schema")

    for d in s.get(f"{MB}/api/dashboard").json():
        if d["name"] == DASHBOARD_NAME:
            s.delete(f"{MB}/api/dashboard/{d['id']}")
    for c in s.get(f"{MB}/api/card").json():
        if c.get("collection_id") is None and c["database_id"] == db:
            s.delete(f"{MB}/api/card/{c['id']}")

    ids = []
    for spec in cards(db):
        r = s.post(f"{MB}/api/card", json=spec)
        r.raise_for_status()
        ids.append(r.json()["id"])

    dash = s.post(f"{MB}/api/dashboard", json={"name": DASHBOARD_NAME,
                                                "description": "Built from sql/*.sql against data/retail.db"})
    dash.raise_for_status()
    dash_id = dash.json()["id"]

    # 24-column grid: (card index, row, col, width, height)
    layout = [(0, 4, 0, 12, 6), (1, 4, 12, 12, 6),
              (4, 10, 0, 24, 7),
              (5, 17, 0, 24, 9),
              (6, 26, 0, 8, 6), (7, 26, 8, 8, 6), (8, 26, 16, 8, 6),
              (9, 32, 0, 14, 6), (10, 32, 14, 10, 6),
              (2, 38, 0, 10, 6), (3, 38, 10, 14, 6),
              (11, 44, 0, 10, 5)]
    dashcards = [text_card(HEADLINE, 0, 0, 24, 4)]
    for i, (idx, row, col, w, h) in enumerate(layout):
        dashcards.append({"id": -(i + 1), "card_id": ids[idx], "row": row, "col": col, "size_x": w, "size_y": h,
                          "parameter_mappings": [], "visualization_settings": {}})
    note = text_card(NOTES, 44, 10, 14, 5)
    for i, dc in enumerate([dashcards[0], note]):
        dc["id"] = -(100 + i)
    dashcards.append(note)

    r = s.put(f"{MB}/api/dashboard/{dash_id}", json={"dashcards": dashcards, "tabs": []})
    if not r.ok:
        sys.exit(f"dashboard layout failed: {r.status_code} {r.text[:500]}")
    print(f"{MB}/dashboard/{dash_id}")


if __name__ == "__main__":
    main()
