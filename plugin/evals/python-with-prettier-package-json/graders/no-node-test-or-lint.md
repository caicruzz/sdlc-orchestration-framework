---
type: regex
target:
  source: file
  path: .ai-factory/config.md
flags: m
match: not_contains
pattern: '^\| \*\*(Test|Lint)\*\* \|[^\n]*\b(npm|npx|pnpm|yarn|bun)\b'
---
