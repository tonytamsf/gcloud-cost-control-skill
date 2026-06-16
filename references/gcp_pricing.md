# GCP Service Pricing Reference (2026)

Quick reference for common GCP services used in Firebase projects. All prices are pay-as-you-go USD.

## Cloud Text-to-Speech API

| Voice Type | Price per 1M chars | Free Tier |
|---|---|---|
| Standard | $4.00 | 4M chars/month |
| WaveNet | $16.00 | 1M chars/month |
| Neural2 | $16.00 | 1M chars/month |
| Studio | $160.00 | 100K chars/month |

**Cost driver:** Full article text synthesis. A 10,000-char article at Neural2 = $0.16 per synthesis. 700 articles = $112.

## Cloud Functions (1st Gen)

| Resource | Price | Free Tier |
|---|---|---|
| Invocations | $0.40/1M | 2M/month |
| Compute (GB-second) | $0.0000025 | 400K GB-sec/month |
| Compute (GHz-second) | $0.0000100 | 200K GHz-sec/month |
| Networking (egress) | $0.12/GB | 5GB/month |

**Cost driver:** Functions with high memory (1GB) and long execution times (Puppeteer, TTS synthesis).

## Cloud Storage

| Class | Storage $/GB/mo | Retrieval $/GB |
|---|---|---|
| Standard | $0.020 | $0.00 |
| Nearline | $0.010 | $0.01 |
| Coldline | $0.004 | $0.02 |
| Archive | $0.0012 | $0.05 |

Free tier: 5GB Standard storage, 1GB egress/month.

**Cost driver:** Audio files (MP3), PDF files, container images in Artifact Registry.

## Firestore

| Operation | Price | Free Tier |
|---|---|---|
| Document reads | $0.06/100K | 50K/day |
| Document writes | $0.18/100K | 20K/day |
| Document deletes | $0.02/100K | 20K/day |
| Storage | $0.18/GB | 1GB |

**Cost driver:** Real-time listeners that re-read on every change. `IndexedStack` keeping all tabs alive multiplies reads.

## Generative Language API (Gemini)

| Model | Input $/1M tokens | Output $/1M tokens |
|---|---|---|
| gemini-2.5-flash | $0.15 | $0.60 |
| gemini-2.5-pro | $1.25 | $10.00 |

API key billing goes through the GCP project the key is associated with.

## Artifact Registry

| Resource | Price |
|---|---|
| Storage | $0.10/GB/month |
| Egress | same as Cloud Storage |

**Cost driver:** Docker images from Cloud Function deployments accumulate. Clean up old versions.

## Firebase Hosting

Free tier: 10GB storage, 360MB/day transfer. Paid: $0.026/GB stored, $0.15/GB transferred.

## Cloud Build

Free tier: 120 build-minutes/day. Paid: $0.003/build-minute.

## Cloud Logging

Free tier: 50GB/month. Paid: $0.50/GB ingested above free tier.

## Pub/Sub

Free tier: 10GB/month. Paid: $0.04/GB after free tier.
