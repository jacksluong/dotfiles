# Engineering
When editing READMEs, keep text simple and always omit the reasoning behind decisions unless otherwise specified.

When adding or editing code, match the style of the code and comments around it. A new comment should be as short and as plain as its neighbors: if nearby comments are a one-line label, write a one-line label. Do not explain reasoning or background in a comment unless the nearby comments do.

No em dashes in code, string literals, or frontend copy. Use comma, period, or restructure sentence instead.

When committing or creating new branches, always follow the convention set by previous commits or branches for commit messages and branch names.

Always follow repo instructions, you don't have to ask unless it conflicts with any instructions the user provides.

Never include any AI agent as a co-author of commits or mention any AI agent or tool in PR descriptions, comments, or anything Git-related.

This machine does not have `npm` or `npx` installed; it exclusively uses `pnpm` and `pnpm dlx` instead, with node installed via `pnpm`.

# Worktrees
Make code changes in a git worktree, so the user's main checkout stays as it is. Skip this for read-only tasks, files outside a git repo, the `~/Developer/dotfiles` and `~/Developer/skills` repos, or when the user says to work in the current checkout. If the repo's instructions say how to use worktrees, follow them instead.

Before you change code, pick where to work, in this order:
1. If the user or a parent agent gave you a directory, work there.
2. If the session started in a linked worktree (`git rev-parse --git-dir` differs from `--git-common-dir`), work there unless the task is about a different branch.
3. If you used a worktree earlier in this session for the same task, check that it still exists and is on the expected branch, then keep using it.
4. If the task is about an existing branch or PR, look for its branch in `git worktree list --porcelain`. If the main checkout has it, work there. If a linked worktree has it and has uncommitted changes you did not make, ask before using it, since another session may be working there.
5. Otherwise, create a worktree at `.worktrees/<branch>` in the main checkout's root, the parent of `git rev-parse --path-format=absolute --git-common-dir`. For a PR, use `gh pr checkout <number> --worktree <path>`. For new work, branch from the freshly fetched default branch unless the task builds on another branch. If the task depends on uncommitted changes in the main checkout, ask first.

If your harness can switch the session into the worktree, do that. Then:
- Use the worktree's path for every read, edit, and command, including paths the user gives in the main checkout. Give subagents the worktree's path.
- Install dependencies the way the repo's docs describe, and copy the ignored files the code needs, such as `.env`, from the main checkout.
- When you finish, tell the user the worktree's path and branch.

Remove a worktree when its PR has merged, or when you created it in this session and made no changes in it. Switch the session out of it first, then run `git worktree remove <path>` and delete its local branch with `git branch -D`, since squash merges leave it unmerged. If the worktree has uncommitted changes, or the branch has commits the PR lacks, ask first. Leave other worktrees alone unless the user asks.

# Worktree progress

- For coding tasks, keep a `.progress.md` at the root of the assigned checkout. Get the root by running `git rev-parse --show-toplevel` from that checkout. Read any existing note before starting work. Once the goal is clear, create the note before editing code.
- If you're resuming the task, check `git status` and the relevant diff against the note before continuing. Only one session should own the note at a time. Keep it out of commits and leave it behind when copying ignored files into a new worktree.
- Keep the note to one screen and rewrite it as work progresses. Include the status (`active`, `blocked`, or `done`), goal, acceptance criteria and user constraints, meaningful decisions and why, completed and in-progress work, verification commands and results, blockers, and the first concrete next step. Link to existing plans, issues, and relevant files. Leave out secrets.
- Update the note when the approach changes, a meaningful change lands, a check reveals something, or work gets blocked. Save it before long verification runs and before ending a turn that advanced the task. Mark it `done` when the task is complete.

# Behavior
Ask clarification questions before you start when a request is unclear or has a choice only the user can make. Once the task is clear, keep working without stopping to ask about things you can decide yourself. Risky or destructive actions still need a go-ahead.

Before you state a claim about anything, check it instead of inferring it: read the file, run a command, or search. This includes external things like libraries, APIs, and tools, since they may have changed after your training data. Mark anything you didn't check as unverified, so the user knows how far to trust it.

By the end of your response, stop any shells/processes you started, unless the user asks you to keep one running. If our session is in a code editor like Zed, the user has no way to see or stop processes you started that are still running (e.g., `pnpm run dev`, Playwright).

`rg` (ripgrep) and `jq` are installed. Use `rg` to search for text and `jq` to read JSON when either would be more efficient than alternatives.
