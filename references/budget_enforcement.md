# Budget Enforcement Cloud Function

A Pub/Sub-triggered Cloud Function that disables billing when costs exceed the budget.

## Implementation (TypeScript — Firebase Cloud Functions)

```typescript
import * as functions from 'firebase-functions';
import { GoogleAuth } from 'google-auth-library';
import { Logging } from '@google-cloud/logging';

const PROJECT_ID = '<YOUR_PROJECT_ID>';
const PROJECT_NAME = `projects/${PROJECT_ID}`;
const BILLING_API = 'https://cloudbilling.googleapis.com/v1';

const logging = new Logging({ projectId: PROJECT_ID });

async function writeBillingDisabledAlert(
  costAmount: number,
  budgetAmount: number
): Promise<void> {
  const log = logging.log('billing-enforcement');
  const entry = log.entry(
    {
      resource: { type: 'cloud_function', labels: { function_name: 'onBudgetAlert', region: 'us-central1' } },
      severity: 'CRITICAL',
      labels: { event: 'billing_disabled', project: PROJECT_ID },
    },
    {
      message: `BILLING DISABLED: Cost ($${costAmount}) exceeded budget ($${budgetAmount}) for project ${PROJECT_ID}. All Cloud Functions are now offline. Re-enable billing manually: gcloud billing projects link ${PROJECT_ID} --billing-account=ACCOUNT_ID`,
      costAmount,
      budgetAmount,
      projectId: PROJECT_ID,
      action: 'billing_disabled',
    }
  );
  await log.write(entry);
}

export const onBudgetAlert = functions.pubsub
  .topic('budget-notifications')
  .onPublish(async (message) => {
    const data = JSON.parse(
      Buffer.from(message.data, 'base64').toString()
    );

    console.log('Budget alert received:', JSON.stringify(data));

    const costAmount = data.costAmount ?? 0;
    const budgetAmount = data.budgetAmount ?? 0;

    if (costAmount <= budgetAmount) {
      console.log(
        `Cost ($${costAmount}) is within budget ($${budgetAmount}). No action taken.`
      );
      return;
    }

    console.warn(
      `Cost ($${costAmount}) EXCEEDS budget ($${budgetAmount}). Disabling billing.`
    );

    const auth = new GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/cloud-billing'],
    });
    const client = await auth.getClient();

    const res = await client.request({
      url: `${BILLING_API}/${PROJECT_NAME}/billingInfo`,
      method: 'PUT',
      data: { billingAccountName: '' },
    });

    console.warn(
      `Billing disabled for ${PROJECT_ID}. Response: ${JSON.stringify(res.data)}`
    );

    await writeBillingDisabledAlert(costAmount, budgetAmount);
  });
```

## Dependencies

Add `@google-cloud/logging` to your functions `package.json`:

```bash
cd functions && npm install @google-cloud/logging
```

## Budget Notification Payload

The Pub/Sub message `data` field (base64-decoded) contains:

```json
{
  "budgetDisplayName": "Read-N-Replay Monthly Budget",
  "alertThresholdExceeded": 1.0,
  "costAmount": 112.51,
  "costIntervalStart": "2026-06-01T07:00:00Z",
  "budgetAmount": 10.0,
  "budgetAmountType": "SPECIFIED_AMOUNT",
  "currencyCode": "USD"
}
```

- `alertThresholdExceeded` — the threshold that was crossed (0.5, 0.9, or 1.0)
- `costAmount` — actual spend so far this period
- `budgetAmount` — the configured budget limit
- The function only acts when `costAmount > budgetAmount`

## Required Permissions

The Cloud Functions service account needs `roles/billing.projectManager` on the project:

```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:<PROJECT_ID>@appspot.gserviceaccount.com" \
  --role="roles/billing.projectManager"
```

## Deployment

```bash
# First-time deploy (new functions must be deployed manually before CI can handle them)
npx -y firebase-tools@latest deploy --only functions:onBudgetAlert --project=<PROJECT_ID>
```

## Email Alert Setup

After deploying the function, set up a GCP Monitoring alert so the billing admin gets emailed when billing is disabled:

```bash
# 1. Create email notification channel
CHANNEL_ID=$(gcloud beta monitoring channels create \
  --project=<PROJECT_ID> \
  --display-name="Billing Admin" \
  --type=email \
  --channel-labels=email_address=<ADMIN_EMAIL> \
  --format='value(name)')

# 2. Create log-based alert policy (see SKILL.md Step 4i for full JSON)
gcloud alpha monitoring policies create \
  --project=<PROJECT_ID> \
  --policy-from-file=/tmp/billing-alert-policy.json
```

The alert fires on the CRITICAL log entry written by `writeBillingDisabledAlert()`, which includes the cost/budget amounts and the re-enable command. The alert is rate-limited to once per 5 minutes to avoid spam.

## Important Notes

- Disabling billing is a **hard stop** — all paid services cease immediately (Cloud Functions return 503)
- The function fires on EVERY budget notification after the threshold is crossed, not just once
- Budget notifications can be delayed by several hours — costs may exceed the budget before the function fires
- The CRITICAL log + email alert is written BEFORE billing is fully disabled, ensuring the notification gets through
- To re-enable: `gcloud billing projects link <PROJECT_ID> --billing-account=<BILLING_ACCT_ID>`
- Fix the cost driver BEFORE re-enabling, or the function will fire again
