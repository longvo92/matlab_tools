# matlab_tools

Small, self-contained MATLAB / Simulink helper tools for day-to-day MBD work.

Every tool is a single `.m` file (two at most) with **no cross-tool dependencies**.
That means you can grab a tool straight from the GitHub web UI — open the file,
copy its contents into your MATLAB path — without cloning or downloading the repo.

## Layout

```
tools/
  <tool_name>/<mainFunction>.m   # one folder per tool, function name = file name
```

Each `.m` file starts with an `help` block documenting its arguments, options,
and an example, so `help <functionName>` works after you copy it in.

## Tools

| Tool | File | What it does |
|------|------|--------------|
| Bus element signal naming | [`tools/signal_naming/nameBusElementSignals.m`](tools/signal_naming/nameBusElementSignals.m) | Names Bus Selector output / Bus Creator input signals after their top-level bus element and turns on propagated-signal display. Built for AUTOSAR-style models. |
| Quick simulation setup | [`tools/quick_sim/quickSimEnv.m`](tools/quick_sim/quickSimEnv.m) | Creates a new empty model, loads a data `.mat` you name into the base workspace, and auto-links the first config set found in the base workspace. |

## Usage

Copy a tool's `.m` file somewhere on your MATLAB path, then call it. Examples:

```matlab
% Name the current system's bus element signals and show propagated names
nameBusElementSignals(gcs)

% New model + load stimuli + auto-link a config set from the base workspace
quickSimEnv('drive_cycle.mat')
```

See each file's header (`help nameBusElementSignals`, `help quickSimEnv`) for the
full option list.

## License

MIT — see [LICENSE](LICENSE).
