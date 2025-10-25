# Git Hook Examples

Copy `post-commit.ps1` into `.git/hooks/post-commit` (remember to `chmod +x` on macOS/Linux) and update the `RepoRoot`/`TasksDir`
as needed. The hook enqueues a `git status -sb` task after every commit so the worker can pick it up immediately.
