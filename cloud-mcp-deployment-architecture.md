---
title:   "Cloud Vault Deployment — Architecture Decision Record"
type:    decision-record
status:  active
tags:    [obsidian-base, cloud, mcp, security, hipaa, architecture, cdk, aws]
created: 2026-07-21
updated: 2026-07-28
confidence: high
sources: 31
related:
  - "[[onedrive-sensitive-plane-setup-gotchas]]"
  - "[[connect-github-naming-parity-and-push-resilience]]"
---

# Cloud Vault Deployment — Architecture Decision Record

> [!note] Amended 2026-07-22 after a full `/grilling` session (pre-`ce-plan`).
> This revision supersedes 2026-07-21 throughout: IaC moved Pulumi → CDK, the server
> moved fork → fresh TypeScript build, tenancy moved per-vault → per-trust-domain,
> the sync topology and sensitive-plane transport gaps are now specified, the
> autonomous runner moved Routines-first → in-VPC-first with dual auth rails, and
> PHI mode moved from build item to paper design.

> [!note] Amended 2026-07-28 after `ce-plan` + annotation review of the resulting
> implementation plan. **Decision 6 is restated** (the single writer targets a
> *configured write target*, defaulting to a weekly human-reviewed knowledge branch —
> no longer `main` directly); **decisions 15–23 are new**, folding back what planning
> resolved beyond this record (write credential, durability/conflict semantics,
> branch conventions, tool-level guards, auth-facade details, endpoint identity +
> networking cost correction, runner containment, domain config, image home + the
> single-task invariant); an **Undeploy** section is added. The implementation plan
> (ce-plan, machine-local) holds unit-level detail; this record stays the
> decision-grade source.

## TL;DR

Add an **opt-in cloud deployment module** to obsidian-base: a vault derived from the
template *can* be deployed to Amazon Web Services (AWS) and exposed as an
authenticated, read/write **Model Context Protocol (MCP)** endpoint, so its owners
reach the knowledge base (KB) from Claude/ChatGPT anywhere and autonomous maintenance
(`/vault-dream`) runs unattended in the cloud. Local-only vaults change **nothing**.
The design: a **fresh-built, markdown-only, multi-vault MCP server** (TypeScript,
official MCP software development kit (SDK)) living in a sibling repo
(**`agentic-knowledge-base-mcp`**) and shipped as a versioned container image;
**one deployment per trust domain** (not per vault), provisioned by an idempotent
**`/deploy-cloud-mcp`** skill driving **AWS Cloud Development Kit (CDK)** — Fargate
first, Bedrock AgentCore as a later module swap; **cloud-primary write topology**
(the server is the single writer to the vault's **configured write target** — by
default a weekly `knowledge/` branch merged into `main` through one human-reviewed
PR per week, decision 6 as restated; local Obsidian demotes to a pull-only
replica); the **`_sensitive/` plane stays OneDrive/Drive-authoritative**, reached by
a one-way `rclone` mirror in and provider-API write-through out; an **in-VPC
scheduled runner ships in v1** with dual auth rails (subscription OAuth token now,
API key as the terms-correct rail). **v1 scope: the confidential tier, deployed for
one vault (`obsidian-puma-peak`) in one trust domain; PHI (protected health
information) mode is a documented config-superset, not a build item.** **Firm IP
control remains the governing principle**: the billing/terms seam is *which
contractual rail the tokens ride, per data plane*.

## Key decisions

