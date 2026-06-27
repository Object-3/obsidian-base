# `_local/` — files that stay on your machine (never committed)

Everything in this folder (except this README and `.gitkeep`) is **gitignored** — it
stays on your machine and never reaches GitHub.

It's the **escape hatch** for files too big or too sensitive for git: PDFs, large
images, datasets, exports, anything private. You don't have to remember to use it —
the pre-commit size guard blocks oversized files and points you here. Just move the
file in and carry on. Obsidian can still embed/preview it, and your local agents (and
the Obsidian MCP) can still read it straight off disk.

When a file here matters to the knowledge, leave a small **reference note** in the
vault (in git) that captures the key points and points to it — that's how the KB
"knows about" it without storing the bytes.

Need a file on multiple devices or shared with others? Put it in **Google Drive** (or
similar) and link to it from a note instead.
