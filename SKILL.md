---
name: gcloud-cost-control
description: Analyze and control Google Cloud Platform costs using gcloud CLI, BigQuery billing exports, and Cloud Monitoring. Use this skill whenever the user asks about GCP costs, billing, budgets, spending, cost optimization, or wants to understand what's driving their cloud bill. Also use when the user mentions budget alerts, billing exports, cost spikes, or wants to set up cost controls on any GCP or Firebase project. Trigger on phrases like "how much am I spending", "what's costing money", "set a budget", "billing report", "cost breakdown", or any mention of GCP/Firebase billing.
---

# GCP Cost Control & Budget Analysis

Analyze, monitor, and control Google Cloud Platform costs using CLI tools. This skill covers cost investigation, budget enforcement, billing export setup, and ongoing cost optimization for GCP and Firebase projects.

## Quick Start

```bash
# Analyze costs for a project
# /gcloud-cost-control analyze <project-id>

# Set up budget with enforcement
# /gcloud-cost-control budget <project-id> <amount>

# Check current spend breakdown
# /gcloud-cost-control spend <project-id>
```

---

## Step 1: Identify the Project and Billing Account

Before any analysis, establish the billing context:

```bash
# Find the project's billing account
gcloud billing projects describe <PROJECT_ID>

# List all projects on a billing account
gcloud billing projects list --billing-account=<BILLING_ACCOUNT_ID>

# Ensure the right account is active
gcloud auth list
gcloud config set account <ACCOUNT_WITH_BILLING_ACCESS>
```

The active gcloud account needs `roles/billing.admin` or `roles/billing.viewer` on the billing account, and sufficient project-level permissions.

---

## Step 2: Cost Investigation

GCP does not expose cost reports via CLI or REST API directly. Use these approaches in order of preference:

### Approach A: BigQuery Billing Export (Best — if configured)

```sql
-- Cost by service (last 7 days)
SELECT service.description, ROUND(SUM(cost), 2) as total_cost
FROM `<PROJECT>.billing_export.gcp_billing_export_v1_<BILLING_ACCT_ID_UNDERSCORED>`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY 1 ORDER BY 2 DESC

-- Cost by SKU (detailed breakdown)
SELECT service.description, sku.description, ROUND(SUM(cost), 2) as cost
FROM `<PROJECT>.billing_export.gcp_billing_export_v1_<BILLING_ACCT_ID_UNDERSCORED>`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY 1, 2 HAVING cost > 0 ORDER BY 3 DESC

-- Daily cost trend
SELECT DATE(usage_start_time) as day, ROUND(SUM(cost), 2) as daily_cost
FROM `<PROJECT>.billing_export.gcp_billing_export_v1_<BILLING_ACCT_ID_UNDERSCORED>`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1 ORDER BY 1
```

Run via: `bq query --use_legacy_sql=false '<SQL>'`

The billing account ID in the table name uses underscores instead of hyphens (e.g., `0186A2_1DECC4_14D03F`).

### Approach B: Usage-Based Estimation (When no export exists)

Estimate costs by measuring actual usage of each service:

1. **Cloud Functions** — count invocations and execution time from logs
2. **Cloud Storage** — measure bucket sizes with `gsutil du -sh`
3. **Firestore** — check document counts and read/write volumes
4. **Text-to-Speech / AI APIs** — count API calls and character volumes from function logs
5. **Artifact Registry** — check container image storage sizes
6. **Networking** — estimate egress from function response sizes

```bash
# Count function invocations by name (this month)
gcloud logging read 'resource.type="cloud_function" AND textPayload="Function execution started"' \
  --project=<PROJECT_ID> --freshness=30d --format="value(resource.labels.function_name)" \
  --limit=5000 | sort | uniq -c | sort -rn

# Average execution time per function
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name="<FUNC>" AND textPayload=~"Function execution took"' \
  --project=<PROJECT_ID> --freshness=30d --format="value(textPayload)" \
  --limit=500 | grep -oP '\d+ ms' | awk '{sum+=$1; count++} END {printf "%.1fs avg, %d calls, %.0fs total\n", sum/count/1000, count, sum/1000}'

# Storage sizes
gsutil ls -p <PROJECT_ID>
gsutil du -sh gs://<BUCKET_NAME>/

# Artifact Registry size
gcloud artifacts repositories list --project=<PROJECT_ID>

# List enabled APIs (potential cost sources)
gcloud services list --project=<PROJECT_ID> --format="value(name)" | sort
```

