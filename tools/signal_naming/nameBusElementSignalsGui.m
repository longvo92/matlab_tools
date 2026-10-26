function fig = nameBusElementSignalsGui(sys, opts)
%NAMEBUSELEMENTSIGNALSGUI Preview and apply bus-element signal names.
% Version: 2.0.2 (Signal naming).
%   nameBusElementSignalsGui
%   fig = nameBusElementSignalsGui('MyModel/Subsystem')
%   fig = nameBusElementSignalsGui(gcs, struct('overwrite', true))
%
% SYS defaults to the current Simulink system. Use current refreshes it.
% OPTS initializes nameBusElementSignals options. The GUI exposes overwrite,
% recurse, and propagate; remaining options retain their
% backend defaults or supplied values. Preview always uses dryRun=true.
% Apply edits the model in memory without saving it. Verbose output is off.
% In Bus Element first lines keep their propagation setting. Out Bus Element
% tracing stops at Signal Copy/Conversion and Signal Specification outputs.
% Function Element Call / Function Element blocks without data ports are skipped.
% The latest backend report is available in fig.UserData.Report.
%
% Copy this file with nameBusElementSignals.m onto the MATLAB path.
% No other repository files or installation are required.

    if nargin < 1 || isempty(sys), sys = local_currentSystem(); end
    if nargin < 2, opts = struct(); end
    validateattributes(opts, {'struct'}, {'scalar'});
    validateattributes(sys, {'char', 'string'}, {'scalartext'});
    if isempty(which('nameBusElementSignals'))
        error('SignalNaming:MissingBackend', ...
            'Copy nameBusElementSignals.m alongside this GUI on the MATLAB path.');
    end
    if (isfield(opts, 'prefix') && ~isempty(char(opts.prefix))) || ...
            (isfield(opts, 'useLeafName') && any(opts.useLeafName(:)))
        error('SignalNaming:RemovedOption', ...
            'prefix and useLeafName have been removed. Names use the full Element path.');
    end
    defaults = struct('overwrite', false, 'recurse', true, 'propagate', true);
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        field = fields{k};
        if ~isfield(opts, field) || isempty(opts.(field))
            opts.(field) = defaults.(field);
        end
    end
    busy = false;
    fig = uifigure('Name', 'Bus Element Signal Naming v2.0.2', ...
        'Position', [220 140 840 480], 'CloseRequestFcn', @(~, ~) closeGui());
    fig.UserData = struct('Report', [], 'Mode', '', 'Error', '');
    grid = uigridlayout(fig, [7 1], ...
        'RowHeight', {26, 30, 26, 32, 24, '1x', 22}, ...
        'Padding', [16 12 16 12], 'RowSpacing', 8);
    uilabel(grid, 'Text', 'Bus Element Signal Naming', ...
        'FontSize', 18, 'FontWeight', 'bold');
    targetGrid = uigridlayout(grid, [1 3], ...
        'ColumnWidth', {110, '1x', 100}, 'Padding', [0 0 0 0]);
    uilabel(targetGrid, 'Text', 'Model / subsystem');
    target = uieditfield(targetGrid, 'text', 'Value', char(sys), 'Tag', 'TargetSystem', ...
        'Placeholder', 'MyModel or MyModel/Subsystem', ...
        'ValueChangedFcn', @(~, ~) invalidate());
    current = uibutton(targetGrid, 'Text', 'Use current', 'Tag', 'UseCurrent', ...
        'ButtonPushedFcn', @(~, ~) useCurrent());
    optionGrid = uigridlayout(grid, [1 3], ...
        'ColumnWidth', {'1x', '1x', '1x'}, 'RowHeight', {22}, ...
        'Padding', [0 0 0 0]);
    recurse = uicheckbox(optionGrid, 'Text', 'Include subsystems', ...
        'Value', opts.recurse, 'Tag', 'Recurse', 'ValueChangedFcn', @(~, ~) invalidate());
    overwrite = uicheckbox(optionGrid, 'Text', 'Overwrite existing names', ...
        'Value', opts.overwrite, 'Tag', 'Overwrite', 'ValueChangedFcn', @(~, ~) invalidate());
    propagate = uicheckbox(optionGrid, 'Text', 'Show propagated names', ...
        'Value', opts.propagate, 'Tag', 'Propagate', ...
        'Tooltip', 'Enable supported Out Bus Element source labels; leave In Bus Element first lines unchanged.', ...
        'ValueChangedFcn', @(~, ~) invalidate());
    actionGrid = uigridlayout(grid, [1 3], ...
        'ColumnWidth', {120, 120, '1x'}, 'Padding', [0 0 0 0]);
    preview = uibutton(actionGrid, 'Text', 'Preview', 'Tag', 'Preview', ...
        'ButtonPushedFcn', @(~, ~) runNaming(true));
    apply = uibutton(actionGrid, 'Text', 'Apply', 'Tag', 'Apply', ...
        'ButtonPushedFcn', @(~, ~) runNaming(false));
    status = uilabel(grid, 'Text', 'Ready. Preview to inspect proposed signal names.', ...
        'Tag', 'Status', 'Interpreter', 'none');
    results = uitable(grid, 'Data', cell(0, 6), 'Tag', 'NamingResults', ...
        'ColumnName', {'Kind', 'Element', 'Signal name', 'Status', 'Propagation', 'Block'}, ...
        'ColumnWidth', {45, 130, 130, 180, 90, 'auto'}, ...
        'ColumnEditable', false, 'RowName', {});
    uilabel(grid, 'Text', 'Apply updates the model in memory. Save it in Simulink after review.');
    controls = [target, current, recurse, overwrite, propagate, preview, apply];

    function useCurrent()
        target.Value = local_currentSystem();
        invalidate();
    end

    function invalidate()
        results.Data = cell(0, 6);
        status.Tooltip = '';
        fig.UserData = struct('Report', [], 'Mode', '', 'Error', '');
        status.Text = 'Settings changed. Run Preview to compare.';
    end

    function runNaming(dryRun)
        invalidate();
        system = strtrim(target.Value);
        if isempty(system)
            status.Text = 'Enter a model/subsystem or open one and select Use current.';
            fig.UserData.Error = status.Text;
            return;
        end
        busy = true;
        setControls('off');
        cleanup = onCleanup(@() finish());
        status.Text = 'Processing...';
        drawnow;
        runOpts = opts;
        runOpts.recurse = recurse.Value;
        runOpts.overwrite = overwrite.Value;
        runOpts.propagate = propagate.Value;
        runOpts.dryRun = dryRun;
        runOpts.verbose = false;
        try
            report = nameBusElementSignals(system, runOpts);
            data = cell(numel(report), 6);
            for row = 1:numel(report)
                data(row, :) = {report(row).kind, report(row).element, report(row).name, ...
                    report(row).status, report(row).propagated, report(row).block};
            end
            results.Data = data;
            if dryRun, mode = 'Preview'; else, mode = 'Apply'; end
            fig.UserData = struct('Report', report, 'Mode', mode, 'Error', '');
            errors = sum(startsWith({report.status}, 'error:') | ...
                startsWith({report.propagated}, 'err:'));
            status.Text = sprintf('%s: %d ports, %d proposed, %d named, %d errors.', ...
                mode, numel(report), sum(startsWith({report.status}, 'dry-run')), ...
                sum(startsWith({report.status}, 'set')), errors);
        catch ME
            fig.UserData.Error = ME.message;
            status.Text = ['Error: ' ME.message];
            status.Tooltip = ME.message;
        end
    end

    function setControls(state)
        if ~isvalid(fig), return; end
        for n = 1:numel(controls)
            controls(n).Enable = state;
        end
    end

    function finish()
        busy = false;
        setControls('on');
    end

    function closeGui()
        if ~busy, delete(fig); end
    end
end

function sys = local_currentSystem()
    sys = gcs;
    if isempty(sys), sys = ''; end
end
