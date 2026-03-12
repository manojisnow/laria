# Laria — SaaS Conversion Plan

Date: 2025-12-25

Purpose
-------
This document collects the analysis and proposed plan to convert the Laria local/CI security scanning tool into a secure, scalable SaaS offering (with hybrid/on-prem agent options). It mirrors the detailed plan prepared after reviewing the repository and test files, and consolidates design decisions, API examples, architecture, roadmap, costs, risks, staffing, and an actionable checklist for an MVP and near-term roadmap.

Quick task receipt & high-level plan
-----------------------------------
I'll summarize repository confirmations, then present a prioritized SaaS plan and an actionable 90-day checklist. This document is organized so engineers and stakeholders can quickly find API shapes, infra recommendations, security considerations, and the 3–6 month roadmap.

Top-level checklist (what this file contains)
---------------------------------------------
- Confirm repository facts and scope
- High-level SaaS architecture and deployment patterns
- API design, CLI/agent workflow, and JSON examples
- Data model and storage choices; retention and privacy
- Authentication, RBAC, and tenancy isolation strategy
- Scalable scan execution and sandboxing
- Security, observability, and compliance guidance
- Billing and pricing approaches and metering primitives
- Migration roadmap, 3–6 month timeline and milestones
- Rough cost estimate for an MVP scale
- Risks, mitigations, and open questions
- Recommended OSS/commercial components to reuse
- Concrete prioritized action checklist (first 90 days)

Section A — Quick repository confirmations
------------------------------------------
- Statement: "This is a security-related developer tool for local usage and CI pipelines that scans deliverables (Dockerfiles, helm charts, Java JAR/WAR, Maven artifacts, etc)."
  - Confirmed. Evidence: `scanners/` modules including `container_scanner.py`, `helm_scanner.py`, `dependency_scanner.py`, `iac_scanner.py`, `sast_scanner.py`, and `secrets_scanner.py`, plus tests in `tests/` and docs in `docs/`/`README.md`.

- Statement: "It is installable and provides direct installer and uninstaller for macOS and Linux."
  - Confirmed. Evidence: presence of `install.sh`, `uninstall.sh`, `Dockerfile`, `docker-compose.yml`, and `requirements.txt`.

- Statement: "The project is still in alpha stage, and it is not on cloud as a SaaS."
  - Confirmed / very likely. Evidence: no hosted/cloud control plane code, no billing/SSO modules, no SaaS manifests. Repository is focused on local and CI usage.

Section B — High-level SaaS architecture and deployment patterns
----------------------------------------------------------------
Core components (logical):
- API Gateway / HTTPS frontend (rate-limits, WAF)
- Backend API service (REST/GraphQL; recommended: FastAPI or Go) exposing OpenAPI
- Auth & Identity (OIDC, SAML, API keys, SCIM)
- Worker fleet (Kubernetes) running scanner images (Trivy, Semgrep, custom)
- Task Queue (SQS / RabbitMQ) for scan jobs
- Metadata DB (Postgres / RDS) with Row-Level Security
- Blob store (S3-compatible) for artifacts and reports
- Search & index (OpenSearch) for findings
- Redis for caching and short-lived state
- Secrets (Vault / Cloud KMS)
- Observability (Prometheus, Grafana, Loki/ELK, OpenTelemetry)
- Web UI (React/Next.js)
- CLI/Agent (Go or Python) for local and on-prem scanning
- Billing subsystem (Stripe integration)

Deployment patterns and tenancy options:
- Multi-tenant SaaS control plane (MVP): shared control plane, logical separation via org_id and Postgres RLS.
- Single-tenant (Enterprise): dedicated DB, KMS, and worker pools per customer.
- Hybrid/on-prem agent: lightweight agent that runs locally (push model) or accepts tasks (pull model) so customers need not upload artifacts to the cloud.

