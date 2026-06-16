# gcloud-cost-control

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill for analyzing and controlling Google Cloud Platform costs. It provides guided workflows for cost investigation, budget enforcement with automatic billing shutoff, BigQuery billing export setup, and cost optimization — all driven through the `gcloud` CLI.

## What It Does

- **Cost investigation** — breaks down spending by service and SKU using BigQuery billing exports or usage-based estimation when no export exists
- **Budget enforcement** — creates GCP budgets wired to a Pub/Sub-triggered Cloud Function that automatically disables billing when costs exceed the limit
- **Billing export setup** — walks through configuring BigQuery billing exports for granular cost data
- **Cost optimization** — identifies common cost drivers (Text-to-Speech, Cloud Functions, Firestore, Storage) and recommends specific fixes
- **Cost analysis script** — a standalone shell script that audits a project's resource usage across functions, storage, APIs, and budgets

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `gcloud` CLI authenticated with access to your GCP billing account
- `bq` CLI (included with gcloud SDK) for BigQuery queries
- Sufficient IAM permissions: `roles/billing.admin` or `roles/billing.viewer` on the billing account

## Installation

Clone this repo into your Claude Code skills directory:

```bash
git clone https://github.com/tonytamsf/gcloud-cost-control-skill.git \
  ~/.claude/skills/gcloud-cost-control
```

Or, if you already have a skills directory and want to add it manually:

```bash
mkdir -p ~/.claude/skills
cp -R gcloud-cost-control-skill ~/.claude/skills/gcloud-cost-control
```

Claude Code will automatically discover the skill from the `SKILL.md` file.

## Usage

Once installed, trigger the skill in Claude Code by asking about GCP costs. The skill activates on phrases like:

- "How much am I spending on GCP?"
- "What's driving my cloud bill?"
- "Set a budget for my project"
- "Break down costs for `project-id`"
- "Set up billing export"

### Analyze Costs

Ask Claude to analyze a specific project:

```
What are the costs for my-project-id over the last 7 days?
```

Claude will check for BigQuery billing exports first, fall back to usage-based estimation if none exist, and present a breakdown by service.

### Set Up Budget Enforcement

Ask Claude to set up a budget with automatic shutoff:

```
Set a $25/month budget for my-project-id with auto-enforcement
```

This will:
1. Enable required APIs (`billingbudgets`, `pubsub`)
2. Create a Pub/Sub topic for budget notifications
3. Create a budget with 50%, 90%, and 100% threshold alerts
4. Deploy a Cloud Function that disables billing when costs exceed the budget
5. Grant the necessary IAM permissions

### Run the Analysis Script Directly

The included shell script can be run standalone:

```bash
# Analyze last 30 days (default)
./scripts/analyze_costs.sh my-project-id

# Analyze last 7 days
./scripts/analyze_costs.sh my-project-id 7
```

It reports on Cloud Functions invocations/execution times, storage bucket sizes, Artifact Registry usage, billable APIs, and existing budgets.

## File Structure

```
gcloud-cost-control/
├── SKILL.md                          # Skill definition and workflows
├── README.md                         # This file
├── references/
│   ├── gcp_pricing.md                # GCP service pricing reference (2026)
│   └── budget_enforcement.md         # Budget enforcement Cloud Function code
└── scripts/
    └── analyze_costs.sh              # Standalone cost analysis script
```

## Important Notes

- **Disabling billing is a hard stop.** When the enforcement function triggers, ALL paid services on the project cease immediately. Re-enable with `gcloud billing projects link`.
- **Budget notifications can be delayed** by several hours. Costs may exceed the budget before the function fires.
- **BigQuery billing export takes ~24 hours** to populate after initial setup.
- **Always fix the cost driver** before re-enabling billing, or the enforcement function will fire again.

## License

MIT
