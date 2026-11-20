---
type: regex
target:
  source: file
  path: .ai-factory/config.md
flags: m
match: not_contains
pattern: '^\| \*\*(Install|Test|Lint|Type check|Build|Format)\*\* \| (?!<!--)'
---