Section C — API design and CLI/agent integration
-----------------------------------------------
API principles:
- RESTful JSON v1 with OpenAPI v3 spec and API versioning.
- Auth via JWT for users and short-lived bearer tokens for agents; API keys for CI.
- Provide both synchronous small-scan endpoints and asynchronous job-based endpoints.
- Webhooks for lifecycle events and HMAC signatures for verification.

Core endpoints (summary):
- POST /api/v1/orgs
- POST /api/v1/orgs/{org_id}/projects
- POST /api/v1/orgs/{org_id}/projects/{project_id}/scans
- POST /api/v1/scans/{scan_id}/stop
- GET /api/v1/scans/{scan_id}
- GET /api/v1/reports/{report_id}
- GET /api/v1/findings
- POST /api/v1/webhooks
- POST /api/v1/agents/register

Start scan (concise JSON example):
{
  "scan_type": "container_image",
  "target": "registry.example.com/myapp:1.2.3",
  "tools": ["trivy","semgrep"],
  "policy": "default",
  "priority": "normal",
  "artifact_upload": false,
  "callback_url": "https://hooks.example.com/laria"
}

Scan accepted response (202): scan_id, status, timestamps.

Webhook example (scan.completed): includes scan_id, org_id, project_id, findings_summary, and report_url. Sign with HMAC.

CLI/Agent workflows (patterns):
- Remote CI: CLI calls API with registry pointer; remote workers pull image and scan.
- Local quick scan: agent runs locally and uploads report via presigned S3 or sends results to control plane.
- Agent registration & heartbeat: agent obtains short-lived token, registers capabilities, long-polls for jobs or uses websocket.

Section D — Data model and storage choices
-----------------------------------------
Primary entities:
- organizations, users, projects, scans, findings, artifacts, agents, billing/usage, policies.

Storage choices:
- Postgres for relational metadata (RDS/Aurora)
- S3 for artifacts & reports (SSE-KMS)
- OpenSearch for indexing findings and advanced search
- Redis for cache, rate-limits, and short-lived tokens
- SQS or RabbitMQ for durable job queues
- Vault + Cloud KMS for secrets

Retention & privacy:
- Default retention: artifacts 90 days, reports/archives 90 days, metadata 365 days (configurable per org).
- Minimize PII; redact or hash sensitive fields; provide export and deletion endpoints for GDPR/CCPA.
- For EU customers, offer regional deployments/data residency.

Section E — Authentication & authorization
------------------------------------------
Authentication:
- OIDC & SAML for SSO (enterprise)
- API keys (org/project-scoped), OAuth2 client-credentials for CI, JWTs for user sessions
- MFA for user accounts (TOTP)

Authorization:
- RBAC roles: Org Owner, Org Admin, Project Admin, Developer, Auditor
- API key scopes (read:reports, write:scans, admin:org)
- Use Postgres RLS + app-layer checks to enforce org scoping

Section F — Multi-tenancy design and tenancy isolation strategy
---------------------------------------------------------------
Phased approach:
- Phase 1 (MVP): shared schema multi-tenant with Postgres RLS and strict middleware enforcement.
- Phase 2: per-tenant schema or logical separation of indexes; per-tenant encryption keys on higher tiers.
- Enterprise: dedicated DB + dedicated worker pool + VPC peering.

Compute/data isolation:
- Use per-tenant S3 prefixes and bucket policies.
- Worker isolation via Kubernetes namespaces and network policies; optionally run per-tenant node pools for enterprise.

Section G — Scalable scan execution
-----------------------------------
Worker model:
- API enqueues job; durable queue distributes jobs to worker pool.
- Workers implemented as K8s Jobs or long-lived pods (with autoscaling based on queue depth).
- Resource classes: small/medium/large workers for lightweight vs heavy scans.

Sandboxing & isolation:
- Use gVisor, Kata Containers, or Firecracker for stronger isolation.
- Apply seccomp, AppArmor, user namespace remapping, and resource limits.
- Limit outbound network access for worker processes.

Artifact handling:
- Offer presigned S3 uploads, or temporary registry credentials for workers to pull images.
- Cache common scanner databases (Trivy DB) in shared cache to reduce worker runtime.

