---
title:   "Cloud Vault Deployment — Architecture Decision Record"
type:    decision-record
status:  active
tags:    [obsidian-base, cloud, mcp, security, hipaa, architecture]
created: 2026-07-21
updated: 2026-07-21
confidence: medium
sources: 18
related:
  - "[[onedrive-sensitive-plane-setup-gotchas]]"
  - "[[connect-github-naming-parity-and-push-resilience]]"
---

# Cloud Vault Deployment — Architecture Decision Record

## TL;DR

Add an **opt-in cloud deployment module** to obsidian-base: any vault derived from
the template *can* be deployed to Amazon Web Services (AWS) and exposed as an
authenticated, read/write **Model Context Protocol (MCP)** endpoint, so people reach
their knowledge base (KB) from Claude/ChatGPT anywhere and autonomous maintenance
(e.g. `/vault-dream`) runs unattended in the cloud. Local-only vaults change **nothing**.
The design: a **narrow markdown-only MCP server** (no cloud Obsidian, no document
parsing) composed alongside the native Microsoft 365 (M365) / Google Drive MCPs;
**Fargate-first hosting** with a clean migration path to Bedrock AgentCore; a
**three-tier data-control ladder** (shareable → confidential → protected health
information, PHI) that keeps ~90% of usage on existing Claude subscriptions while
routing confidential/PHI inference to commercial-terms or Business Associate
Agreement (BAA)-covered rails; and the `_sensitive/` plane retained as the
**enforced routing boundary** that makes all of this hold. **Firm IP control is a
governing principle**: consumer-tier LLM terms are never acceptable for firm
knowledge beyond the de-identified Shareable plane.

## Key decisions

