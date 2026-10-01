# Engineering
When editing READMEs, keep text simple and always omit the reasoning behind decisions unless otherwise specified.

No em dashes in code, string literals, or frontend copy. Use comma, period, or restructure sentence instead.

When committing or creating new branches, always follow the convention set by previous commits or branches for commit messages and branch names.

Never include Claude as a co-author of commits.

# Behavior
Always ask clarification questions.

By the end of your response, always stop any shells/processes you started; do not leave any of them running. If our session is in a code editor like Zed, I have no way to see or stop processes you started that are still running (e.g., `pnpm run dev`, Playwright).

`rg` (ripgrep) and `jq` are installed. Use `rg` to search for text and `jq` to read JSON when either would be more efficient than alternatives.