Section H — Security, compliance, and hardening
-----------------------------------------------
Network & infra controls:
- Private subnets for DB and workers; strictly controlled public endpoints.
- WAF & rate-limiting at the edge; DDoS protection; strict ingress rules.

Secrets & key management:
- Centralized secrets in Vault; per-tenant KMS keys for higher tiers.
- Rotate API keys and service credentials regularly.

Application & infra security:
- Harden K8s cluster (least privilege service accounts, network policies, PodSecurity admission controls).
- Regular dependency scanning, container image scanning for all deployed images.
- Pen-testing and bug bounty program for continuous testing.

Compliance readiness:
- DPA and documented data flows for GDPR.
- Audit trails for user and admin actions; retention policies for logs.

Section I — Observability: metrics, logging, tracing, alerting
-------------------------------------------------------------
- Metrics: Prometheus for API & worker metrics; separate dashboards per environment.
- Logs: structured logs shipped to Loki/ELK with retention and role-based access.
- Tracing: OpenTelemetry across API & worker flows.
- Alerting: Alerts to PagerDuty for P1; Slack for lower-severity notifications.
- SLOs: API availability 99.9%; queue median start time < 30s under nominal load.

Section J — Billing, metering, and pricing models
------------------------------------------------
Metering primitives:
- Scan count (per-tool execution counts)
- Compute time (worker seconds)
- Storage (GB-month)
- Seats (active user accounts)
- Agents (registered agent count)

Pricing models:
- Freemium: limited free scans per month
- Per-scan pricing: $x per scan, or discounts at volume
- Seat + usage: base per-seat monthly fee + discounted per-scan usage
- Tiered plans and enterprise contracts with dedicated infra

Billing integration:
- Stripe for card payments & invoicing; support net-30 invoicing for large customers.
- Metering pipeline: aggregate daily usage and produce monthly invoice drafts.

Section K — Migration path from current repo to SaaS (MVP roadmap)
-----------------------------------------------------------------
Assumptions (explicit):
1. Prioritize Trivy (vulnerability scanning) and Semgrep (SAST/IaC) for MVP.
2. Default retention: artifacts 90 days; metadata 365 days.

MVP scope (3 months):
- Multi-tenant API + Postgres + S3
- Worker queue + K8s workers running Trivy & Semgrep
- CLI to trigger remote scans and artifact upload
- Basic Web UI & JSON report download
- API keys, webhooks, and basic observability

3–6 month expansion:
- SSO (OIDC/SAML), SCIM provisioning
- Billing integration (Stripe) + usage dashboard
- OpenSearch for findings search
- On-prem agent and enterprise tenancy features

Milestones (high-level weeks):
- Week 0–2: Project setup, OpenAPI skeleton, IaC skeleton
- Week 2–6: API + DB schema + S3 integration + basic UI
- Week 6–10: Queue + worker + Trivy & Semgrep runner images
- Week 10–14: CLI/agent v1 + webhooks + report viewer
- Week 14–18: Observability & security hardening
- Week 18–24: Billing stub + Stripe + pilot launch

Section L — CI/CD, IaC, and cloud provider recommendations
---------------------------------------------------------
CI/CD:
- Use GitHub Actions or GitLab CI for build and deploy pipeline.
- Protect branches with policy checks and SCA scanning.

IaC & deployment:
- Terraform for cloud resources; Helm for in-cluster deployments.
- Remote terraform state (S3 backend + DynamoDB locking or Terraform Cloud).

Cloud provider recommendations:
- Primary: AWS (EKS, RDS/Aurora, S3, SQS) for managed services and ecosystem.
- Alternatives: GCP (GKE, Pub/Sub) or Azure (AKS) depending on customer preference.

Section M — Estimated costs (ballpark for MVP)
-----------------------------------------------
Assumptions:
- 50 orgs, 5 scans/org/day → 250 scans/day → ~91k scans/year
- Average scan runtime 5 minutes; worker resource ~0.5 vCPU, 1GB RAM per scan.

