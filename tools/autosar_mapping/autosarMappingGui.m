function fig = autosarMappingGui(model, opts)
%AUTOSARMAPPINGGUI Preview/apply AUTOSAR Code Mappings (version 1.3.0).
%   autosarMappingGui opens a simple GUI for a loaded AUTOSAR Classic model.
%   autosarMappingGui(MODEL, OPTS) optionally sets Source (model CSV),
%   CalibrationConfig (global JSON, '' disables), and Visible ('on'/'off').
%   Empty Source runs global calibration rules only. The global JSON is shared
%   with configureAutosarMapping. Export CSV writes a new settings file.
%   Apply preview checks that model/config inputs still match the preview.
%   Changes stay in memory; save the model explicitly in Simulink.
%   Requires MATLAB/Simulink R2024a+, AUTOSAR Blockset. Copy the full bundle.
    if nargin < 1, model = []; end
    if nargin < 2, opts = struct(); end
    if ~isstruct(opts) || ~isscalar(opts) || ...
            any(~ismember(fieldnames(opts), {'Source', 'CalibrationConfig', 'Visible'}))
        error('AutosarMapping:Options', 'GUI opts accepts Source, CalibrationConfig, Visible.');
    end
    if ~isfield(opts, 'Source'), opts.Source = ''; end
    if ~isfield(opts, 'CalibrationConfig')
        opts.CalibrationConfig = fullfile(fileparts(mfilename('fullpath')), 'autosar_calibration_config.json');
    end
    if ~isfield(opts, 'Visible'), opts.Visible = 'on'; end
    validateattributes(opts.Source, {'char', 'string'}, {'scalartext'});
    validateattributes(opts.CalibrationConfig, {'char', 'string'}, {'scalartext'});
    visible = validatestring(opts.Visible, {'on', 'off'});
    selected = '';
    if ~isempty(model), selected = get_param(bdroot(model), 'Name');
    else
        current = bdroot;
        if ~isequal(current, 0) && ~isempty(current), selected = get_param(current, 'Name'); end
    end
    preview = [];
    fig = uifigure('Name', 'AUTOSAR Code Mappings v1.3.0', 'Tag', 'AutosarMappingGui', ...
        'Position', [180 150 1080 650], 'Visible', 'off', 'CloseRequestFcn', @closeWindow);
    grid = uigridlayout(fig, [6 1], 'RowHeight', {32, 32, 32, 34, '1x', 62}, ...
        'Padding', [12 12 12 12]);
    modelRow = uigridlayout(grid, [1 4], 'ColumnWidth', {135, '1x', 90, 90}, 'Padding', 0);
    uilabel(modelRow, 'Text', 'Model');
    models = uidropdown(modelRow, 'Items', {'<Load an AUTOSAR model>'}, ...
        'Tag', 'AutosarMappingModel', 'ValueChangedFcn', @invalidate);
    refresh = uibutton(modelRow, 'Text', 'Refresh', 'ButtonPushedFcn', @refreshModels);
    loadModel = uibutton(modelRow, 'Text', 'Load model', 'ButtonPushedFcn', @loadSelectedModel);
    csvRow = uigridlayout(grid, [1 4], 'ColumnWidth', {135, '1x', 90, 90}, 'Padding', 0);
    uilabel(csvRow, 'Text', 'Model CSV (optional)');
    csv = uieditfield(csvRow, 'text', 'Value', char(opts.Source), ...
        'Tag', 'AutosarMappingSource', 'ValueChangedFcn', @invalidate);
    browseCsv = uibutton(csvRow, 'Text', 'Browse', 'ButtonPushedFcn', @(~, ~) browseFile(csv, '*.csv'));
    editCsv = uibutton(csvRow, 'Text', 'Edit', 'ButtonPushedFcn', @(~, ~) editFile(csv));
    calibrationRow = uigridlayout(grid, [1 4], 'ColumnWidth', {135, '1x', 90, 90}, 'Padding', 0);
    uilabel(calibrationRow, 'Text', 'Global calib JSON');
    calibration = uieditfield(calibrationRow, 'text', 'Value', char(opts.CalibrationConfig), ...
        'Tag', 'AutosarMappingCalibration', 'ValueChangedFcn', @invalidate);
    browseCalibration = uibutton(calibrationRow, 'Text', 'Browse', ...
        'ButtonPushedFcn', @(~, ~) browseFile(calibration, '*.json'));
    editCalibration = uibutton(calibrationRow, 'Text', 'Edit', 'ButtonPushedFcn', @(~, ~) editFile(calibration));
    actions = uigridlayout(grid, [1 4], 'ColumnWidth', {120, 120, 120, '1x'}, 'Padding', 0);
    previewButton = uibutton(actions, 'Text', 'Preview', 'Tag', 'AutosarMappingPreview', 'ButtonPushedFcn', @runPreview);
    applyButton = uibutton(actions, 'Text', 'Apply preview', 'Tag', 'AutosarMappingApply', ...
        'Enable', 'off', 'ButtonPushedFcn', @runApply);
    exportButton = uibutton(actions, 'Text', 'Export CSV', 'Tag', 'AutosarMappingExport', 'ButtonPushedFcn', @exportCsv);
    uilabel(actions, 'Text', 'Apply changes in memory. Save the model explicitly in Simulink.', 'WordWrap', 'on');
    results = uitable(grid, 'Tag', 'AutosarMappingResults', 'ColumnEditable', false, ...
        'ColumnName', {'Category', 'Element', 'Property', 'Current', 'Desired', 'Status', 'Reason'}, ...
        'ColumnWidth', {180, 150, 155, 135, 135, 85, 'auto'}, 'RowName', {});
    status = uitextarea(grid, 'Editable', 'off', 'Tag', 'AutosarMappingStatus', ...
        'Value', {'Ready. Choose a model and run Preview. Empty CSV uses global calibration rules only.'});
    controls = {models, refresh, loadModel, csv, browseCsv, editCsv, calibration, ...
        browseCalibration, editCalibration, previewButton, applyButton, exportButton};
    fig.UserData = struct('Report', [], 'LastError', [], 'Busy', false);
    refreshModels();
    fig.Visible = visible;

    function refreshModels(varargin)
        if isBusy(), return; end
        if ~isempty(varargin), selected = models.Value; end
        names = find_system('SearchDepth', 0, 'BlockDiagramType', 'model');
        names = names(cellfun(@(name) strcmp(get_param(name, 'SystemTargetFile'), 'autosar.tlc'), names));
        if isempty(names), names = {'<Load an AUTOSAR model>'}; end
        models.Items = names;
        if ismember(selected, names), models.Value = selected; else, models.Value = names{1}; end
        invalidate();
    end

    function invalidate(varargin)
        preview = [];
        applyButton.Enable = 'off';
        results.Data = cell(0, 7);
        fig.UserData = struct('Report', [], 'LastError', [], 'Busy', isBusy());
        status.Value = {'Inputs changed. Run Preview before applying.'};
    end

    function options = backendOptions(mode)
        options = struct('Mode', mode, 'CalibrationConfig', calibration.Value);
    end

    function modelName = chosenModel()
        modelName = models.Value;
        if ~bdIsLoaded(modelName)
            error('AutosarMapping:Model', 'Choose or load an AUTOSAR Classic model first.');
        end
    end

    function runPreview(~, ~)
        if isBusy(), return; end
        beginOperation('Reading model and configuration...');
        finish = onCleanup(@() local_endOperation(fig, controls, applyButton));
        try
            report = configureAutosarMapping(chosenModel(), csv.Value, backendOptions('preview'));
            preview = report;
            showReport(report);
        catch cause
            showError(cause);
        end
    end

    function runApply(~, ~)
        if isBusy() || isempty(preview), return; end
        beginOperation('Checking preview and applying mappings...');
        finish = onCleanup(@() local_endOperation(fig, controls, applyButton));
        try
            options = backendOptions('apply');
            options.ExpectedSnapshot = preview.Snapshot;
            report = configureAutosarMapping(chosenModel(), csv.Value, options);
            preview = [];
            showReport(report);
        catch cause
            showError(cause);
        end
    end

    function showReport(report)
        results.Data = cellstr(report.Elements{:,:});
        fig.UserData = struct('Report', report, 'LastError', [], 'Busy', isBusy());
        detail = 'Changes are in memory only. Save the model explicitly in Simulink after review.';
        if isempty(report.CalibrationMatches) && report.CalibrationConfig ~= ""
            detail = 'No calibration names matched. Check global IncludePatterns/ExcludePatterns; empty includes match nothing.';
        end
        status.Value = {sprintf('%s: %d changes, %d applied. Calibration names matched: %d. Optional rules skipped: %d.', ...
            report.Mode, report.Changed, report.Applied, height(report.CalibrationMatches), ...
            height(report.SkippedRules)), detail};
    end

    function showError(cause)
        preview = [];
        results.Data = cell(0, 7);
        fig.UserData = struct('Report', [], 'LastError', cause, 'Busy', isBusy());
        messages = {sprintf('%s: %s', cause.identifier, cause.message)};
        for k = 1:numel(cause.cause), messages{end + 1} = cause.cause{k}.message; end %#ok<AGROW>
        status.Value = messages;
    end

    function beginOperation(message)
        state = fig.UserData;
        state.Busy = true;
        fig.UserData = state;
        for k = 1:numel(controls), controls{k}.Enable = 'off'; end
        status.Value = {message};
        drawnow;
    end

    function value = isBusy()
        value = fig.UserData.Busy;
    end

    function browseFile(field, filter)
        if isBusy(), return; end
        restoreFocus = onCleanup(@() refocus(field));
        [name, folder] = uigetfile(filter);
        if isequal(name, 0), return; end
        field.Value = fullfile(folder, name);
        invalidate();
    end

    function refocus(target)
        if ~isvalid(fig) || ~isvalid(target) || strcmp(fig.Visible, 'off'), return; end
        drawnow;
        if isvalid(fig) && isvalid(target) && strcmp(fig.Visible, 'on') && ...
                strcmp(target.Enable, 'on')
            focus(target);
        end
    end

    function editFile(field)
        if isBusy(), return; end
        try
            filename = field.Value;
            if ~isfile(filename), filename = which(filename); end
            if isempty(filename) || ~isfile(filename), error('AutosarMapping:ConfigFile', 'Select an existing configuration file.'); end
            edit(filename);
            invalidate();
        catch cause
            showError(cause);
        end
    end

    function loadSelectedModel(~, ~)
        if isBusy(), return; end
        restoreFocus = onCleanup(@() refocus(loadModel));
        [name, folder] = uigetfile({'*.slx;*.mdl', 'Simulink models'});
        if isequal(name, 0), return; end
        beginOperation('Loading model...');
        finish = onCleanup(@() local_endOperation(fig, controls, applyButton));
        try
            load_system(fullfile(folder, name));
            [~, selected] = fileparts(name);
            % Refresh is blocked while busy; populate once after releasing it.
            clear finish;
            refreshModels();
        catch cause
            showError(cause);
        end
    end

    function exportCsv(~, ~)
        if isBusy(), return; end
        restoreFocus = onCleanup(@() refocus(csv));
        [name, folder] = uiputfile('*.csv', 'Export to a new CSV file');
        if isequal(name, 0), return; end
        beginOperation('Exporting native Code Mapping settings...');
        finish = onCleanup(@() local_endOperation(fig, controls, applyButton));
        try
            filename = fullfile(folder, name);
            exportAutosarMapping(chosenModel(), filename);
            csv.Value = filename;
            invalidate();
            status.Value = {'CSV exported. Edit the file, then run Preview.'};
        catch cause
            showError(cause);
        end
    end

    function closeWindow(~, ~)
        if isBusy(), return; end
        delete(fig);
    end
end

function local_endOperation(fig, controls, applyButton)
    if ~isvalid(fig), return; end
    for k = 1:numel(controls), controls{k}.Enable = 'on'; end
    state = fig.UserData;
    if isempty(state.Report) || state.Report.Mode ~= "preview" || state.Report.Changed == 0
        applyButton.Enable = 'off';
    end
    state.Busy = false;
    fig.UserData = state;
end
