# MATLAB / Simulink Helpers
Independent tools under tools/<tool_name>/, copied directly into an engineer's MATLAB path.

## Constraints
- Each tool works from one .m file (two files maximum); no shared repo helpers, package installation or download step.
- Internal helpers are local functions, conventionally local_*. Main function and file names match; public names are camelCase, verb-first.
- Use an opts struct, safe non-destructive defaults and current-system targets where appropriate.
- Return a result/report; print a concise summary when nargout == 0.
- Maintain the help header (purpose, arguments/options, example and repo-dependency note) and README tool table when behavior changes.
- AUTOSAR bus-element ports are Inport/Outport blocks: detect IsBusElementPort == 'on'. Presence of the Element parameter alone gives false positives.

## Verification
Exercise changed tools in a live MATLAB/Simulink session when available. Otherwise sanity-check syntax/API usage and state explicitly that MATLAB execution is unverified. Use existing lint/CI checks where applicable.
## Delivery
Follow global Git autonomy: commit scoped changes, push the task branch and create/update a PR without another approval after relevant checks. Use a draft when verification is incomplete. Merge, release and deploy require a request. Preserve unrelated work and private data.