Estimated annual costs (very rough): $34k — $112k. Recommend planning $50k–$100k for Year 1 MVP operations and a 20% buffer.

Section N — Risks, mitigations, and open questions
--------------------------------------------------
Top risks & mitigations:
- Running untrusted code: use sandboxing (gVisor/Firecracker/Kata), ephemeral workers, strict timeouts.
- Data leakage: per-tenant S3 prefixes, encryption, minimal retention, and strict access control.
- Cost spikes: rate-limits, quotas, usage-based pricing, autoscaling limits.
- Customer unwillingness to upload artifacts: prioritize on-prem agent and hybrid flows.

Open questions:
- Which scanners beyond Trivy & Semgrep are essential for early customers?
- Data residency requirements for pilot customers?
- Acceptable retention limits and legal constraints.

Section O — Recommended open-source / commercial components to reuse
--------------------------------------------------------------------
Open-source:
- Trivy (vulnerability scanning)
- Semgrep (SAST / IaC rules)
- Falco (runtime security)
- gVisor / Kata / Firecracker (sandboxing)
- Prometheus, Grafana, Loki, OpenTelemetry (observability)
- OpenSearch (findings search)

Commercial integrations:
- Auth0 / Okta (SSO if not building in-house)
- Stripe (billing)
- Elastic Cloud (managed Elasticsearch) or OpenSearch managed alternatives

Licensing note: prefer permissive OSS licenses for core components; consider OpenSearch to avoid Elastic license complications.

Section P — Developer experience and integrations
-------------------------------------------------
- Publish OpenAPI docs (interactive) and provide quickstart guides.
- Build SDKs (Python & Go initially) and CI templates (GitHub Actions/GitLab CI).
- Provide GitHub App and status check integration for PR scanning.
- Provide Slack/MS Teams notification integrations and webhooks.

Section Q — Legal, compliance & privacy checklist for SaaS
----------------------------------------------------------
Minimum items before paid beta:
- Terms of Service, Privacy Policy, Data Processing Agreement (DPA)
- Data deletion & export APIs
- Incident response plan and notification process
- Penetration testing schedule and bug disclosure policy
- SOC2 readiness checklist and basic controls

Section R — MVP scope & prioritized checklist (concise)
--------------------------------------------------------
Priority 1 — Must have (MVP):
- API: orgs, projects, start/stop scans, scan status, download JSON report
- Workers: Trivy + Semgrep runner images and orchestration
- Storage: Postgres for metadata, S3 for artifacts
- Auth: API keys & basic user auth
- CLI: remote scan starter & artifact upload
- Web UI: minimal dashboard and report viewer
- Webhooks: scan.completed event
- Observability: Prometheus basic + logs
- Security basics: TLS, Vault/KMS, secret rotation
- Billing stub: usage CSV export for now

Priority 2 — Post-MVP (beta):
- SSO (OIDC/SAML), SCIM provisioning
- Billing integration (Stripe)
- OpenSearch for findings & search
- On-prem agent and hybrid mode

Priority 3 — Enterprise:
- Dedicated tenancy options and per-tenant KMS
- SLA, advanced policy editor, PDF exports, enterprise support

Section S — Concrete endpoints, data shapes & examples
------------------------------------------------------
Start scan (POST): /api/v1/orgs/{org}/projects/{project}/scans
Input fields:
- scan_type: container_image | dockerfile | helm | sast | iac
- target: registry URL, repo URL, or artifact pointer
- tools: ["trivy","semgrep"]
- priority: low|normal|high
- callback_url: optional webhook
- artifact_upload: boolean

Scan status (GET): /api/v1/scans/{scan_id} returns status and findings summary

Report JSON shape:
{
  "report_id": "report_01F",
  "scan_id": "scan_01F",
  "generated_at": "2025-12-25T12:10Z",
  "findings": [ { "id": "f_0001", "rule_id": "TRIVY-CVE-2025-1234", "severity": "HIGH", "description": "...", "path": "/app/..." } ]
}

