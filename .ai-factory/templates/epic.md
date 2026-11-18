# Epic: <title>

## Summary

Short overview of scope and outcomes.

## Task list

| ID | Title | Depends on |
|----|-------|------------|
| T001 | (title) | none |
| T002 | (title) | T001 |

## Task dependency graph

Prerequisite direction: an edge from **A** to **B** means **B depends on A**
(A completes before B).

```mermaid
flowchart TD
  T001["T001"]
  T002["T002"]
  T003["T003"]
  T001 --> T003
  T002 --> T003
  %% For parallel streams, define one classDef per stream + mergeNode; assign with class.
  %% classDef streamA fill:#e3f2fd
  %% classDef streamB fill:#fce4ec
  %% classDef mergeNode fill:#eceff1
  %% class T001 streamA
  %% class T002 streamB
  %% class T003 mergeNode
  %% Single chain or no parallelism: one style for all nodes, e.g.:
  classDef defaultNode fill:#f5f5f5
  class T001,T002,T003 defaultNode
```

### Legend

Replace with bullets that map each stream to its color and task IDs, plus
merge nodes if used. For a single `defaultNode` style, one bullet is enough
(e.g. “All tasks: neutral gray fill”).

- Stream A (example): T001
- Stream B (example): T002
- Merge (example): T003
