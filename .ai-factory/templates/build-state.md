# Build state: <slug>

<!-- Written only by the factory-build orchestrator. A fresh orchestrator reads
     this to resume the build. Task files stay the source of truth for status,
     iterations, feedback and PR links; this file holds only what they do not. -->

| Field | Value |
|---|---|
| **Status** | <!-- active | handoff-pending | complete --> |
| **Base branch** | <!-- e.g. main --> |
| **Epic branch** | factory/<slug> |
| **Rounds this session** | <!-- e.g. 3 / 6 (handoff_after_rounds) --> |
| **Last updated** | <!-- ISO 8601 timestamp --> |

## Tasks in flight

<!-- One row per task whose loop is running or stopped mid-round. Leave empty
     when nothing is running. Step is A, B, C or D from factory-build. -->

| Task | Step | Iteration | Note |
|---|---|---|---|
| <!-- T001 --> | <!-- B --> | <!-- 2 / 3 --> | <!-- e.g. Coder was running when the session ended --> |

## Notes from the human

<!-- Build-wide instructions or decisions the human gave in chat that are not
     in any task file. Task-specific instructions go in that task file instead.
     Append only. -->

## Waiting on the human

<!-- PRs to merge, escalations to resolve, questions asked and not answered. -->

## Next step

<!-- One or two sentences: what the next orchestrator should do first. -->