Webhook event types: scan.queued, scan.started, scan.completed, scan.failed (deliver HMAC signed payloads).

Section T — Sample CLI/agent workflow and example commands
---------------------------------------------------------
1) Quick remote scan (CI):
- Command: `laria scan start --org 123 --project 456 --type container_image --target registry.example.com/foo:1.0 --tools trivy,semgrep --api-key <key>`
- Behavior: CLI calls POST start-scan and returns scan_id and poll URL.

2) Local upload + remote scan:
- Command: `laria scan upload --file ./artifact.tar.gz --org 123 --project 456 --tools trivy --api-key <key>`
- Behavior: CLI requests a presigned S3 URL from API, uploads artifact, then triggers scan with artifact pointer.

3) Agent register & worker loop:
- Register: `laria agent register --org 123 --name agent-01 --api-key <org-key>`
- Worker loop: authenticate, long-poll tasks, run scan in sandbox, upload report to S3, POST completion status.

Section U — Risks recap, mitigations & open questions
-----------------------------------------------------
- Untrusted code execution: sandboxing, timeouts, and strict network egress rules.
- Data privacy: per-tenant encryption, data deletion APIs.
- Cost: rate limiting, quotas, autoscaling limits, pricing with overages.
- Customer constraints: on-prem agent for customers who do not permit cloud uploads.

Section V — Final prioritized action checklist (first 90 days)
---------------------------------------------------------------
1. Project kickoff: stack decisions, infra account setup, IaC repo.
2. Implement OpenAPI spec and server skeleton.
3. Postgres schema + RLS + migrations.
4. S3 artifact lifecycle & presigned upload flow.
5. Worker + queue + Trivy/Semgrep runners and end-to-end flow.
6. CLI to start scans and upload artifacts.
7. Minimal Web UI to view scan results and download JSON.
8. Observability + logging pipeline.
9. Basic security controls (Vault/KMS, TLS, secrets rotation).
10. Pilot with 3–5 customers; iterate.

Section W — Staffing / hiring priorities
---------------------------------------
Immediate hires:
- Backend (2 FTE), DevOps/SRE (1 FTE), Security (0.5 FTE), Frontend (0.5–1 FTE), QA (0.5 FTE), Product (0.5 FTE)

Section X — Legal / compliance checklist
----------------------------------------
- Publish TOS & Privacy Policy
- DPA for enterprise customers
- Data deletion & export APIs
- Incident response plan and pen-test schedule
- SOC 2 readiness plan

Section Y — Two reasonable assumptions (explicit)
-------------------------------------------------
1. Prioritize Trivy and Semgrep for MVP scanners.
2. Default retention: artifacts 90 days; metadata 365 days.

Section Z — Summary of deliverables & next steps
-------------------------------------------------
Deliverables included in this plan:
- Repository confirmations
- High-level SaaS architecture and deployment patterns
- API design + concrete endpoints + JSON examples
- CLI/agent workflows and sample commands
- Data model & storage recommendations, PII/GDPR considerations
- Auth & RBAC design, multi-tenancy recommendations
- Scalable execution model and sandboxing options
- Security, compliance, observability, and billing recommendations
- Migration roadmap and prioritized 3–6 month timeline
- Staffing and cost ballpark estimate
- Risks, mitigations, open questions, OSS/commercial recommendations
- Actionable prioritized checklist for MVP

Recommended immediate next step: generate an OpenAPI v3 spec for the core API along with a worker/agent contract (JSON schemas) so engineers can implement server, client, and agent in parallel.

If you'd like, I can now:
- Produce the OpenAPI YAML spec in this repo under `docs/openapi.yaml` (then generate server/client stubs).
- Create a JSON contract for agent-worker jobs under `docs/agent_contract/`.
- Scaffold Terraform + Helm skeleton under `infra/` for a baseline deploy.

Tell me which of the three to generate first and I will create the files and validate them.
