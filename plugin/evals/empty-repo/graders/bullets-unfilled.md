---
type: regex
target:
  source: file
  path: .ai-factory/config.md
flags: m
match: not_contains
pattern: '^- \*\*[^*\n]+\*\*: (?!<!--)'
---