1. **Fresh TypeScript server, markdown-only, multi-vault, composed with native
   MCPs.** Vault operations only: read, write, search, frontmatter/tag queries,
   computed backlinks — with a **graph-native tool surface as a first-class
   requirement** (link/backlink traversal, frontmatter and tag predicates,
   note-neighborhood queries; no full-vault scans per query; a dedicated `/research`
   pass on knowledge-graph leverage feeds the final tool spec during planning).
   Write tools return diffs and favor narrow, verifiable operations — the local
   Obsidian MCP's `patch_content` silently clobbering heading subtrees is the
   documented anti-pattern. Built on the official `@modelcontextprotocol/sdk`
   (TypeScript-first, most mature); **FastMCP (TypeScript) is evaluated in the auth
   spike** — its built-in OAuth 2.1 proxy (PKCE + dynamic client registration (DCR))
   may replace the custom MCP-OAuth shim. Reference designs are **concepts-only**:
   [obsidian-web-mcp](https://github.com/jimprosser/obsidian-web-mcp) is
   **unlicensed (code uncopyable)** and its tunnel-to-local-machine model is
   inverted from ours; the 2026 landscape (mcpvault, Vault-as-MCP,
   obsidian-sync-mcp, etc.) contains no server with our load-bearing requirements
   (scope-enforced sensitivity, git single-writer, multi-vault, mirror
   orchestration). Raw work documents (Word/Excel/PDF) stay in OneDrive/Google
   Drive, read by the **native M365/Drive MCPs** — our server never parses Office
   documents.
2. **Deployment unit = trust domain; the server is multi-vault by config.** A stack
   is deployed **per trust domain** — the boundary within which one admin may hold
   deploy keys, Graph credentials, and user management for everything inside. One
   stack hosts N vaults (the server takes a vault list; authorization is per-vault
   scopes), so vault count shows up as scopes and repos, never as servers — and
   future **vault inheritance** (one vault reading another's knowledge) is a feature
   of one process seeing both trees, not a federation problem. Distinct trust
   domains never share a stack. **v1: one domain (the firm's AWS account), one vault
   (`obsidian-puma-peak`); `obsidian-strategy` stays local for now** — adding a
   second domain later is a rerun of the same skill with different credentials.
3. **Code home: sibling repo, thin skill in the template.** The server **and** the
   CDK program live in **`agentic-knowledge-base-mcp`**; CI publishes a versioned
   container image. The vault template carries only the **`/deploy-cloud-mcp`**
   skill plus a **base-blessed version pin** (an engine file propagated by
   `update-base`): the skill clones the pinned tag to a cache outside the vault,
   runs the deploy, and records a **no-secrets coordinates block** (endpoint,
   region, tier, deployed version, stack name) in `.agents/vault-profile.md` — real
   secrets live only in AWS Secrets Manager. Every vault has the capability; only
   opted-in vaults have a deployment; upgrades = pin bump + skill rerun.
4. **Idempotent by construction: the skill owns judgment, the IaC owns state.**
   Every cloud mutation goes through the CDK deploy (convergent; rerun = no-op,
   rerun after pin bump = rolling update). The skill's local side effects
   (vault-profile block, Obsidian Git demotion) are check-then-set. No imperative
   AWS calls in the skill, ever.
5. **IaC: AWS CDK (TypeScript) — Pulumi decision reversed.** CDK's state *is*
   CloudFormation (server-side in the account: no state bucket, no KMS key, no
   passphrase to lose — nothing for a vault owner to custody); `cdk bootstrap` is
   the one-time idempotent account prep. The 2026-07-21 revision preferred Pulumi
   partly on AgentCore IaC coverage — stale: **AgentCore went GA 2026-04 with native
   CloudFormation support and CDK constructs**. Cloud portability is **a property of
   the container contract, not the IaC tool** (an `aws.*` Pulumi program is exactly
   as AWS-locked as CDK); the IaC layer is deliberately cloud-native and disposable.
   Container contract (unchanged, now the explicit portability carrier): stateless
   image, Streamable HTTP MCP with port/path from environment, all state external
   (Elastic File System (EFS) / git / Secrets Manager), inbound auth = JSON Web
   Token (JWT) validation against a **configurable OpenID Connect (OIDC) issuer**.
6. **Write topology: cloud-primary, one writer per plane — RESTATED 2026-07-28
   (supersedes "single writer to `main`").** The cloud server is the **single
   writer to the vault's configured write target**. **Default: a rolling weekly
   knowledge branch** (`knowledge/<YYYY>-W<ww>`) that accrues all interactive MCP
   writes and reaches `main` only through **one human-reviewed PR per week** — the
   team's standing review surface over agent-mediated knowledge; `main` remains
   selectable per vault for continuous writes with no weekly gate. Interactive
   edits are audit-logged either way; a cheap fetch→rebase→push absorbs upstream
   edits *on the target branch*; autonomous jobs are **always branch + PR into the
   write target** — unchanged dream rails. Consequences stated plainly: in weekly
   mode, GitHub-web-UI edits on `main` are **not** absorbed (the weekly merge is
   the only reconciliation channel; a divergence alarm watches it), and the demoted
   local replica — which pulls `main` — **lags by up to a week** (the MCP surface
   is unaffected; the operator accepts this at deploy time, shortens the cadence,
   or selects `main`). If a week's PR is still open at the boundary, the next week
   **chains from it**, never from `main`, so no write is stranded; chain depth is
   alarmed. The deploy skill **demotes local Obsidian to a pull-only replica**
   (Obsidian Git auto-commit/push off; graph/search/reading keep working);
   `/doctor` checks the demotion on deployed vaults (it is convention-enforced,
   not physics). Web exploration (Quartz read-only publish) and a self-hosted web
   editor (SilverBullet-class) are deferred, separable follow-ups; GitHub's web
   editor is the interim manual path.
7. **Sensitive plane transport (new section — the prior revision had no way for
   `_sensitive/` to reach the cloud at all, since it is gitignored by design).**
   **OneDrive/Drive stays authoritative for the sensitive plane, everywhere.**
   - *Read path:* a one-way **`rclone` mirror** (provider → EFS) on ~60-second
     delta polls, using **app-only client credentials at narrowest scope** (Graph
     client-credentials + `Sites.Selected` + explicit `drive_id`; a Google service
     account for Drive vaults). Scoped to `*.md` and excluding Office lock/temp
     artifacts (`~$*`, `.tmp*`, `.DS_Store`) — SharePoint rewrites Office file
     internals after upload (checksum churn), and live-edited workbooks shed
     phantom-change artifacts; a markdown-scoped mirror is immune by construction.
     The server reads sensitive notes as plain on-disk files, exactly like the
     laptop does via its native sync client (which keeps running unchanged).
     True mounts are impossible anyway: no OneDrive client exists for Linux and
     Fargate cannot FUSE-mount.
   - *Write path:* **provider-API write-through** — the server uploads the markdown
     to the backing folder (Graph PUT) and updates its EFS mirror copy in one
     serialized operation. The write credential has write access **only to the
     vault's own backing folder**, never any shared/Sources folder. Provider
     version history is the tamper/conflict backstop (last-writer-wins is
     acceptable at markdown-note granularity).
   - *Structure:* mirrors are **N configured remotes** (direction, file-type scope,
     excludes, credential each) even though v1 configures exactly one — a future
     read-only Sources-plane remote (cloud `/ppc-sweep`-class jobs) is a config
     entry, not new architecture. The single server process owns both the mirror
     schedule and writes, so sync passes and writes are serialized — no two-writer
     race exists on the box.
   - *Named prerequisite:* the **Azure app registration** (client-credentials,
     `Sites.Selected`) is net-new — headless Graph access was never configured for
     the existing vaults; the deploy skill owns that walkthrough.
8. **Auth: OAuth 2.1 + PKCE against Cognito, per deployment.** Cognito is free at
   this scale (Lite/Essentials: 10,000 monthly active users free; federated OIDC/
   SAML users free to 50) and works identically fronting Fargate or as AgentCore's
   JWT authorizer. **v1: Cognito-native users + group→scope grants** (`{vault}:read`,
   `{vault}:sensitive`); adding **Entra ID federation later** (work accounts,
   automatic offboarding) is an IdP addition to the existing pool, not a rework.
   The DCR gap (Cognito lacks dynamic client registration; MCP clients expect it)
   is closed by the thin MCP-OAuth shim or FastMCP's proxy (spike decides). **Stated
   plainly: the consumer-tier cap is administratively enforced** — OAuth proves who
   the human is, not which Claude plan their client runs; the `sensitive` scope is
   granted only to people known to be on commercial-terms seats.
9. **Hosting: Fargate first; AgentCore is a later module swap, not a rewrite**
   (unchanged, strengthened: the container contract above is what keeps the swap
   clean, and AgentCore now has GA + IaC parity — re-evaluate at migration time on
   maturity of session storage and EFS mounts).
10. **Autonomous runner: in-VPC scheduled task ships in v1** (EventBridge Scheduler
    → ECS RunTask, a job variant of the same image plus the Claude Code CLI). Being
    in-VPC unlocks the **full dream**: sensitive-plane awareness *and*
    **audit-log-as-session-source** (in cloud-primary mode the MCP server's
    structured audit log replaces local session transcripts as `dream-scan`'s
    input — a named design item). Default cadence **weekly** — cadence is the cost
    dial. **Dual auth rails, switchable by env var:**
    - `CLAUDE_CODE_OAUTH_TOKEN` from **`claude setup-token`** (official, ~1-year,
      subscription-billed — the chosen starting rail for cost). **Recorded
      deviation:** on a *consumer* Pro/Max seat this routes content under consumer
      terms, which decision 12 forbids for confidential content; mitigation dial:
      restrict dreaming to the tracked plane while on a consumer token. A
      commercial-seat (Team/Enterprise) token cures the deviation at zero cost.
    - `ANTHROPIC_API_KEY` — the **terms-correct, preferred rail** for confidential
      content (no training, Data Processing Agreement (DPA), short retention);
      ≈$5–20/mo at weekly cadence.
    **Anthropic Routines demote to a documented alternative** for vaults with no
    sensitive plane: they are subscription-free but run on Anthropic's managed
    cloud — **no VPC reach** (EFS/mirrors invisible), pull-request/release triggers
    only, no self-approve, daily caps. Cloud sweep/ingest jobs are **explicitly
    v2**, riding the same seams (job pattern + mirror remotes).
11. **Observability and disaster recovery (new).** Every task logs to CloudWatch
    with **explicit retention** (~90 days); volumes sit far inside the always-free
    tier (5 GB/month ingestion — vintage-independent), with CloudTrail's free
    management trail on. The **audit log is structured (JSON lines)** because it
    doubles as dream input. **EFS is a disposable cache**: the tracked plane's
    durability is git/GitHub, the sensitive plane's is the provider — DR is
    re-clone + re-mirror, never restore.
12. **Firm IP control — the data-control ladder (governing principle, retained).**
    Consumer Claude trains on chats unless opted out (and the 2026-06 safety-flag
    carve-out weakens the opt-out); commercial tiers (Team/Enterprise, both APIs)
    do not train, carry a DPA, and offer short/zero retention; Bedrock is maximal
    control (bytes never leave the firm's AWS account). The ladder: **Shareable
    (de-identified) → any client. Confidential (NDA/financial/firm IP) →
    commercial-terms seats or API only. PHI → Business Associate Agreement
    (BAA)-covered rails only.** The `_sensitive/` plane is retained as the enforced
    routing boundary (GitHub is still not a business associate; minimum-necessary
    needs a boundary independent of who holds a BAA; it is economically
    load-bearing).
13. **Billing seam (rewritten):** the seam is **which contractual rail the tokens
    ride, chosen per data plane** — not interactive-vs-automated (both can ride
    subscriptions) and not non-PHI-vs-PHI (confidential already forces commercial
    rails). Interactive use rides users' existing seats; automation rides the API
    or a commercial setup-token; PHI inference (future) rides Bedrock under the
    AWS BAA.
14. **HIPAA posture: paper design only.** The one-click org-wide AWS BAA, the
    Config HIPAA conformance pack, and Bedrock routing remain the documented
    **config-superset** of the confidential tier — **explicitly not in the v1 build
    list**; nothing in v1 closes the door (service choices stay HIPAA-eligible),
    and the tier flag exists in config from day one.

*Decisions 15–23 added 2026-07-28: what planning resolved beyond this record
(plan decisions D5–D21, consolidated — the mapping is noted per decision).*

15. **GitHub write credential: a GitHub App per trust domain** *(plan D5)*. Bot
    identity (name parity `akb-mcp-<domain>`), installed on the vault repo(s) with
    `contents:write` + `pull_requests:write` and **nothing else** — no `workflows`,
    no administration, no org-level permissions; the permission floor doubles as
    the prompt-injection blast-radius bound (decision 21). Installation tokens
    (1 h) are minted at runtime from the App key in Secrets Manager and live in
    process memory only. Rotation = rotate the secret + force a new deployment
    (task-start-frozen secrets make redeploy the mechanism). Branch protection on
    the write target: none, or bypass-allowance for the App — a stated deviation
    the deploy skill checks and records. Fallback: fine-grained personal access
    token with its expiry recorded for `/doctor`.
16. **Write durability and conflict semantics** *(plan D8–D10; resolves this
    record's "disposable EFS" contradiction)*. An interactive write is acknowledged
    **only after push succeeds**; boot reconciliation commits-or-quarantines dirty
    state (`recovery/<ts>`), pushes unpushed commits, and rebases — first boot
    gates endpoint health on clone + index build only, **never on the first mirror
    pass** (a Graph outage must not take the git plane down). Disaster-recovery
    re-clone is gated on the write target being push-clean, with an
    unpushed-commit-age alarm as the belt. Rebase content conflicts park on
    `conflict/<ts>` with the diff surfaced in the tool result — one policy for all
    writers. Read freshness: periodic fetch/fast-forward on the ~60 s mirror
    cadence. Sensitive-plane writes are PUT-first with `If-Match` ETags (412s
    surface, never silent clobbers) and bounded `Retry-After` budgets that release
    the serialization lock across sleeps.
17. **Branch naming is a stated convention, not ad-hoc** *(plan D21 + D20
    mechanics)*. Every machine-created branch carries a **typed prefix + UTC
    timestamp** (ISO-8601 basic form, no colons): `knowledge/<YYYY>-W<ww>` (weekly
    write target; human-readable date range rides the PR title),
    `dream/<ts>-<slug>` (PR title repeats timestamp + description),
    `conflict/<ts>`, `recovery/<ts>`. Pre-flight collision checks and age-based
    cleanup key off these prefixes, so the convention is load-bearing; generators
    are tested against the patterns.
18. **Plane routing and guards move to tool level** *(plan D7)*. Git hooks do not
    run for the cloud writer, so the server enforces: `_sensitive/**` reachable
    **only** via the provider write-through (never the git plane); tracked-plane
    writes reject `classification: confidential*` frontmatter; the ~25 MB size
    guard is mirrored; and the confidential-**name scan** (fed by the vault's
    gitignored names file, mirrored in from the sensitive plane) runs on both the
    runner's pre-commit gate and interactive tracked-plane writes. **The gate
    fails closed**: sensitive plane configured but names file absent/empty ⇒
    autonomous runs abort with an alarm and interactive tracked writes are
    rejected with a named error; a vault with no sensitive plane is legitimately a
    no-op. Plane routing + classification are the structural controls;
    name-matching is the incomplete-by-design backstop, its staleness surfaced by
    `/doctor`.
19. **Auth facade details** *(plan D2, D3, D6; extends decision 8)*. The server
    serves RFC 9728 protected-resource metadata + the 401 handshake; a thin
    authorization-server facade in the service task (FastMCP vs hand-rolled —
    spike decides) serves **corrected AS metadata** (Cognito's discovery omits
    `code_challenge_methods_supported`), supports **CIMD first** with DCR
    fallback, and carries the confused-deputy contract (per-client consent,
    exact-match redirect URIs, issuer-URL consistency). **Scopes are
    `{vault}:read`/`write`/`sensitive` — write is not implied by read**; v1 maps
    `cognito:groups` server-side. Tokens are validated on issuer, `token_use`,
    client allowlist, expiry, **and audience — scope alone is not audience
    proof**. Registrations must survive task replacement (a rolling update never
    forces connector re-auth). Account hardening: no self-service sign-up,
    mandatory MFA, strengthened password policy; offboarding revokes live refresh
    tokens, not just future logins. **Protocol surface v1: tools only** —
    resources/prompts/completions are not served (completions can leak sensitive
    note titles); tool lists are filtered at `tools/list` *and* enforced at
    `tools/call` (the call check is the boundary); search filters inside the
    query, never post-filter.
20. **Endpoint identity, networking, and the cost correction** *(plan D4, D15;
    amends the cost section below)*. Each trust domain supplies a **custom domain
    + ACM certificate**; the **hosted zone is a one-time, long-lived bootstrap
    resource outside the stacks** (stacks reference it and own only records +
    certs — a zone inside a disposable stack would reassign nameservers on every
    recreate and drag the operator back to the parent DNS provider, and the zone
    must survive undeploy). Certificate-transparency logs make any chosen hostname
    publicly enumerable — accepted; auth is the boundary. ALB is HTTPS-only, TLS
    1.2+, **no plaintext listener and no 3xx on the MCP URL**; explicit 300 s idle
    timeout that decision 16's retry budgets stay under. One hostname serves the
    whole deployment (vault selection by validated tool argument, never by path or
    subdomain). **Networking cost correction:** interface VPC endpoints (~$29/mo/AZ)
    cannot reach GitHub/Graph/Anthropic — endpoints never eliminate NAT here; v1
    uses a **public-subnet task with a public IP (~$3.60/mo), inbound locked to
    the ALB security group** — no NAT gateway. WAF is consciously deferred
    (Anthropic's egress range is published, ChatGPT's is not; strict allowlisting
    is impractical); the compensating **rate limiting is a built control**:
    per-IP on unauthenticated surfaces, per-subject on `tools/call`, a cap on
    total DCR registrations.
21. **Runner containment and plane access** *(plan D11, D16, D17, D19)*. The dream
    job works in its **own ephemeral clone** (never the service tree — the weekly
    two-writer race is eliminated by construction); sensitive-plane **reads** come
    from a separate **read-only mirror access point, commercial rail only**; **v1
    dreams make no sensitive-plane writes** — proposals ride the dream PR as
    de-identified, title-level stubs with opaque pointers the human resolves
    locally (pre-applied sensitive writes would escape the merge gate, which fires
    after provider writes land). Injection is a first-class threat: the runner
    reads attacker-influenceable content while holding write credentials —
    controls are the decision-15 permission floor, a **PR path allowlist** (note
    paths only; engine/CI paths rejected before push), digest-as-quoted-data, and
    the **human merge gate named as an injection control**. The audit log is
    **metadata-only** (CloudWatch is IAM-governed, not vault-scope-governed —
    content there would bypass the scope model; the invariant covers *all* task
    output, with leak tests). The dream digest is reconstructed runner-side: tool
    sequences + paths from the log, tracked-plane diffs re-derived from git in the
    job's clone; search-query text is deliberately not reconstructable — an
    accepted degradation, recorded so nobody "fixes" it by widening the log.
22. **Multi-vault domain config lives in a versioned SSM parameter** *(plan D18,
    D20 recording)*, owned by the deploy skill check-then-set and resolved at
    **synth time** (CloudFormation dynamic references cannot shape topology).
    Without a domain-level source of truth, "rerun = no-op" (decision 4) breaks
    the day the second vault lands. Each vault's entry records repo, tier, mirror
    remotes, and write-target choice; partial undeploy is an edit to this config.
23. **Image home, runtime, and the single-task invariant** *(plan D13, D14)*.
    Versioned container images publish to GitHub Container Registry with immutable
    tags (decoupled from any single AWS account; ECR mirroring is the documented
    alternative). Node 22, pnpm, zod v4, vitest. **"At most one service task" is
    an explicit, load-bearing invariant** (the in-process write mutex is only a
    global lock because of it) — asserted by an IaC-level test and an EFS
    lockfile, and **signposted at the point of change**: the test's failure
    message, the lockfile error, and the runbook all name what must change before
    a second task (external writer lease, per-vault locks, always-on loops
    extracted to schedulable one-shots) — the same homework the AgentCore swap
    (decision 9) needs, so the two futures share it.

## Details

### Content model (unchanged)

Humans primarily author work documents in their cloud drives; the vault is the
synthesis + navigation layer (distilled, cross-linked, frontmatter-tagged notes plus
agent working memory). Notes point to source documents; following a pointer means
the *client* agent switches to the native provider MCP. Obsidian remains the local
human cockpit (read-only on deployed vaults); it is not required anywhere in the
cloud path.

### Deployment shape

One stack per trust domain: an always-on **interactive MCP service** (the single
tree owner) and a **scheduled job task** (dream now; sweep/ingest in v2) sharing the
image, EFS, Secrets Manager, and Cognito. Delivered per the existing opt-in
cloud-module pattern (`/setup-sensitive-plane`, `/connect-github`): the skill owns
judgment (trust domain, region, tier, credential rail, demotion consent), the CDK
program owns resources, `update-base` propagates capability.

### Client discoverability

MCP endpoints are wired **once per client** (claude.ai connector, `claude mcp add`,
ChatGPT connector) — the cloud endpoint replaces `localhost` with URL + OAuth in the
existing per-vault-connector pattern. Runtime steering lives **server-side** (tool
names/descriptions + the server's `initialize` instructions), which travels to every
provider automatically; the module ships an updated fast-orient block for user-level
docs. One server exposing N vaults beats N near-duplicate servers for model tool
selection (no ambiguous same-named tools; `list_vaults` + a `vault` argument).

### Undeploy (added 2026-07-28 — plan D12)

Undeploy is a **first-class, ordered flow**, not an afterthought: (1) drain — final
push, verify origin matches the working tree, no in-flight provider write; **in
weekly-target mode the open knowledge PR must be merged or its abandonment
explicitly acknowledged first** (else knowledge strands on an orphan branch while
the re-promoted vault resumes writing `main`); (2) **export the CloudWatch audit
logs** (they are the audit trail), then `cdk destroy`; (3) external revocations the
IaC cannot do — Azure app/site grant, GitHub App uninstall, per-client connector
removal; (4) re-promote local Obsidian (inverse config patch, per machine); (5)
remove the vault-profile managed block (its presence is what keys `/doctor`'s cloud
checks). Partial undeploy of one vault from a multi-vault domain is a config +
scope + connector removal, never a stack teardown. End state of a full undeploy:
**no stack, no idle resources, recurring cost $0** — the survivors are the exported
audit archive, Secrets Manager entries inside their no-charge deletion window, and
the $0 SSM domain-config parameter (removed when the last vault leaves the domain).
The long-lived hosted zone (decision 20) survives by design, so a redeploy never
re-touches the parent DNS provider.

### Cost (verified rates, July 2026; estimates are speculation)

- Fargate floor ≈ **$38/mo per trust domain** (0.5 vCPU/1 GB ≈ $18 + Application
  Load Balancer ≈ $20) — flat as vaults are added to the domain. AgentCore bursty
  ≈ $5–15/mo at migration time (crossover ≈ 50% duty cycle).
- Shared fixed *(corrected 2026-07-28 — decision 20)*: ~~NAT gateway ~$33/mo /
  ~$7 VPC endpoints~~ — **neither**: interface endpoints cannot reach
  GitHub/Graph/Anthropic, so v1 runs a public-subnet task with a public IP
  (~$3.60/mo), inbound locked to the ALB security group. KMS/Secrets/CloudTrail
  ~$3–10/mo, EFS <$1 (markdown), CloudWatch ≈ $0 (always-free tier, retention
  capped), Cognito $0 (≤10k MAU), hosted zone $0.50/mo.
- **Interactive tokens ≈ $0** (users' subscriptions). **Automation:** ≈ $0 on a
  subscription OAuth token; ≈ $5–20/mo weekly-cadence on the API rail. Machine-to-
  machine Cognito tokens $0.00225 each (pennies).
- Estimated all-in: **$40–100/mo for the v1 domain**. The dominant real cost of a
  future PHI mode remains the administrative compliance program, not servers.

## Recommendations (build order for ce-plan)

> [!note] Executed 2026-07-22 → 2026-07-28: `ce-plan` turned this build order into a
> nine-unit implementation plan (machine-local ce-plan document; annotation-reviewed).
> The list below is retained as the original decision-time shape; the plan is the
> live execution source.

0. **Plan-phase research:** run `/research` on knowledge-graph tool surfaces (how
   the strongest vault-MCP servers expose link/graph/frontmatter queries) — feeds
   the server tool spec. *(Also subsumes recovering the earlier claude.ai research
   session on the same topic.)*
1. **Auth spike (~1 day):** hello-world MCP behind Cognito + OAuth; prove a real
   Claude client completes Connect → OAuth → tool call. **Doubles as the FastMCP-
   vs-hand-rolled-shim bake-off.** Riskiest unknown first; host-agnostic payoff.
2. **Scaffold `agentic-knowledge-base-mcp`:** CDK program (Fargate compute as a
   swappable construct) + CI image publishing; `/deploy-cloud-mcp` skill + version-
   pin plumbing in the template.
3. **Server build:** tool surface per the research; git single-writer ownership
   (rebase-absorb, branch/PR mode); `classification:`/scope filtering; multi-vault
   config; diff-returning writes.
4. **Sensitive-plane transport:** Azure app registration walkthrough; rclone mirror
   remote #1; Graph write-through; serialization with writes.
5. **Runner:** job task + EventBridge; dual auth rails; audit-log-as-session-source
   for `dream-scan`; weekly cadence default.
6. **Demotion + docs:** pull-only flip in the deploy skill; `/doctor` checks
   (demotion, deployed-vs-pinned version, mirror freshness, token expiry);
   fast-orient/AGENTS.md updates.

*(Dropped from the build list: PHI mode — paper design, decision 14.)*

## Caveats

- **"HIPAA-eligible" ≠ compliant** — the administrative program is irreducible
  human work; PHI mode stays paper until a PHI vault exists.
- **Consumer opt-out is not airtight** (2026-06 carve-out) — and v1's subscription-
  token runner is a **recorded deviation** from the ladder until a commercial seat
  or the API rail replaces it. The tier boundary is administratively enforced.
- **Pull-only local Obsidian is convention** (config, not physics) — `/doctor`
  checks it; a user can still type locally and strand uncommitted edits.
- **Sensitive-plane freshness lags ≤ ~1 minute** (mirror poll interval); the
  writing agent reads its own writes immediately (write-through), other readers on
  the next pass.
- **In-place editing of complex Office documents remains out of scope.**
- **AgentCore and FastMCP maturity** are spike/migration-time questions, not
  assumptions; the unlicensed reference repo is concepts-only.
- Vendor terms, prices, free-tier definitions, and token-limit numbers move fast —
  re-verify before implementation hardens any of them. Monthly estimates are
  directional, not quotes.

## Sources (retrieved 2026-07-21, amendments verified 2026-07-22)

- [obsidian-web-mcp](https://github.com/jimprosser/obsidian-web-mcp) *(no license — concepts only)* · [Obsidian Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) · 2026 landscape: [mcpvault](https://github.com/bitbonsai/mcpvault) · [Vault-as-MCP plugin](https://community.obsidian.md/plugins/vault-as-mcp) · [obsidian-sync-mcp](https://crossaitools.com/mcp/es617/obsidian-sync-mcp) · [roundup](https://contextbolt.com/blog/obsidian-mcp-claude/)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk) · [FastMCP (TS)](https://github.com/punkpeye/fastmcp) · [framework guide](https://mcp.guide/reference/mcp-frameworks-sdks-overview) · [remote MCP auth best practices](https://www.kapa.ai/blog/remote-mcp-servers-hosting-authentication-best-practices)
- [CDK AgentCore module](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_bedrockagentcore-readme.html) · [CFN AgentCore Runtime resource](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-bedrockagentcore-runtime.html) · [CDK hotswap for AgentCore](https://dev.to/aws-heroes/aws-cdk-hotswap-deployments-now-support-bedrock-agentcore-runtime-42c7) · [Pulumi DIY backends](https://www.pulumi.com/docs/iac/operations/stack-management/using-a-diy-backend/)
- [AgentCore pricing](https://aws.amazon.com/bedrock/agentcore/pricing/) · [Runtime MCP hosting](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html) · [EFS/S3 mounts (2026-05)](https://aws.amazon.com/about-aws/whats-new/2026/05/amazon-bedrock-agentcore-runtime/) · [inbound/outbound auth](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-oauth.html)
- [Cognito pricing](https://aws.amazon.com/cognito/pricing/) · [Entra External ID pricing](https://www.microsoft.com/en-us/security/pricing/microsoft-entra-external-id/) · [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) · [AWS free-tier changes 2025](https://dev.to/usxcloud/new-aws-free-tier-updates-after-july-15-2025-what-you-need-to-know-3m36)
- [Claude Code authentication (`setup-token`)](https://code.claude.com/docs/en/authentication) · [Claude Code Routines](https://code.claude.com/docs/en/routines) · [rclone OneDrive backend](https://rclone.org/onedrive/) *(app-only client-credentials + `drive_id`)*
- [AWS org-wide BAA](https://aws.amazon.com/blogs/security/accept-a-baa-with-aws-for-all-accounts-in-your-organization/) · [HIPAA conformance pack](https://docs.aws.amazon.com/config/latest/developerguide/operational-best-practices-for-hipaa_security.html) · [Bedrock/AgentCore HIPAA eligibility](https://www.accountablehq.com/post/is-amazon-bedrock-hipaa-eligible-what-to-know-about-the-aws-baa-and-using-phi)
- [Anthropic BAA coverage](https://privacy.claude.com/en/articles/8114513-business-associate-agreements-baa-for-commercial-customers) · [HIPAA-ready Enterprise](https://support.claude.com/en/articles/13296973-hipaa-ready-enterprise-plans) · [consumer terms update (2025-08)](https://www.anthropic.com/news/updates-to-our-consumer-terms) · [API retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention) · [safety-flag carve-out (2026-06)](https://techcoffeehouse.com/2026/06/09/claude-training-data-opt-out-carve-out/) · [OpenAI enterprise privacy](https://openai.com/enterprise-privacy/)
