---
type: regex
target:
  source: file
  path: .gitignore
flags: m
pattern: '^(?=[\s\S]*^\.ai-factory/projects/\*$)(?=[\s\S]*^!\.ai-factory/projects/\.gitkeep$)(?=[\s\S]*^\.ai-factory/archive/\*$)(?=[\s\S]*^!\.ai-factory/archive/\.gitkeep$)'
---