### Approach C: Console Reports (Fallback)

Direct the user to the billing Console:
`https://console.cloud.google.com/billing/<BILLING_ACCT_ID>/reports`

Filter by project and date range. This is the only place that shows exact dollar amounts without BigQuery export.

---

## Step 3: Common Cost Drivers (GCP/Firebase)

When investigating costs, check these services first — they cause the most surprises:

| Service | Why It's Expensive | How to Check |
|---|---|---|
| **Cloud Text-to-Speech** | WaveNet/Neural2 = $16/1M chars. Full article synthesis adds up fast. | Check function logs for synthesis calls and character counts |
| **Generative AI (Gemini)** | Per-token billing via API key still bills to the project. | Count `onArticleCreated` or similar calls; check `generativelanguage.googleapis.com` |
| **Cloud Functions** | Puppeteer functions use 1GB+ memory with long timeouts. | Check avg execution time × memory × invocation count |
| **Cloud Storage egress** | Serving audio/PDF files to users. $0.12/GB after 1GB free. | Check `streamAudio` redirect counts; estimate file sizes |
| **Firestore** | High read volumes from real-time listeners across multiple tabs. | Check if `IndexedStack` or similar keeps listeners alive |
| **Artifact Registry** | Docker images from function deployments accumulate. | `gcloud artifacts repositories list` |

---

## Step 4: Budget Setup with Auto-Enforcement

When setting up cost controls, ALWAYS do both: create a budget AND deploy the enforcement function. Budget alerts alone are just emails — they don't stop spending.

### 4a. Ask the user for budget amount

If not already specified, ask the user: "What monthly budget do you want for this project?" Default suggestion: $10/month for development, $50/month for production.

### 4b. Enable required APIs

```bash
gcloud services enable billingbudgets.googleapis.com --project=<PROJECT_ID>
gcloud services enable pubsub.googleapis.com --project=<PROJECT_ID>
```

### 4c. Create the Pub/Sub topic

```bash
gcloud pubsub topics create budget-notifications --project=<PROJECT_ID>
```

### 4d. Create the budget with Pub/Sub wiring

```bash
# Get the project number
PROJECT_NUMBER=$(gcloud projects describe <PROJECT_ID> --format="value(projectNumber)")

gcloud billing budgets create \
  --billing-account=<BILLING_ACCT_ID> \
  --display-name="<PROJECT_ID> Monthly Budget" \
  --budget-amount=<AMOUNT>USD \
  --filter-projects="projects/${PROJECT_NUMBER}" \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0 \
  --notifications-rule-pubsub-topic="projects/<PROJECT_ID>/topics/budget-notifications"
```

### 4e. Deploy the billing enforcement Cloud Function

Create a file `budgetEnforcement.ts` in the project's Cloud Functions source directory (e.g., `functions/src/`). Read `references/budget_enforcement.md` for the full implementation. The function:

- Subscribes to the `budget-notifications` Pub/Sub topic
- Parses the budget notification JSON
- Disables billing when `costAmount > budgetAmount` (i.e., over 100%)
- Uses `google-auth-library` (already available via firebase-admin) to call the Cloud Billing API

**Critical steps:**
1. Write the `budgetEnforcement.ts` file with the project's actual `PROJECT_ID`
2. Export it from `index.ts`: `export { onBudgetAlert } from './budgetEnforcement';`
3. Build to verify compilation: `cd functions && npm run build`
4. Deploy the new function manually (new functions must be deployed before CI can handle them):
   ```bash
   npx -y firebase-tools@latest deploy --only functions:onBudgetAlert --project=<PROJECT_ID>
   ```

### 4f. Grant billing permissions to the Cloud Functions service account

```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:<PROJECT_ID>@appspot.gserviceaccount.com" \
  --role="roles/billing.projectManager"
```

### 4g. Verify the setup

```bash
# Verify budget exists with Pub/Sub topic
gcloud billing budgets list --billing-account=<BILLING_ACCT_ID>

# Verify function is deployed
gcloud functions list --project=<PROJECT_ID> --filter="name:onBudgetAlert"

# Verify IAM binding
gcloud projects get-iam-policy <PROJECT_ID> \
  --flatten="bindings[].members" \
  --filter="bindings.role:billing.projectManager" \
  --format="table(bindings.role,bindings.members)"
```

