---
name: repo-onboarding
description: Map an unfamiliar repository before substantial implementation, debugging, migration, or architectural work. Use when understanding boundaries, data flow, conventions, and validation commands will materially improve the change.
---

# Repository Onboarding

Build a compact, evidence-based model of the repository before changing it.

1. Read the applicable `CLAUDE.md` files, the main README, manifests, and contributor
   documentation.
2. Inspect the working tree and preserve existing uncommitted changes.
3. Identify entry points, module boundaries, public interfaces, persistence boundaries,
   external services, and generated code.
4. Trace the specific behavior relevant to the request from input to output. Prefer
   symbol and reference searches over reading whole directories. For a broad sweep
   across many files, dispatch the `Explore` agent rather than reading them yourself.
5. Derive build, test, lint, and formatting commands from repository configuration
   rather than guessing.
6. State only findings that affect the task. Mark uncertain conclusions and resolve them
   through targeted inspection.

Finish with the files and interfaces likely to change, the validation path, and any
compatibility constraint the implementation must preserve.
