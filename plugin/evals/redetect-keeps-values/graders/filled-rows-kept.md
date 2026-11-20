---
type: regex
target:
  source: file
  path: .ai-factory/config.md
pattern: '^# soloAIfactory Project Configuration\n\nEdit this file to match your project''s tech stack and conventions\.\nThe Architect, Planner, Coder, Reviewer, and Verifier agents all read this file\.\n\n## Tech Stack\n\n- \*\*Language\*\*: Go\n- \*\*Runtime\*\*: [^\n]*\n- \*\*Framework\*\*: [^\n]*\n- \*\*Package Manager\*\*: [^\n]*\n\n## Project Structure\n\n- \*\*Source directory\*\*: [^\n]*\n- \*\*Test directory\*\*: [^\n]*\n- \*\*Entry point\*\*: [^\n]*\n- \*\*Config files\*\*: [^\n]*\n\n## Commands\n\n\| Check \| Command \| Notes \|\n\|---\|---\|---\|\n\| \*\*Install\*\* \|[^\n]*\n\| \*\*Test\*\* \| `go test -race \./\.\.\.` \| Required \|\n\| \*\*Lint\*\* \| `golangci-lint run` \| Required \|\n\| \*\*Type check\*\* \|[^\n]*\n\| \*\*Build\*\* \|[^\n]*\n\| \*\*Format\*\* \|[^\n]*\n\n## Conventions\n\n- \*\*Code style\*\*: [^\n]*\n- \*\*Naming\*\*: [^\n]*\n- \*\*Commit style\*\*: [^\n]*\n- \*\*Test naming\*\*: [^\n]*\n- \*\*Import style\*\*: [^\n]*\n\n## Architecture Notes\n[\s\S]*$'
---