### 4h. Clean up duplicate budgets

Check for pre-existing budgets without enforcement and delete them to avoid confusion:

```bash
gcloud billing budgets list --billing-account=<BILLING_ACCT_ID> --format=yaml
# Delete any budget without a pubsubTopic that covers the same project
gcloud billing budgets delete <OLD_BUDGET_ID> --billing-account=<BILLING_ACCT_ID>
```

**Warning:** Disabling billing is a hard stop — ALL paid services shut down. The project must be manually re-linked to restore service. Always identify and fix the cost driver before re-enabling.

---

## Step 5: BigQuery Billing Export Setup

The export must be configured via the GCP Console (no CLI/API support):

1. **Create the BigQuery dataset via CLI:**
   ```bash
   bq --project_id=<PROJECT_ID> mk --dataset --location=US \
     --description="GCP billing export data" <PROJECT_ID>:billing_export
   ```

2. **Grant the billing export service account access:**
   ```bash
   bq update --source /dev/stdin <PROJECT_ID>:billing_export <<'EOF'
   {
     "access": [
       {"role": "WRITER", "specialGroup": "projectWriters"},
       {"role": "OWNER", "specialGroup": "projectOwners"},
       {"role": "READER", "specialGroup": "projectReaders"},
       {"role": "WRITER", "userByEmail": "billing-export-bigquery@system.gserviceaccount.com"}
     ]
   }
   EOF
   ```

3. **Enable in Console:** Go to Billing > Billing export > BigQuery export > Enable standard export. Select the project and `billing_export` dataset.

4. **Wait ~24 hours** for initial data population. Data backfills 1-2 days.

The Console account needs Owner or Editor on the target project for the project to appear in the dropdown.

---

## Step 6: Cost Optimization Recommendations

After identifying the cost driver, apply these patterns:

### Text-to-Speech Optimization
- Cap character count per synthesis (e.g., 5,000 chars max)
- Use Standard voices instead of WaveNet/Neural2 ($4/1M vs $16/1M)
- Cache generated audio aggressively — never re-synthesize
- Add rate limiting per user/article to prevent runaway costs
- Consider pre-generating audio only on explicit user request, not on-demand from RSS

### Cloud Functions Optimization
- Reduce memory allocation where possible (default 256MB vs 1GB)
- Set appropriate timeouts (don't use 540s unless needed)
- Clean up old Artifact Registry images

### Firestore Optimization
- Use `.autoDispose` on StreamProviders to cancel unused listeners
- Avoid `IndexedStack` patterns that keep all listeners alive
- Batch reads where possible

### Storage Optimization
- Set lifecycle rules to auto-delete old audio/PDF files
- Use Nearline/Coldline for infrequently accessed content
- Monitor bucket size growth

---

## Re-enabling Billing After Enforcement Triggers

When the budget enforcement function disables billing:

```bash
# Re-link the billing account
gcloud billing projects link <PROJECT_ID> \
  --billing-account=<BILLING_ACCT_ID>

# Verify
gcloud billing projects describe <PROJECT_ID>
```

Before re-enabling, identify and fix the cost driver to prevent the function from firing again immediately.

---

## Useful Commands Reference

```bash
# List billing accounts
gcloud billing accounts list

# Check project billing status
gcloud billing projects describe <PROJECT_ID>

# List budgets
gcloud billing budgets list --billing-account=<BILLING_ACCT_ID>

# Describe a budget
gcloud billing budgets describe <BUDGET_ID> --billing-account=<BILLING_ACCT_ID>

# Delete a budget
gcloud billing budgets delete <BUDGET_ID> --billing-account=<BILLING_ACCT_ID>

# Check IAM on billing account
gcloud billing accounts get-iam-policy <BILLING_ACCT_ID>

# Add billing admin
gcloud billing accounts add-iam-policy-binding <BILLING_ACCT_ID> \
  --member="user:<EMAIL>" --role="roles/billing.admin"

# Enable an API needed for billing features
gcloud services enable billingbudgets.googleapis.com --project=<PROJECT_ID>
```

---

## Prerequisite APIs

These APIs must be enabled for full cost control functionality:

- `billingbudgets.googleapis.com` — for creating/managing budgets
- `pubsub.googleapis.com` — for budget notification routing
- `cloudbilling.googleapis.com` — for billing account management
- `bigquery.googleapis.com` — for billing export queries
