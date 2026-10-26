# MATLAB / Simulink Helpers

A collection of independent and reusable MATLAB/Simulink utilities.

Follow the global `AGENTS.md` for engineering autonomy, Git workflow, documentation standards, and delivery.

## Architecture
- Organize tools under `tools/<tool_name>/`.
- Prefer self-contained tools that can run directly without installation or repository-wide setup.
- Multi-file implementations, packages, classes, and shared helpers are allowed when they improve maintainability, reuse, or testability.
- Keep tool dependencies explicit. Avoid unnecessary coupling between unrelated tools.
- Refactor or reorganize tool boundaries when justified by the implementation.

## MATLAB Conventions
- Match public function names with their M-file names.
- Use verb-first camelCase for new public functions. Follow existing conventions for private and local helpers.
- Prefer an `opts` struct for configurable operations, especially when multiple optional settings are needed.
- Use non-destructive defaults. Require explicit intent for destructive modifications.
- Target the current Simulink system when appropriate, but support explicit model or path selection.
- Return structured results or reports when useful. Print concise summaries for interactive calls without outputs.
- Preserve existing public APIs when practical; document intentional breaking changes and migrations.

## Simulink / AUTOSAR
- Detect AUTOSAR bus-element Inport/Outport blocks using `IsBusElementPort == 'on'`. Do not infer bus-element ports from the `Element` parameter alone.
- Respect Simulink model state, loaded dictionaries, architecture interfaces, and existing mappings.
- Avoid unintended model changes, data loss, and destructive operations.
- Support the repository's declared MATLAB/Simulink version and required toolboxes.
- Prefer APIs and mechanisms supported by the target MATLAB release.

## Documentation and Versioning
- Maintain useful M-file help headers covering purpose, options, examples, and dependencies.
- Keep the README feature table aligned with supported tools and capabilities.
- Version tools independently using MAJOR.MINOR.PATCH when a user-visible release is made.
- Keep version references synchronized across M-file help, README, and CHANGELOG.
- Keep all M-files in the interface GUI bundle on the same version.

## Verification
- Run `mh_lint .` for relevant code changes.
- Exercise affected MATLAB/Simulink behavior in a live MATLAB session when available.
- For interface changes, run `tests/testInterfaceTools.m`.
- Add or improve automated tests when implementation complexity or regression risk justifies them.
- Report runtime checks that could not be executed.
- Documentation-only changes require relevant document, link, and diff checks.