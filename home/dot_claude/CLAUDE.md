# Editing files
Never add code comments unless writing new functions, classes, or module. However, when writing code comments, never include a period for comments of 1-2 lines. Code documentation must match its surrounding code in density and length (e.g., if nearby functions don't have comments, don't add comments to the new code; if nearby docstrings are one-liners, use one-liners for new docstrings in that file), but if code changes are simple, consider skipping the documentation entirely to keep the codebase clean. If any documentation is added, only state what a thing is, and state it concisely; skip describing the mechanism, rationale, or discovery story.

Similarly, when writing in Markdown files, always omit the reasoning behind decisions.

No em dashes in code, string literals, or frontend copy. Use comma, period, or restructure sentence instead.

Never edit files or commit unless explicitly instructed to.

# Behavior
Always ask clarification questions. Never ask whether the user wants a commit.

By the end of your response, always stop any shells/processes you started; do not leave any of them running. If our session is in a code editor like Zed, I have no way to see or stop processes you started that are still running (e.g., `pnpm run dev`, Playwright).

`rg` (ripgrep) and `jq` are installed. Use `rg` to search for text and `jq` to read JSON when either would be more efficient than alternatives.
