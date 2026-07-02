## Obsidian knowledge base

I keep a personal, user-owned Obsidian vault as a knowledge base, exposed to agents
via the Obsidian MCP (`mcp-obsidian`) when the connector is enabled and Obsidian is
running.

**First, figure out where you are — this decides everything below:**
- If the working directory **is the vault repo** (its `AGENTS.md` / `vault-profile.md`
  is present), follow that repo's contract: work **natively on a branch**, not through
  the MCP. The MCP rules below don't apply — you're already in the right place.
- If you're working **anywhere else**, the vault is reachable only via the MCP, and the
  rules below apply.

**Proactively consult it — don't wait for me to ask.** Before answering anything that
my own notes could inform, do a quick search of the vault via the Obsidian MCP first:
- questions about **my past decisions, prior research, or project context**
- "what did I conclude / decide / find about X", "have I looked at X before"
- **my preferences, conventions, or standing context** for a piece of work
- anything where my own accumulated knowledge likely beats a generic answer

**Don't** reach for it on generic coding or factual questions that my notes wouldn't
inform — keep it scoped so it's a help, not overhead.

**Access rules:**
- **Consuming** knowledge (the above) → **read/search** the live vault via the MCP.
- **Working on the vault itself** (creating, editing, restructuring notes inside its
  repo) → use native file tools on a branch, not the MCP.
- **Don't write** to the vault through the MCP unless I explicitly ask.

**Fallback:** if the MCP isn't available (Obsidian closed, connector off), just answer
normally — mention once that the vault wasn't reachable, then don't keep retrying.
