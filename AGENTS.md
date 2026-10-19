# MATLAB / Simulink Helpers

- Keep tools independent under `tools/<tool_name>/`: one M-file, two at most.
  The existing interface GUI bundle is an exception. No shared repo helpers or installation step.
- Match function and file names. Use verb-first camelCase for new public functions
  and local functions (usually `local_*`) for internal helpers; preserve existing APIs.
- Use an `opts` struct, non-destructive defaults, and current-system targets where appropriate.
  Return a result/report; print a concise summary when called without outputs.
- Keep help headers (purpose, options, example, dependencies) and the README feature table current.
- Version tools independently with MAJOR.MINOR.PATCH; update M-file help, README versions,
  and CHANGELOG together. Keep all interface bundle M-files on the same version.
- Detect AUTOSAR bus-element Inport/Outport blocks with `IsBusElementPort == 'on'`;
  the `Element` parameter alone is insufficient.
- Run `mh_lint .`. Exercise changed MATLAB/Simulink behavior in a live session;
  state when execution is unverified. For interface changes, run `tests/testInterfaceTools.m`.
  Documentation-only edits need link, rendering, and diff checks.
- Preserve unrelated work and private data. Commit scoped changes, push the task branch,
  and create/update a PR after checks; use a draft if verification is incomplete.
  Merge, release, and deploy only when requested.
