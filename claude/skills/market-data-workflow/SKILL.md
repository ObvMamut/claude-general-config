---
name: market-data-workflow
description: Shared protocol for pulling market and macro data from FRED, Alpha Vantage, and SEC EDGAR — credentials, rate-limit budgeting, caching, as-of dating, and cross-source reconciliation. Use when a task needs figures from more than one of these sources, or any figure that will be quoted, charted, or acted on.
---

# Market Data Workflow

The individual source skills (`fred-economic-data`, `alpha-vantage`, `edgartools`) each
know their own API. This skill is what they share: how to sequence them, how to stay
inside the free tiers, and how to make every number reproducible.

## Credentials

All three are free tiers. Never introduce a paid plan or a second provider without an
explicit request.

| Source | Variable | Notes |
|---|---|---|
| FRED | `FRED_API_KEY` | set in `~/.zshenv` |
| Alpha Vantage | `ALPHAVANTAGE_API_KEY` | set in `~/.zshenv` |
| SEC EDGAR | `EDGAR_IDENTITY` | **not currently set**; SEC requires `"Name email@example.com"` |

Read them from the environment. Never hardcode a key, never echo one into output, never
write one into a file that lands in a repo.

## Source selection

Go to the source that is authoritative for the question, not the one that is easiest:

- **Macro series** (rates, CPI, unemployment, GDP, spreads) → FRED. It carries revision
  history via ALFRED, which is the only way to know what was *knowable* on a past date.
- **Prices and technicals** (OHLCV, FX, crypto, indicators) → Alpha Vantage.
- **Company fundamentals** (revenue, margins, segments, holdings, insider activity) →
  EDGAR. Prefer the filing over any vendor's summary of it.

When two sources disagree, the filing beats the vendor and the vintage beats the current
print. Say which you used and why.

## Rate-limit budgeting

The free tiers are tightly capped, and Alpha Vantage's daily cap is small enough that a
careless loop exhausts it in one session.

- **Plan the call list before making any call.** Write down which series and which
  symbols you need; deduplicate; then fetch.
- Never call inside a loop over rows without a delay and a hard cap on iterations.
- Fetch a full series once and slice locally rather than making one call per date.
- On a rate-limit response, stop. Do not retry in a tight loop, and do not silently
  fall back to a different provider — report that the budget is spent.

## Caching

Write every raw response to a local cache before transforming it:

```
.cache/marketdata/<source>/<identifier>__<YYYY-MM-DD>.json
```

Re-reading a cached file is free; re-fetching is not. Check the cache before every call.
Keep the raw payload, not just the parsed frame — a parsing bug should never cost
another fetch.

## As-of dating

Every figure that leaves this workflow carries, without exception:

- the **value** with its unit,
- the **period** it covers,
- the **source** and its identifier (FRED series ID, ticker, CIK + accession number),
- the **retrieval date**.

For macro data also record whether the value is preliminary, revised, or final, and
which vintage you pulled. A backtest that uses today's revised figure for a past date is
wrong, and wrong in a way that looks plausible.

## Reconciliation

Before reporting a cross-source figure, check it against a second source when one exists
and the check is cheap. If they disagree by more than rounding, report both and explain
the discrepancy rather than silently picking one.

## Output

Hand results to `dataviz` before writing any plotting code. For anything the user will
quote or act on, the `research-report` output style applies: finding first, then
evidence, then caveats.

Analysis is not advice. Do not recommend a position, allocation, or trade unless asked.
