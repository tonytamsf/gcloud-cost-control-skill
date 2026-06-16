#!/bin/bash
# GCP Cost Analysis Script
# Usage: ./analyze_costs.sh <PROJECT_ID> [DAYS]
#
# Analyzes a GCP project's resource usage to estimate costs.
# Checks Cloud Functions, Storage, Artifact Registry, and API usage.

set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <PROJECT_ID> [DAYS]}"
DAYS="${2:-30}"

echo "=== GCP Cost Analysis: ${PROJECT_ID} ==="
echo "Period: Last ${DAYS} days"
echo ""

# 1. Billing account
echo "--- Billing Account ---"
gcloud billing projects describe "$PROJECT_ID" 2>/dev/null || echo "Cannot access billing info"
echo ""

# 2. Cloud Functions invocations
echo "--- Cloud Functions: Invocations ---"
gcloud logging read "resource.type=\"cloud_function\" AND textPayload=\"Function execution started\"" \
  --project="$PROJECT_ID" --freshness="${DAYS}d" \
  --format="value(resource.labels.function_name)" --limit=10000 2>/dev/null \
  | sort | uniq -c | sort -rn || echo "No function logs found"
echo ""

# 3. Cloud Functions execution times
echo "--- Cloud Functions: Execution Times ---"
for fn in $(gcloud logging read "resource.type=\"cloud_function\" AND textPayload=\"Function execution started\"" \
  --project="$PROJECT_ID" --freshness="${DAYS}d" \
  --format="value(resource.labels.function_name)" --limit=10000 2>/dev/null \
  | sort -u); do
  result=$(gcloud logging read "resource.type=\"cloud_function\" AND resource.labels.function_name=\"$fn\" AND textPayload=~\"Function execution took\"" \
    --project="$PROJECT_ID" --freshness="${DAYS}d" \
    --format="value(textPayload)" --limit=500 2>/dev/null \
    | grep -oP '\d+ ms' | awk '{sum+=$1; count++} END {if(count>0) printf "%.1fs avg, %d calls, %.0fs total", sum/count/1000, count, sum/1000; else print "no timing data"}')
  echo "  $fn: $result"
done
echo ""

# 4. Storage
echo "--- Cloud Storage ---"
for bucket in $(gsutil ls -p "$PROJECT_ID" 2>/dev/null); do
  size=$(gsutil du -sh "$bucket" 2>/dev/null | head -1)
  echo "  $size"
done
echo ""

# 5. Artifact Registry
echo "--- Artifact Registry ---"
gcloud artifacts repositories list --project="$PROJECT_ID" \
  --format="table(REPOSITORY,FORMAT,LOCATION,SIZE_MB:label='SIZE (MB)')" 2>/dev/null \
  || echo "No repositories found"
echo ""

# 6. Enabled APIs (potential cost sources)
echo "--- Enabled APIs (billable) ---"
gcloud services list --project="$PROJECT_ID" --format="value(config.title)" 2>/dev/null \
  | grep -iE "text-to-speech|generative|vision|translate|speech|video|natural language|automl|vertex" \
  || echo "No billable AI/ML APIs found"
echo ""

# 7. Budgets
echo "--- Budgets ---"
BILLING_ACCT=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null | sed 's/billingAccounts\///')
if [ -n "$BILLING_ACCT" ]; then
  gcloud billing budgets list --billing-account="$BILLING_ACCT" \
    --format="table(displayName,amount.specifiedAmount.units,notificationsRule.pubsubTopic)" 2>/dev/null \
    || echo "Cannot list budgets"
fi
echo ""

echo "=== Analysis Complete ==="
