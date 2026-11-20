# factory-setup detection reference

Detection heuristics for step 4 of [`SKILL.md`](SKILL.md). **The agent proposes, the human decides.** Every proposed value needs evidence (the file or line that suggested it); when nothing reliable is found, the field stays unfilled with the reason. **An unfilled placeholder is preferred to a guess.**

Inspection is read-only: list files with `git ls-files`, read files, and read `git log -20 --format=%s`. Never run project code. A failing `git log` (no commits) means "no commit history".

## Ecosystem table

| Marker | Language / PM | Test | Lint | Type check | Build |
|---|---|---|---|---|---|
| `package.json` | TS if `tsconfig.json`, else JS; PM from lockfile (`pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, else npm) | `<pm> test` if `scripts.test` is real | `<pm> run lint` if script | `<pm> run typecheck` if script, else `npx tsc --noEmit` if `tsconfig.json` | `<pm> run build` if script |
| `pyproject.toml` / `requirements*.txt` | Python; `uv.lock`→uv, `poetry.lock`→poetry, else pip | `pytest` (prefixed `uv run`/`poetry run`) if pytest configured, referenced, or `tests/` has `.py` | `ruff check .` if ruff configured, else `flake8` if configured | `mypy .` if configured | `none` |
| `go.mod` | Go | `go test ./...` | `golangci-lint run` if `.golangci.y*ml`, else `go vet ./...` | `none` | `go build ./...` |
| `Cargo.toml` | Rust / cargo | `cargo test` | `cargo clippy -- -D warnings` | `none` | `cargo build` |
| `*.sln` / `*.csproj` | C# / dotnet | `dotnet test` | `dotnet format --verify-no-changes` | `none` | `dotnet build` |
| `pom.xml` / `build.gradle*` | Java/Kotlin / maven or gradle | `mvn test` / `./gradlew test` | `./gradlew check` if configured, else unfilled | `none` | `mvn package` / `./gradlew build` |

Notes on the table:

- **"Configured"** means the tool has a config section or file in the repo (for example `[tool.ruff]` in `pyproject.toml` or a `ruff.toml`; `[tool.pytest.ini_options]`, `pytest.ini` or `conftest.py`; `[tool.mypy]` or `mypy.ini`; `.flake8` or `[flake8]` in `setup.cfg`/`tox.ini`), or is listed as a dependency. **"Referenced"** means it appears in a dependency list, CI config or task-runner target.
- **Install** follows the package manager: `npm install` / `pnpm install` / `yarn install` / `bun install`, `uv sync`, `poetry install`, `pip install -r requirements.txt` (only if that file exists), `go mod download`, `cargo fetch`, `dotnet restore`. Leave unfilled when unsure.
- **Format** is proposed only when a formatter is configured (for example `prettier --check .` with a Prettier config, `ruff format --check .` with ruff configured, `gofmt -l .`, `cargo fmt --check`); otherwise leave unfilled.
- **Not-applicable optional rows** (Type check, Build, Format) are written as `none`, which the Verifier treats as `skipped`. Test and Lint are never `none`.
- Tech Stack and Project Structure come from the same evidence: the language and package manager from the marker; Runtime from `engines`, `.nvmrc`, `.python-version`, `requires-python`, the `go` directive, `rust-toolchain*`, `TargetFramework`; Framework from direct dependencies (for example `next`, `fastapi`, `django`, `express`); Source and Test directories from `git ls-files` (`src/`, `tests/`, `__tests__/`, `*_test.go`); Config files from the marker and tool config files actually present.

## Command precedence

When several sources suggest a command, the precedence, **highest first**, is:

1. **A hint in the request** (for example "lint is `make lint`").
2. **A task-runner target** named test / lint / typecheck / build in `Makefile`, `justfile`, `Taskfile.yml`, `tox.ini` or `noxfile.py` (for example `make test`, `just lint`, `task build`, `tox -e lint`, `nox -s tests`).
3. **A package-manager script** (for example `scripts.lint` in `package.json`).
4. **The plain command a CI config runs** (`.github/workflows/*.yml`, `.gitlab-ci.yml`), copied as written when it is a single plain command.
5. **The ecosystem default** from the table, used **only when the tool is configured or built in**.

Precedence chooses values **only for unfilled rows**. A configured row is `kept` even when a source above suggests a different command (for example CI runs `bash scripts/test.sh` while **Test** is `/bin/bash scripts/test.sh`); never propose that command as a replacement.

## Edge cases

In apply-without-review mode, every "ask" below becomes "leave the field unfilled and state the reason", for example `Test: unfilled; polyglot (Python, Go) with no task runner`.

Every "ask" below covers **only unfilled, in-scope fields**. A configured row (for example a human-written **Test** or **Lint**) is shown as `kept` and is never asked about again.

### Placeholder npm test script

`package.json` created by `npm init` has `"test": "echo \"Error: no test specified\" && exit 1"`. A `scripts.test` that contains `no test specified` (case-insensitive), or consists of `echo …` followed by `exit 1`, counts as **no test**. Test is Required, so it stays unfilled with the Verifier warning ("Verifier will fail as *not configured* until **Test** is set; `factory-build` will stop and ask you.") until the human sets it. **Setup never proposes `true`** (or any other no-op); a repo without tests sets Test explicitly, by the human's choice.

### No lint configured

Propose a zero-config built-in **only where one exists**: `go vet ./...` (Go), `cargo clippy` (Rust). Otherwise leave Lint unfilled and name the idiomatic tool in the evidence (for example "not detected; left unfilled: no lint tool configured (idiomatic: ruff)" for Python, eslint for JS/TS) **without adding dependencies** or installing anything.

### Polyglot repos

- If a **task-runner target** covers everything (for example `make test` that runs both suites), use it.
- If **exactly one** ecosystem has a test signal, it is **primary**.
- If **several** have test signals (for example Python and Go) and there is no task runner, **ask the human** to pick one or compose them with `&&`. **Never choose silently**, and never compose with `&&` on your own.
- List **every detected ecosystem** under Tech Stack (Language) and Architecture Notes.

### Tooling-only package.json

A `package.json` that only configures tooling (for example Prettier, husky, lint-staged, commitlint) in a repo whose code is another language has **no Node test signal**, so Node is **not primary**. It may still suggest Format (Prettier) and is listed under Tech Stack only as tooling.

### Monorepo workspaces

When `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, `turbo.json` (turbo) or `nx.json` (nx) is present, **prefer root scripts** (for example `pnpm -r test`, `turbo run test`, `nx run-many -t test`, or a root `scripts.test`). If there are **no root scripts**, ask the human which command to use.

### Empty repo

With **no marker files**, every value is unfilled. Ask the human for the language and the commands (Test and Lint at least). On re-detect, or whenever `config.md` already has values, ask only for the unfilled rows: a repo with no marker files whose config already has **Test** and **Lint** (for example a Bash or Markdown repo) keeps them as `kept`. Still propose the `.gitkeep` files and `.gitignore` lines when they are in scope.

### Conventions

- **Commit style**: Conventional Commits when **most** of the last 20 commit subjects (`git log -20 --format=%s`) match `^\w+(\(.+\))?!?:`. Otherwise, or with no commit history, leave unfilled.
- **Code style**: from formatter config files (`.prettierrc*`, `prettier` key in `package.json`, `[tool.black]`, `[tool.ruff.format]`, `rustfmt.toml`, `.editorconfig`, `gofmt` for Go).
- **Naming**, **Test naming** and **Import style**: stay unfilled unless obvious from the files (an unfilled placeholder is preferred to a guess).

### Existing values

Never propose a replacement for a configured row. On "re-detect", configured rows are shown as `kept` and only unfilled rows and absent `.gitignore` lines are proposed.