1. **Narrow KB MCP server, composed with native MCPs.** Our server does markdown
   vault operations only: read, write, search, frontmatter queries, computed
   backlinks. Direct-to-disk atomic writes (write-temp-then-rename); no Obsidian
   process in the cloud — links and frontmatter live *in the files*, so nothing is
   lost, and the only Obsidian-runtime features forgone (live Dataview index,
   structure-aware PATCH) are recomputable or unneeded. Raw work documents
   (Word/Excel/PDF) stay in OneDrive/Google Drive and are read by the **native
   M365/Drive MCPs** under the provider's existing terms — our server never parses
   Office documents. Ingest skills orchestrate across both servers. Reference
   design: [obsidian-web-mcp](https://github.com/jimprosser/obsidian-web-mcp)
   (direct-to-disk, OAuth 2.0 + PKCE, atomic writes; lacks backlinks and git — we add both).
2. **Two write modes, one tree owner.** Interactive edits (a person via their LLM)
   → the server writes and commits to `main`, audit-logged — the cloud equivalent
   of a person typing in Obsidian. Autonomous jobs (dreaming, consolidation) →
   always a branch + pull request (PR), never `main` — unchanged from the existing
   dream rails. The cloud server is the **single process** that touches the working
   tree and runs git, eliminating the multi-writer race.
3. **Fargate first; AgentCore is a later module swap, not a rewrite.** Amazon
   Elastic Container Service (ECS) Fargate is mature, boring, and operator-familiar.
   Bedrock AgentCore Runtime is deferred on **maturity grounds, not cost** — at
   bursty small-team duty cycles AgentCore is actually cheaper (idle/input-output
   wait is free; no load balancer needed); Fargate wins only when busy >~half the
   time. What deferral forgoes: per-session micro-virtual-machine isolation,
   idle-free billing, the managed endpoint, and the Identity outbound token vault —
   the last of which lost most of its value once our server stopped reading Drive
   (its only outbound credential is a git deploy key). Migration stays clean iff we
   hold a **container contract**: stateless image in Elastic Container Registry
   (ECR), Streamable HTTP MCP with port/path from environment variables, all state
   external (Elastic File System (EFS) / git / Secrets Manager), and inbound auth =
   JSON Web Token (JWT) validation against a configurable OpenID Connect (OIDC)
   issuer — Cognito works identically fronting Fargate or as AgentCore's JWT
   authorizer, so the auth investment carries over untouched.
4. **Auth: OAuth 2.1 + PKCE against Cognito, with scope-enforced sensitivity.** The
   MCP spec (Nov 2025 revision) effectively mandates OAuth 2.1 + Proof Key for Code
   Exchange (PKCE) for internet-facing servers. A thin MCP-OAuth shim
   (`.well-known` metadata, dynamic client registration) is needed regardless of
   host. **Scopes enforce the data tiers**: a `sensitive` scope is granted only to
   org-verified (commercial-terms) identities; consumer-tier clients never receive
   `_sensitive/` content — the server filters on `classification:` frontmatter. The
   sensitivity boundary graduates from convention to an **API-enforced control**.
5. **Firm IP control — the data-control ladder (governing principle).** Transport
   security is table stakes everywhere; what differs is **contractual control**
   over training use, retention, and deletion. Verified as of July 2026:
   consumer Claude (Free/Pro/Max) trains on chats **unless opted out**, retains up
   to 5 years opted-in, and a June 2026 policy carve-out permits use of
   safety-flagged conversations even when opted out; consumer ChatGPT trains by
   default. Commercial tiers (Claude Team/Enterprise, ChatGPT Business/Enterprise,
   both APIs) do **not** train, carry a Data Processing Agreement (DPA), and offer
   short/zero retention. **Bedrock is maximal control: the bytes never leave the
   firm's AWS account** — Anthropic never receives them. The ladder:
   **Shareable (de-identified) → any client, incl. consumer subscriptions.
   Confidential (NDA/financial/firm IP) → commercial-terms subscription seats or
   API only. PHI → BAA-covered rails only (HIPAA-ready Enterprise, BAA'd API, or
   Bedrock).**
6. **Billing seam: the split is non-PHI vs PHI, not interactive vs automated.**
   Interactive use rides users' existing Claude subscriptions. Automation can too:
   Anthropic **Routines** run scheduled Claude Code jobs on managed cloud and draw
   the *subscription* pool (Pro 5/day, Max 15/day, Team/Enterprise 25/day, hourly
   minimum). So the entire non-PHI column — interactive *and* scheduled — is
   ≈zero marginal token cost. Anything touching PHI must leave subscription rails
   (no BAA there) for Bedrock under the AWS BAA or a HIPAA-ready Anthropic path.
7. **The `_sensitive/` plane is retained — repurposed, not retired.** Even with
   full BAA coverage available, the plane remains because (a) GitHub is still not a
   business associate — PHI/confidential must stay off git; (b) the Health
   Insurance Portability and Accountability Act (HIPAA) minimum-necessary rule and
   plain access control need a boundary independent of who holds a BAA; (c) it is
   **economically load-bearing** — it is what keeps most usage on free subscription
   rails by routing only sensitive operations to paid covered inference.
8. **HIPAA posture: compliant-by-construction on the technical layer.** One-click,
   free, **org-wide AWS BAA via AWS Artifact** (all current and future accounts);
   150+ HIPAA-eligible services including Bedrock **and AgentCore** (eligible as of
   2026-02-10); AWS Control Tower auto-enables the AWS Config "Operational Best
   Practices for HIPAA Security" conformance pack for continuous drift detection.
   **Financial/NDA confidential data is legally distinct from PHI but ~90%
   infra-identical** — build one "confidential tier"; PHI mode is a configuration
   superset (accept org BAA + route server-side inference to Bedrock), not a
   second system.

## Details

### Content model

Humans primarily author **work documents in their cloud drives**, not markdown in
Obsidian. The vault is the **synthesis + navigation layer**: distilled, cross-linked,
frontmatter-tagged notes that make the document corpus queryable, plus agent working
memory. Notes reference source documents as pointers (the existing reference-note
pattern); following a pointer means the agent switches to the native provider MCP.
Obsidian remains the local human cockpit; it is not required anywhere in the cloud path.

### Deployment shape

Two deployables sharing one repo, one EFS, and one auth layer:
- **Interactive KB MCP server** (always-on or AgentCore-bursty): the single tree
  owner; serves reads/writes to authenticated clients.
- **Autonomous runner** (scheduled): runs skills like `/vault-dream` headlessly;
  writes only branches + PRs. Prefer Anthropic Routines (subscription-billed) for
  non-PHI vaults; a scheduled Fargate/AgentCore task with Bedrock for PHI vaults.

Delivered following the existing opt-in cloud-module pattern
(`/setup-sensitive-plane`, `/connect-github`): a Pulumi program under an engine
path + a hand-authored `/deploy-cloud-mcp` skill that owns judgment (tier choice,
region, BAA acknowledgment gate) and records a no-secrets block in
`.agents/vault-profile.md`. Propagated by `update-base`; inert until run — "every
vault has the capability, only opted-in vaults have a deployment."

### Cost (verified rates, July 2026; estimates are speculation)

- Fargate floor ≈ **$38/mo** (0.5 vCPU/1 GB ≈ $18 + Application Load Balancer ≈ $20).
- AgentCore bursty ≈ **$5–15/mo** ($0.0895/vCPU-hr + $0.00945/GB-hr active only;
  Gateway $0.005/1k invocations; Identity free). Crossover ≈ 50% duty cycle.
- Shared fixed: Network Address Translation (NAT) gateway ~$33/mo *(replaceable
  with ~$7 VPC endpoints)*, KMS/Secrets/CloudTrail ~$3–10/mo, EFS <$1 (markdown).
- **Model tokens ≈ $0 for non-PHI** (subscriptions + Routines); PHI inference is
  token-billed on Bedrock/API. Estimated all-in infra: **$30–150/mo per deployment**.
- The dominant real cost is the **HIPAA administrative program**, not servers.

## Recommendations (next steps, in order)

1. **Auth spike (~1 day):** hello-world MCP behind Cognito + OAuth shim; prove a
   real Claude client completes Connect → OAuth → tool call. Riskiest unknown first;
   host-agnostic payoff.
2. **Scaffold the module:** `/deploy-cloud-mcp` skill + Pulumi program (Fargate
   compute as a swappable component), Shareable-tier first.
3. **Server build:** fork/adapt obsidian-web-mcp scope; add git single-writer
   ownership, computed backlinks, `classification:`-aware scope filtering.
4. **Autonomous runner:** wire `/vault-dream` as a Routine (non-PHI default);
   Bedrock-backed scheduled task as the PHI variant.
5. **PHI mode last:** org BAA acceptance gate + Control Tower conformance pack +
   Bedrock routing, as a config superset of the confidential tier.

## Caveats

- **"HIPAA-eligible" ≠ compliant.** Technical safeguards are automatable; the
  administrative program (risk assessment, policies, incident response, client
  BAAs) is irreducible human work.
- **Consumer opt-out is not airtight** (June 2026 safety-flag carve-out) — one more
  reason consumer tiers are capped at the Shareable plane.
- **In-place editing of complex Office documents is out of scope** — agents produce
  new artifacts reliably; surgical format-preserving edits are not promised.
- **AgentCore is young** (GA late 2025; EFS mounts May 2026; session storage in
  preview; infrastructure-as-code coverage trails). Re-evaluate at migration time.
- Vendor terms, prices, and daily-limit numbers cited here move fast — re-verify
  before implementation hardens any of them.
- Speculative numbers (monthly estimates, duty-cycle crossover) are directional,
  not quotes.

## Sources (retrieved 2026-07-21)

- [obsidian-web-mcp](https://github.com/jimprosser/obsidian-web-mcp) · [Obsidian Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api)
- [AgentCore pricing](https://aws.amazon.com/bedrock/agentcore/pricing/) · [Runtime MCP hosting](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html) · [EFS/S3 mounts (2026-05)](https://aws.amazon.com/about-aws/whats-new/2026/05/amazon-bedrock-agentcore-runtime/) · [inbound/outbound auth](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-oauth.html) · [Identity overview](https://aws.amazon.com/blogs/machine-learning/introducing-amazon-bedrock-agentcore-identity-securing-agentic-ai-at-scale/)
- [Pulumi AgentcoreAgentRuntime](https://www.pulumi.com/registry/packages/aws/api-docs/bedrock/agentcoreagentruntime/) · [Pulumi AgentCore blog](https://www.pulumi.com/blog/from-works-on-my-machine-to-production-ready-ai-agents-with-amazon-bedrock-agentcore/)
- [AWS org-wide BAA](https://aws.amazon.com/blogs/security/accept-a-baa-with-aws-for-all-accounts-in-your-organization/) · [HIPAA conformance pack](https://docs.aws.amazon.com/config/latest/developerguide/operational-best-practices-for-hipaa_security.html) · [Bedrock/AgentCore HIPAA eligibility](https://www.accountablehq.com/post/is-amazon-bedrock-hipaa-eligible-what-to-know-about-the-aws-baa-and-using-phi)
- [Anthropic BAA coverage](https://privacy.claude.com/en/articles/8114513-business-associate-agreements-baa-for-commercial-customers) · [HIPAA-ready Enterprise](https://support.claude.com/en/articles/13296973-hipaa-ready-enterprise-plans) · [consumer terms update (2025-08)](https://www.anthropic.com/news/updates-to-our-consumer-terms) · [API retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention) · [safety-flag carve-out (2026-06)](https://techcoffeehouse.com/2026/06/09/claude-training-data-opt-out-carve-out/)
- [Claude Code Routines](https://code.claude.com/docs/en/routines) · [Routines announcement (2026-04)](https://claude.com/blog/introducing-routines-in-claude-code)
- [OpenAI enterprise privacy](https://openai.com/enterprise-privacy/) · [remote MCP auth best practices](https://www.kapa.ai/blog/remote-mcp-servers-hosting-authentication-best-practices)
