# Git
As you are working on a feature or fix, commit at naturally intervals with commit messages following the conventional commits standard. 

Once you have finished working on a feature, push the branch to the remote and setup a PR for review. 

## Commits
Use Conventional Commits: `<type>(<scope>): <subject>`
- Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
- Subject: imperative, lowercase, no trailing period, ≤72 chars
- Breaking changes: `!` after scope + `BREAKING CHANGE:` footer
- Example: `fix(auth): handle expired refresh tokens`
