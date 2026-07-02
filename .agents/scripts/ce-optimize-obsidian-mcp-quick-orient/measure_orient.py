#!/usr/bin/env python3
"""Measurement harness for the obsidian-mcp-quick-orient ce-optimize run.
Immutable (scope.immutable) — experiment agents must not edit this file.

Runs each fixed benchmark question in a FRESH, isolated headless `claude -p`
session (system prompt = today's baseline text + the current candidate file),
restricted to read-only Obsidian MCP tools, and reports MCP call counts +
answers as JSON on stdout for the orchestrator to gate/judge.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

CANDIDATE_PATH = ".agents/mcp-quick-orient.md"
BASELINE_PATH = ".agents/scripts/ce-optimize-obsidian-mcp-quick-orient/baseline-system-prompt.md"
QUESTIONS_PATH = ".agents/scripts/ce-optimize-obsidian-mcp-quick-orient/questions.json"

ALLOWED_TOOLS = [
    "mcp__mcp-obsidian__obsidian_get_file_contents",
    "mcp__mcp-obsidian__obsidian_list_files_in_vault",
    "mcp__mcp-obsidian__obsidian_list_files_in_dir",
    "mcp__mcp-obsidian__obsidian_batch_get_file_contents",
    "mcp__mcp-obsidian__obsidian_simple_search",
    "mcp__mcp-obsidian__obsidian_complex_search",
    "ToolSearch",
]
DISALLOWED_TOOLS = [
    "mcp__mcp-obsidian__obsidian_append_content",
    "mcp__mcp-obsidian__obsidian_patch_content",
    "mcp__mcp-obsidian__obsidian_delete_file",
    "Bash",
    "Write",
    "Edit",
    "NotebookEdit",
    "Read",
    "Glob",
    "Grep",
    "WebFetch",
    "WebSearch",
    "Agent",
    "mcp__plugin_context7_context7__query-docs",
    "mcp__plugin_context7_context7__resolve-library-id",
    "mcp__plugin_playwright_playwright__browser_navigate",
    "mcp__plugin_playwright_playwright__browser_run_code_unsafe",
    "mcp__plugin_playwright_playwright__browser_evaluate",
    "mcp__plugin_playwright_playwright__browser_file_upload",
]

MODEL = os.environ.get("ORIENT_EVAL_MODEL", "sonnet")
MAX_BUDGET_USD = os.environ.get("ORIENT_EVAL_MAX_BUDGET_USD", "0.60")
TIMEOUT_SEC = int(os.environ.get("ORIENT_EVAL_TIMEOUT_SEC", "90"))


def read(path):
    with open(path) as f:
        return f.read()


def run_question(system_prompt, prompt, question_id):
    cmd = [
        "claude", "-p", prompt,
        "--model", MODEL,
        "--permission-mode", "bypassPermissions",
        "--system-prompt", system_prompt,
        "--output-format", "stream-json",
        "--verbose",
        "--max-budget-usd", MAX_BUDGET_USD,
        "--no-session-persistence",
        "--allowedTools", *ALLOWED_TOOLS,
        "--disallowedTools", *DISALLOWED_TOOLS,
    ]
    # Run from a neutral scratch directory OUTSIDE this repo (and outside any project
    # tree) so Claude Code's cwd-based CLAUDE.md/AGENTS.md auto-discovery can't inject
    # this repo's own project instructions as first-message context (that survives even
    # a --system-prompt override, unlike global CLAUDE.md/memory, which --system-prompt
    # does suppress). Without this, the subject would answer from local files instead of
    # the real Obsidian MCP vault, defeating the entire measurement.
    neutral_cwd = tempfile.mkdtemp(prefix="orient-eval-")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_SEC, cwd=neutral_cwd)
    except subprocess.TimeoutExpired:
        return {
            "id": question_id, "completed": False, "error": "timeout",
            "mcp_call_count": 0, "answer": "", "cost_usd": 0.0,
        }
    finally:
        shutil.rmtree(neutral_cwd, ignore_errors=True)

    mcp_call_count = 0
    answer_text = ""
    cost_usd = 0.0
    completed = False
    error = None

    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = evt.get("type")
        if t == "assistant":
            for block in evt.get("message", {}).get("content", []):
                if block.get("type") == "tool_use" and str(block.get("name", "")).startswith("mcp__mcp-obsidian__"):
                    mcp_call_count += 1
                if block.get("type") == "text":
                    answer_text = block["text"]
        elif t == "result":
            completed = (evt.get("subtype") == "success") and not evt.get("is_error", False)
            cost_usd = evt.get("total_cost_usd", 0.0) or 0.0
            if not completed:
                error = evt.get("result") or evt.get("subtype")

    if not completed and error is None:
        error = (proc.stderr[-500:] if proc.stderr else "unknown failure")

    return {
        "id": question_id,
        "completed": completed,
        "error": error,
        "mcp_call_count": mcp_call_count,
        "answer": answer_text,
        "cost_usd": cost_usd,
    }


def main():
    candidate = read(CANDIDATE_PATH) if os.path.exists(CANDIDATE_PATH) else ""
    baseline = read(BASELINE_PATH)
    system_prompt = baseline + "\n\n" + candidate

    questions = json.loads(read(QUESTIONS_PATH))["questions"]

    results = []
    for q in questions:
        r = run_question(system_prompt, q["prompt"], q["id"])
        r["category"] = q["category"]
        r["ground_truth"] = q["ground_truth"]
        r["prompt"] = q["prompt"]
        r["expected_min_mcp_calls"] = q["expected_min_mcp_calls"]
        results.append(r)

    all_completed = all(r["completed"] for r in results)
    max_mcp_call_count = max((r["mcp_call_count"] for r in results), default=0)
    avg_mcp_call_count = (sum(r["mcp_call_count"] for r in results) / len(results)) if results else 0.0
    total_cost_usd = sum(r["cost_usd"] for r in results)

    output = {
        "all_completed": 1 if all_completed else 0,
        "max_mcp_call_count": max_mcp_call_count,
        "avg_mcp_call_count": avg_mcp_call_count,
        "total_cost_usd": total_cost_usd,
        "items": results,
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
