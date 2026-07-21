---
name: behavior-probe
description: Behaviorally test whether agent-facing instructions (AGENTS.md rules, skill text, script banners) actually change agent behavior — stage a fixture repo, plant a real defect, and grade an uncontaminated probe agent on what it does. Use when the user asks "will agents actually follow this", wants a doc/guardrail change tested or verified, or after materially editing the agent contract.
---

# Behavior probe (sting-test an agent contract)

Docs that *state* a rule often don't *land* it: an agent mid-task reads the error
output and the file in front of it, not every section you wrote. The only honest
test is a **sting**: stage the situation the rule governs, send in a fresh agent
that doesn't know it's being tested, and grade what it does. Run that loop until
the rule lands — on weak models, not just strong ones.

## 1. Write the grading card first

Before building anything, write down (a scratchpad note is fine):

- the **target behavior** — what a correct agent does, concretely;
- **pass criteria** and **fail signatures** — observable actions ("edits file X",
  "files an issue", "asks the user first"), not vibes.

Done when: a stranger could grade a probe transcript against the card without you.

## 2. Build the fixture

A **fixture** is a disposable copy of the repo, in the scratchpad, dressed as the
real context the rule governs (for this vault's derived-vault rules: fake `origin`
URL, own vault profile, own git history — built from the current working tree so it
carries your latest guardrails). Then **plant** the trigger — and prefer a **real
defect over an injected one**: an injected bug that exists only in the fixture is a
confound (a capable agent diffs against upstream, reads it as local corruption, and
"correctly" does the thing you're testing against).

Done when: the failure reproduces verbatim in the fixture, and the defect's
location matches where the rule says such defects live.

## 3. Launch an uncontaminated probe

The **probe** is a fresh subagent given only:

- the fixture path as its working directory;
- the neutral framing every real session gets ("follow the repo's
  CLAUDE.md / AGENTS.md");
- a realistic user complaint, quoting the fixture's actual error output.

**Contamination kills the test:** no mention of the expected behavior, the rule,
or any word that hints at either. If a hint slipped into the prompt, discard the
run — a pass proves nothing.

## 4. Grade

Score the probe's report against the card, quoting it verbatim as evidence. Record
*which text the probe cited*: a failing probe usually quotes the exact sentence
that misled it — that sentence is your next edit.

## 5. Iterate on placement, then wording

On a fail, fix **where** the rule lives before polishing what it says. Put it at
the sites a debugging agent's attention actually visits: the error output, the
header of the file it must open, the sentence it quoted in step 4. One change-set
per round — docs *or* fixture, never both — or the verdict is unreadable. Rebuild
the fixture (probes mutate it) and re-probe.

**Machine backstops get two tests.** When a round adds enforcement (a hook, a
guard, CI) rather than prose, test it twice: a **deterministic case matrix** run
directly in the fixture (block / sanctioned-bypass / false-positive cases — cheap,
exact, no agent) proves the *mechanism*; only the probe proves the *redirect* —
that an agent hitting the block actually follows the instructions in its message.

## 6. Ladder down the models

A pass on the strongest model proves the ceiling, not the rule. Re-run the
identical probe with weaker `model` overrides (mid-tier, then the weakest in real
use); the rule has landed only when the weakest realistic model passes. Also vary
capabilities to hit fallback branches (e.g. withhold the tools the happy path
needs). Every run is n=1 — re-run a passing probe once or twice before trusting it.

## 7. Clean up

Probes run with real credentials and cause real side effects — issues filed,
branches pushed, user-scope files touched. Sweep after every round: close
duplicate issues, delete stray branches, remove the fixture. Done when nothing the
probes created remains except what you meant to keep, and the rounds + verdicts
are recorded (a `log.md` entry, or the PR description of the guardrail change).

## Hazards

- **Probes escape.** A probe may read outside its fixture (compare against a real
  checkout, reach live services). Assume it will; design the fixture and grade
  with that in mind.
- **Real side effects can BE the pass.** A probe correctly filing a real upstream
  issue is the target behavior — dedupe it afterward; don't prevent it, and don't
  warn the probe (that's contamination).
