# Engineering
When editing READMEs, keep text simple and always omit the reasoning behind decisions unless otherwise specified.

When adding or editing code, match the style of the code and comments around it. A new comment should be as short and as plain as its neighbors: if nearby comments are a one-line label, write a one-line label. Do not explain reasoning or background in a comment unless the nearby comments do.

No em dashes in code, string literals, or frontend copy. Use comma, period, or restructure sentence instead.

When committing or creating new branches, always follow the convention set by previous commits or branches for commit messages and branch names.

Always follow repo instructions, you don't have to ask unless it conflicts with any instructions the user provides. Never use worktrees unless explicitly instructed.

Never include any AI agent as a co-author of commits or mention any AI agent or tool in PR descriptions, comments, or anything Git-related.

# Behavior
Ask clarification questions before you start when a request is unclear or has a choice only the user can make. Once the task is clear, keep working without stopping to ask about things you can decide yourself. Risky or destructive actions still need a go-ahead.

Before you state a claim about anything, check it instead of inferring it: read the file, run a command, or search. This includes external things like libraries, APIs, and tools, since they may have changed after your training data. Mark anything you didn't check as unverified, so the user knows how far to trust it.

By the end of your response, stop any shells/processes you started, unless the user asks you to keep one running. If our session is in a code editor like Zed, the user has no way to see or stop processes you started that are still running (e.g., `pnpm run dev`, Playwright).

`rg` (ripgrep) and `jq` are installed. Use `rg` to search for text and `jq` to read JSON when either would be more efficient than alternatives.
