#!/usr/bin/env python3
"""
Reproduce DefiLlama's protocol-page ".csv" button.

The button does no server-side export: it serialises the chart data the page
already fetched from a public, unauthenticated endpoint into a Blob. So no
login / PocketBase token is needed - just hit that endpoint.

Usage:
    python defillama_csv.py https://defillama.com/protocol/01-exchange
    python defillama_csv.py 01-exchange --kind adapter --adapter-type derivatives -o out.csv
"""
import argparse
import csv
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse
import polars as pl

# Cloudflare challenges plain curl/requests on defillama.com; curl_cffi
# impersonates Chrome's TLS fingerprint.  pip install curl_cffi
from curl_cffi import requests

ENDPOINT = "https://defillama.com/api/public/protocols/charts"
HEADERS = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130 Safari/537.36"}

# adapterType -> CSV column label the site uses
LABELS = {"derivatives": "Perp Volume", "dexs": "DEX Volume", "fees": "Fees", "options": "Options Volume"}


def slug_from(arg: str) -> str:
    return urlparse(arg).path.rstrip("/").split("/")[-1] if arg.startswith("http") else arg


def fetch(slug: str, kind: str, adapter_type: str | None) -> list[list[float]]:
    params = {"kind": kind, "protocol": slug}
    if kind == "adapter":
        params["adapterType"] = adapter_type
    r = requests.get(ENDPOINT, params=params, timeout=30, impersonate="chrome")
    if "text/html" in r.headers.get("content-type", ""):
        sys.exit(f"Cloudflare challenge (HTTP {r.status_code}) for {slug} - back off or use api.llama.fi")
    if not r.ok:
        return []
    return r.json()


def run(exchange: str) -> pl.DataFrame:
    rows = fetch(exchange, "adapter", "fees")
    df_fees = pl.DataFrame(rows, schema=["timestamp", "fees"], orient="row").cast({"timestamp": pl.Int64, "fees": pl.Int64})
    rows = fetch(exchange, "adapter", "derivatives")
    df_volume = pl.DataFrame(rows, schema=["timestamp", "perp_volume"], orient="row").cast({"timestamp": pl.Int64, "perp_volume": pl.Int64})
    df = df_fees.join(df_volume, on="timestamp", how="full", coalesce=True, suffix="_right").sort("timestamp")
    df = df.with_columns(pl.from_epoch("timestamp", time_unit="s").dt.date().alias("date"))
    df = df.with_columns(pl.lit(exchange).alias("exchange"))
    return df

def extract_exchange(link: str) -> str:
    if link[-1] == "/":
        link = link[:-1]
    last_fs = 0
    first_qm = 0
    for i, c in enumerate(link):
        if c=="/":
            last_fs = i
        if c=="?" and first_qm==0:
            first_qm = i
    if first_qm == 0:
        return link[last_fs+1:]
    else:
        return link[last_fs + 1:first_qm]

if __name__ == "__main__":
    df_link = pl.read_csv("./dex_defillama_links.csv")
    total_links = len(df_link["DefiLlama Link"])
    df_total = pl.DataFrame()
    for i, link in enumerate(df_link["DefiLlama Link"]):
        if link is None: 
            continue
        df = run(extract_exchange(link))
        print(f"done {i / total_links * 100}%")
        df.write_csv("last_one.csv")
        df_total = df_total.vstack(df)
    df_total = df_total.sort("timestamp")
    df_total.write_csv("all_exchanges_fees_volume.csv")
