---
name: dependency-evaluation
description: Evaluate or introduce a software dependency using current primary documentation, repository compatibility, maintenance, security, license, and total integration cost. Use when choosing, upgrading, replacing, or removing a package or tool.
---

# Dependency Evaluation

First determine whether existing platform or repository capabilities already solve the
need.

When a dependency is justified:

- Confirm the current supported release and behavior from the project's primary
  documentation or registry. Use Context7 when its indexed documentation is current and
  relevant.
- Check runtime and toolchain compatibility, transitive footprint, maintenance activity,
  license, security advisories, and platform support.
- Compare only realistic alternatives against the requirements that matter to this
  repository.
- Pin versions according to the repository's existing policy and update the lockfile with
  its native package manager.
- Integrate through the narrowest interface that keeps replacement possible, without
  speculative abstraction.
- Run the relevant build, tests, and vulnerability or license checks the project already
  uses.

Do not recommend a package on popularity alone, and do not introduce a paid service when
a free local solution satisfies the request.
