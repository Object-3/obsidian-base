# `_local/` — local-only assets (never committed)

Everything in this folder (except this README and `.gitkeep`) is **gitignored** — it
stays on your machine and never reaches GitHub.

Put **large or sensitive originals** here: PDFs, big images, datasets, exports, anything
you don't want in version control. Obsidian can still embed/preview them and your local
agents (and the Obsidian MCP) can still read them straight off disk.

For each one, keep a small **reference note** in the vault (in git) that captures the
distilled knowledge and points to the file — that's how the knowledge base "knows about"
it without storing the bytes. See the "Large files & external sources" section in
`AGENTS.md`.

Need a file on multiple devices or shared with others? Put it in **Google Drive** (or
similar) and link to it from the reference note instead.
