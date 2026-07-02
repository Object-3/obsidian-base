<!--
Candidate global-instruction addition for fast Obsidian MCP orientation.
This file is the OPTIMIZATION TARGET of the obsidian-mcp-quick-orient ce-optimize run
(scope.mutable) — its content is meant to be appended to a user's existing global
Obsidian MCP instructions (e.g. ~/.claude/CLAUDE.md), not replace them.
-->

### Fast-orient in obsidian-base-derived vaults (MCP)

Trigger only when BOTH hold: the Obsidian MCP connector is available, AND the
connected vault is actually obsidian-base-derived — never assume the second part.

**No vault-specific fact needed → no MCP call.** The recap below (paths, tools,
conventions) is invariant across every obsidian-base fork — if the question is
answerable straight from it (e.g. "which folder do compounded learnings go in?"),
just answer from the recap. Don't fetch anything and don't re-verify vault identity
first. The gate below exists only for questions that need a fact specific to *this*
vault instance — its name, its `primary_tag`, whether its Sensitive plane is
cloud-backed, or a custom convention layered on top of the base.

**Only when a vault-specific fact is actually needed, check cheaply, once:** fetch
`.agents/vault-profile.md` by its exact path (one `obsidian_get_file_contents` call —
dot-folders don't show up in `obsidian_list_files_in_vault`'s listing, but ARE
fetchable directly by path, so don't list first). If it resolves with
`vault_name`/`primary_tag` frontmatter, the vault is obsidian-base-derived — read the
needed fact off it, and everything below already applies too. If the fetch fails,
this isn't one of these vaults — fall back to normal exploration.

That one fetch is usually the ONLY MCP call orientation ever needs — the rest of the
structure is identical across every obsidian-base fork, so it doesn't need
rediscovering:
- `index.md` = catalog of every note (read only if you need to know what exists);
  `log.md` = append-only changelog
- `docs/knowledge/` = compounded, reusable learnings (written by `kw-compound` /
  `/kw:compound`)
- `docs/solutions/` = engineering-plane learnings (code repos, not this vault)
- `plans/` = in-progress work (`kw-plan` / `kw-work`)
- `_sensitive/` = gitignored confidential plane, present in every fork; if
  `vault-profile.md` has no "Sensitive plane backing store" block, it's at the
  default state — unbacked, local-machine-only
- `.agents/` = agent engine home (skills, scripts) — never part of the note graph
- Frontmatter on every note: `title/type/status/tags/created/updated`; `tags`
  always includes the vault's `primary_tag` from `vault-profile.md`
- New skills are added via `.agents/skill-sources.local.json` +
  `.agents/scripts/sync-skills.sh` — a local mechanism, not something to fetch

Call the known tool/path directly instead of listing-then-exploring. This is a
read-only shortcut — writing still only happens when explicitly asked, through the
vault's own MCP write path.
