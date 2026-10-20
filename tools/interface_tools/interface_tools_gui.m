function fig = interface_tools_gui(opts)
%INTERFACE_TOOLS_GUI Preview/sync interfaces and generate parameter M-files.
% Version: 1.9.0 (Interface tools bundle).
%   interface_tools_gui
%   fig = interface_tools_gui(struct('ConfigFile', 'my_config.json'))
%
% Defaults are read from interface_tools_config.json beside this file.
% SourceXlsx is relative to the config folder; output paths are relative to
% ProjectRoot (or absolute). Empty ProjectRoot enables project discovery.
% Sheets affect SLDD only; parameter generation always processes ALL sheets.
% Preview lists every ADD/REMOVE/PROPERTY_DIFF as bus.element in a table.
% Tick individual ADD/REMOVE rows, then Apply selected. Preview is required.
% Property differences and referenced interfaces cannot be selected.
% Only buses named in selected Excel sheets are compared.
% REMOVE requires Status=remove in Excel; elements absent from Excel are kept.
%
% Requires MATLAB/Simulink R2024a+ and the two adjacent backend M-files.
% SLDD operations read Data Interfaces directly from Architectural Data.
% No exporter or intermediate workbook is needed.
% Activity log streams backend progress and retains all session messages.
% New messages appear first. Disable Follow latest to pause the view.

    if nargin < 1, opts = struct(); end
    validateattributes(opts, {'struct'}, {'scalar'});
    toolFolder = fileparts(mfilename('fullpath'));
    configFile = fullfile(toolFolder, 'interface_tools_config.json');
    if isfield(opts, 'ConfigFile'), configFile = char(opts.ConfigFile); end
    config = local_readConfig(configFile);
    addpath(toolFolder);

    projectRoot = '';
    slddFile = '';
    parametersFile = '';
    knownSheets = strings(1, 0);
    previewReport = [];
    logLines = {'Ready. Choose an Excel workbook.'};
    logClock = tic;
    screen = get(groot, 'ScreenSize');
    windowSize = [min(1180, screen(3)-80), min(920, screen(4)-100)];

    fig = uifigure('Name', 'CVC Interface Tools', ...
        'Position', [40 40 windowSize], 'Color', [0.97 0.98 0.99]);
    layout = uigridlayout(fig, [6 1], 'RowHeight', {28, 72, 320, 28, '1x', 180}, ...
        'Padding', [16 12 16 12], 'RowSpacing', 8, 'Scrollable', 'on');
    uilabel(layout, 'Text', 'CVC Interface Tools', 'FontSize', 20, 'FontWeight', 'bold');
    sourceGrid = uigridlayout(layout, [2 3], 'RowHeight', {30, 22}, ...
        'ColumnWidth', {90, '1x', 90}, 'Padding', [0 0 0 0]);
    uilabel(sourceGrid, 'Text', 'Source XLSX', 'FontWeight', 'bold');
    excelEdit = uieditfield(sourceGrid, 'text', 'Tag', 'SourceXlsx', ...
        'Placeholder', 'Select the Excel interface file...', ...
        'ValueChangedFcn', @(~, ~) loadExcel());
    browseButton = uibutton(sourceGrid, 'push', 'Text', 'Browse...', ...
        'ButtonPushedFcn', @(~, ~) browseExcel());
    uilabel(sourceGrid, 'Text', 'Project', 'FontWeight', 'bold');
    projectLabel = uilabel(sourceGrid, 'Text', 'Automatic project discovery', ...
        'Interpreter', 'none');
    projectLabel.Layout.Column = [2 3];

    sections = uigridlayout(layout, [1 2], 'ColumnWidth', {'1x', '2x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 12);
    parameterPanel = uipanel(sections, 'Title', 'Parameter M-file', 'FontWeight', 'bold');
    pg = uigridlayout(parameterPanel, [5 1], ...
        'RowHeight', {20, 44, 24, 32, '1x'}, 'Padding', [12 10 12 10]);
    uilabel(pg, 'Text', 'Output file', 'FontWeight', 'bold');
    parametersLabel = uilabel(pg, 'Text', config.ParametersFile, ...
        'WordWrap', 'on', 'Interpreter', 'none');
    uilabel(pg, 'Text', 'Always processes ALL parameter sheets.');
    parameterButton = uibutton(pg, 'push', ...
        'Text', 'Generate Parameters', 'Tag', 'GenerateParameters', ...
        'ButtonPushedFcn', @(~, ~) runTasks('parameters'));

    slddPanel = uipanel(sections, 'Title', 'SLDD interfaces', 'FontWeight', 'bold');
    sg = uigridlayout(slddPanel, [5 2], ...
        'RowHeight', {36, 22, '1x', 28, 32}, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [12 8 12 8], 'RowSpacing', 4);
    slddLabel = uilabel(sg, 'Text', config.SlddFile, ...
        'WordWrap', 'on', 'Interpreter', 'none');
    slddLabel.Layout.Column = [1 2];
    sheetCountLabel = uilabel(sg, 'Text', 'Models / sheets: no workbook loaded');
    sheetCountLabel.Layout.Column = [1 2];
    sheetList = uilistbox(sg, 'Tag', 'SyncSheets', ...
        'Items', {}, 'Value', {}, 'Multiselect', 'on', ...
        'ValueChangedFcn', @(~, ~) updateSelectionCount(), ...
        'Tooltip', 'Use Ctrl or Shift to select multiple models.');
    sheetList.Layout.Column = [1 2];
    selectionGrid = uigridlayout(sg, [1 2], 'RowHeight', {28}, 'Padding', [0 0 0 0]);
    selectionGrid.Layout.Column = [1 2];
    selectButton = uibutton(selectionGrid, 'Text', 'Select all', ...
        'ButtonPushedFcn', @(~, ~) selectAllSheets());
    clearButton = uibutton(selectionGrid, 'Text', 'Clear selection', ...
        'ButtonPushedFcn', @(~, ~) clearSheets());
    previewButton = uibutton(sg, 'push', 'Text', 'Preview differences', 'Tag', 'PreviewSldd', ...
        'ButtonPushedFcn', @(~, ~) runTasks('preview'));
    syncButton = uibutton(sg, 'push', 'Text', 'Apply selected (0)', 'Tag', 'SyncSldd', 'Enable', 'off', ...
        'ButtonPushedFcn', @(~, ~) runTasks('sync'));
    actionButtons = [previewButton, syncButton, parameterButton];
    inputControls = [excelEdit, browseButton, sheetList, selectButton, clearButton];

    detailHeader = uigridlayout(layout, [1 3], ...
        'ColumnWidth', {'1x', 130, 110}, 'Padding', [0 0 0 0]);
    detailLabel = uilabel(detailHeader, 'Text', 'Run Preview, then tick changes to apply.', ...
        'FontWeight', 'bold');
    selectChangesButton = uibutton(detailHeader, 'Text', 'Select all changes', 'Tag', 'SelectChanges', ...
        'ButtonPushedFcn', @(~, ~) selectChanges(true));
    clearChangesButton = uibutton(detailHeader, 'Text', 'Clear changes', 'Tag', 'ClearChanges', ...
        'ButtonPushedFcn', @(~, ~) selectChanges(false));
    detailTable = uitable(layout, 'Tag', 'InterfaceDifferences', ...
        'Data', cell(0, 6), 'ColumnName', {'Apply', 'Action', 'Bus.Element', 'Property', 'XLSX', 'SLDD'}, ...
        'ColumnFormat', {'logical', 'char', 'char', 'char', 'char', 'char'}, ...
        'ColumnWidth', {50, 110, 190, 90, 330, 330}, 'RowName', {}, ...
        'ColumnEditable', [true false false false false false], ...
        'CellEditCallback', @(~, event) editChange(event));
    inputControls = [inputControls, selectChangesButton, clearChangesButton, detailTable];
    logPanel = uipanel(layout, 'Title', 'Activity log', 'FontWeight', 'bold');
    logGrid = uigridlayout(logPanel, [2 1], 'RowHeight', {22, '1x'}, ...
        'Padding', [8 6 8 6], 'RowSpacing', 4);
    logHeader = uigridlayout(logGrid, [1 2], 'ColumnWidth', {'1x', 190}, 'Padding', [0 0 0 0]);
    logState = uilabel(logHeader, 'Text', 'Ready', 'Tag', 'ActivityStatus');
    followLog = uicheckbox(logHeader, 'Text', 'Follow latest (newest first)', 'Value', true, 'Tag', 'FollowLog', ...
        'ValueChangedFcn', @(~, ~) flushLog());
    logArea = uitextarea(logGrid, 'Editable', 'off', 'Value', logLines, ...
        'Tag', 'ActivityLog', 'FontName', 'Consolas', 'WordWrap', 'on');
    if ~isempty(config.SourceXlsx)
        excelEdit.Value = config.SourceXlsx;
        loadExcel();
    end

    % ------------------------------------------------------------
    % Select source XLSX / discover project
    % ------------------------------------------------------------
    function browseExcel()
        [filename, folder] = uigetfile( ...
            {'*.xlsx;*.xlsm', 'Excel workbooks (*.xlsx, *.xlsm)'}, ...
            'Select interface XLSX');
        if isequal(filename, 0), return; end
        excelEdit.Value = fullfile(folder, filename);
        loadExcel();
    end

    function loadExcel()
        source = strtrim(excelEdit.Value);
        projectRoot = '';
        slddFile = '';
        parametersFile = '';
        knownSheets = strings(1, 0);
        sheetList.Items = {};
        sheetList.Value = {};
        projectLabel.Text = 'Automatic project discovery';
        slddLabel.Text = config.SlddFile;
        parametersLabel.Text = config.ParametersFile;
        resetPreview();
        detailLabel.Text = 'SLDD differences: run Preview to compare.';
        sheetCountLabel.Text = 'No sheets loaded';
        if isempty(source), return; end
        if ~isfile(source)
            appendLog('XLSX file does not exist: ' + string(source));
            return;
        end

        % Normalize relative XLSX paths before calling the backends.
        [resolved, info] = fileattrib(source);
        if resolved
            source = info.Name;
            excelEdit.Value = source;
        end

        try
            if isempty(config.ProjectRoot)
                projectRoot = findProjectRoot(source, toolFolder, config);
            else
                projectRoot = config.ProjectRoot;
                if ~isfolder(projectRoot)
                    error('Configured ProjectRoot does not exist: %s', projectRoot);
                end
            end
            parametersFile = local_resolvePath(config.ParametersFile, projectRoot);
            slddFile = findProjectSldd(projectRoot, config.SlddFile);

            projectLabel.Text = projectRoot;
            if isempty(slddFile)
                slddLabel.Text = ['NOT FOUND: ' config.SlddFile];
                slddLabel.FontColor = [0.75 0.20 0.18];
                appendLog('SLDD not found/ambiguous. Parameter generation is still available.');
            else
                slddLabel.Text = slddFile;
                slddLabel.FontColor = [0.37 0.40 0.45];
            end
            projectLabel.Tooltip = projectRoot;
            slddLabel.Tooltip = local_resolvePath(config.SlddFile, projectRoot);
            parametersLabel.Text = parametersFile;
            parametersLabel.Tooltip = parametersFile;
            appendLog('Source XLSX: ' + string(source));
            appendLog('SLDD: ' + string(slddFile));
            appendLog('Project: ' + string(projectRoot));

            sheets = string(sheetnames(source));
            for k = 1:numel(sheets)
                try
                    header = readcell(source, 'Sheet', char(sheets(k)), ...
                        'Range', 'A1:AZ40');
                    if isInterfaceSheet(header)
                        knownSheets(end+1) = sheets(k); %#ok<AGROW>
                    end
                catch ME
                    appendLog(sprintf('Ignoring sheet %s: %s', sheets(k), ME.message));
                end
            end
            sheetList.Items = cellstr(knownSheets);
            sheetList.Value = sheetList.Items;
            updateSelectionCount();
            appendLog(sprintf('Loaded %d interface sheet(s). Generate processes ALL sheets.', ...
                numel(knownSheets)));
        catch ME
            appendLog('Error loading XLSX/project: ' + string(ME.message));
            uialert(fig, ME.message, 'Failed to load XLSX', 'Icon', 'error');
        end
    end

    function tf = isInterfaceSheet(cells)
        tf = false;
        for r = 1:size(cells, 1)
            headers = strings(1, size(cells, 2));
            for c = 1:size(cells, 2)
                v = cells{r, c};
                if ischar(v) || (isstring(v) && isscalar(v) && ~ismissing(v))
                    headers(c) = lower(regexprep(strtrim(string(v)), '[^a-zA-Z0-9]', ''));
                end
            end
            if any(headers == "bus") && any(headers == "element")
                tf = true;
                return;
            end
        end
    end

    function selectAllSheets()
        sheetList.Value = sheetList.Items;
        updateSelectionCount();
    end

    function clearSheets()
        sheetList.Value = {};
        updateSelectionCount();
    end

    function updateSelectionCount()
        sheetCountLabel.Text = sprintf('%d / %d model(s) selected for SLDD sync', ...
            numel(sheetList.Value), numel(knownSheets));
        resetPreview();
        detailLabel.Text = 'SLDD differences: selection changed. Run Preview to compare.';
    end

    % ------------------------------------------------------------
    % Run existing tools
    % ------------------------------------------------------------
    function runTasks(task)
        source = strtrim(excelEdit.Value);
        doSync = ismember(task, {'preview', 'sync'});
        doParams = strcmp(task, 'parameters');
        doApply = strcmp(task, 'sync');
        selected = string(sheetList.Value);
        selected = selected(:).';

        if ~isfile(source)
            uialert(fig, 'Select a valid XLSX first.', 'Missing XLSX');
            return;
        end
        if isempty(projectRoot) || isempty(parametersFile)
            uialert(fig, 'Project root is unresolved. Check ProjectRoot in the config.', ...
                'Project not found');
            return;
        end
        if doSync
            if isempty(selected)
                uialert(fig, 'Select at least one model/sheet to sync.', 'No model');
                return;
            end
            if isempty(slddFile) || ~isfile(slddFile)
                uialert(fig, 'Cannot find exactly one SLDD in the project.', ...
                    'SLDD not found');
                return;
            end
        end
        if doParams && ~isfolder(fileparts(parametersFile))
            uialert(fig, sprintf('Parameter output folder does not exist:\n%s', fileparts(parametersFile)), ...
                'Missing target folder');
            return;
        end
        if doApply
            if isempty(previewReport)
                appendLog('Run Preview and tick ADD/REMOVE rows before applying.');
                return;
            end
            chosen = cell2mat(detailTable.Data(:, 1));
            chosen = chosen & previewReport.Selectable;
            if ~any(chosen)
                appendLog('No editable changes selected.');
                return;
            end
            applyOptions = struct('Mode', 'apply', ...
                'SelectedChanges', previewReport.Changes(chosen, :), ...
                'ExpectedSnapshot', {previewReport.Snapshot}, ...
                'LogFcn', @(message) appendLog(message, false));
        end
        if doParams && isfile(parametersFile)
            choice = uiconfirm(fig, ...
                sprintf('Parameter file already exists and will be overwritten:\n%s', parametersFile), ...
                'Confirm overwrite', 'Icon', 'warning', ...
                'Options', {'Overwrite', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(choice, 'Overwrite'), return; end
        end

        enableActions('off');
        restoreButtons = onCleanup(@() enableActions('on'));
        try
            if doSync
                appendLog(sprintf('%s: %d model(s): %s', upper(task), numel(selected), strjoin(selected, ', ')));
                requested = selected;
                if numel(selected) == numel(knownSheets), requested = 'all'; end
                if doApply
                    appendLog(sprintf('Applying %d selected element changes ...', sum(chosen)));
                    summary = sync_bus_interfaces_from_excel(source, slddFile, requested, applyOptions);
                    appendLog(sprintf('Applied: ADD=%d REMOVE=%d SAVED=%d', ...
                        summary.Added, summary.Removed, summary.Saved));
                end
                resetPreview();
                detailLabel.Text = 'Comparing Excel buses with SLDD ...';
                drawnow;
                previewOptions = struct('Mode', 'preview', 'LogFcn', @(message) appendLog(message, false));
                previewReport = sync_bus_interfaces_from_excel(source, slddFile, requested, previewOptions);
                detailTable.Data = [num2cell(false(height(previewReport.Changes), 1)), ...
                    table2cell(previewReport.Changes)];
                detailLabel.Text = sprintf('%d ADD, %d REMOVE, %d PROPERTY_DIFF (report only)', ...
                    previewReport.ToAdd, previewReport.ToRemove, previewReport.MetadataMismatch);
                updateApplyState();
                appendLog(sprintf('Preview: %d ADD, %d REMOVE, %d PROPERTY_DIFF; %d editable changes.', ...
                    previewReport.ToAdd, previewReport.ToRemove, previewReport.MetadataMismatch, ...
                    sum(previewReport.Selectable)));
                appendLog('REMOVE requires Status=remove in Excel; missing elements are kept.');
                appendLog(sprintf('%d matching Data Interfaces; tick local ADD/REMOVE rows to apply.', ...
                    height(previewReport.Interfaces)));
            end
            if doParams
                appendLog('Generating ALL parameter sheets ...');
                drawnow;
                parameterOptions = struct('LogFcn', @(message) appendLog(message, false));
                generate_simulink_parameters(source, parametersFile, 'all', parameterOptions);
                appendLog('Generated: ' + string(parametersFile));
            end
            appendLog('Finished successfully.');
        catch ME
            if doSync
                resetPreview();
                detailLabel.Text = 'Run Preview again. See activity log.';
            end
            appendLog(getReport(ME, 'extended', 'hyperlinks', 'off'));
            appendLog('ERROR: ' + string(ME.message));
            fprintf(2, '\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            uialert(fig, ME.message, 'Tool failed', 'Icon', 'error');
        end
    end

    function enableActions(state)
        if ~isvalid(fig), return; end
        controls = [actionButtons, inputControls];
        for k = 1:numel(controls)
            controls(k).Enable = state;
        end
        if strcmp(state, 'on'), updateApplyState(); end
    end

    function resetPreview()
        previewReport = [];
        detailTable.Data = cell(0, 6);
        syncButton.Enable = 'off';
        syncButton.Text = 'Apply selected (0)';
    end

    function editChange(event)
        if isempty(previewReport), return; end
        row = event.Indices(1);
        if event.Indices(2) ~= 1, return; end
        detailTable.Data{row, 1} = logical(event.NewData) && previewReport.Selectable(row);
        updateApplyState();
    end

    function selectChanges(selected)
        if isempty(previewReport), return; end
        detailTable.Data(:, 1) = num2cell(previewReport.Selectable & selected);
        updateApplyState();
    end

    function updateApplyState()
        count = 0;
        if ~isempty(previewReport)
            chosen = cell2mat(detailTable.Data(:, 1));
            count = sum(chosen & previewReport.Selectable);
        end
        syncButton.Text = sprintf('Apply selected (%d)', count);
        syncButton.Enable = 'off';
        if count > 0, syncButton.Enable = 'on'; end
    end

    function appendLog(message, echo)
        if ~isvalid(fig), return; end
        if nargin < 2, echo = true; end
        message = char(string(message));
        lines = regexp(strtrim(message), '\r\n|\n|\r', 'split');
        stamp = char(datetime('now', 'Format', 'HH:mm:ss'));
        entries = cell(numel(lines), 1);
        for k = 1:numel(lines)
            entries{k} = sprintf('[%s] %s', stamp, lines{k});
        end
        logLines{end+1, 1} = strjoin(entries, newline);
        logState.Text = lines{end};
        logState.Tooltip = message;
        if echo || toc(logClock) >= 0.1, flushLog(); end
        if echo, fprintf('[GUI] %s\n', message); end
    end

    function flushLog()
        if ~isvalid(fig) || ~followLog.Value, return; end
        logArea.Value = flipud(logLines);
        drawnow;
        scroll(logArea, 'top');
        logClock = tic;
    end

end

function projectRoot = findProjectRoot(xlsxFile, guiFolder, config)
% Search parent folders from XLSX first, then GUI script, then MATLAB pwd.
% Also supports MATLAB started in the folder immediately ABOVE EBUS_12M.
    seeds = {fileparts(char(xlsxFile)), guiFolder, pwd};
    for i = 1:numel(seeds)
        folder = seeds{i};
        while ~isempty(folder)
            [~, name] = fileparts(folder);
            candidates = {};
            if strcmpi(name, config.ProjectFolderName)
                candidates{end+1} = folder; %#ok<AGROW>
            end
            if isfolder(fullfile(folder, config.ArchitectureFolder))
                candidates{end+1} = folder; %#ok<AGROW>
            end
            candidates{end+1} = fullfile(folder, config.ProjectFolderName); %#ok<AGROW>
            for k = 1:numel(candidates)
                p = candidates{k};
                if isfolder(fullfile(p, config.ArchitectureFolder))
                    projectRoot = p;
                    return;
                end
            end
            parent = fileparts(folder);
            if strcmp(parent, folder), break; end
            folder = parent;
        end
    end
    error('Could not locate project root. Set ProjectRoot in the config or place XLSX inside the project.');
end

function slddFile = findProjectSldd(projectRoot, configuredFile)
% Prefer fixed default; otherwise accept ONLY one project-local SLDD.
    defaultFile = local_resolvePath(configuredFile, projectRoot);
    if isfile(defaultFile)
        slddFile = defaultFile;
        return;
    end

    matches = dir(fullfile(projectRoot, '**', '*.sldd'));
    matches = matches(~[matches.isdir]);
    if isscalar(matches)
        slddFile = fullfile(matches(1).folder, matches(1).name);
    else
        slddFile = '';
    end
end

function config = local_readConfig(configFile)
    if ~isfile(configFile)
        error('InterfaceTools:Config', 'Config file not found: %s', configFile);
    end
    [~, info] = fileattrib(configFile);
    configFolder = fileparts(info.Name);
    config = jsondecode(fileread(configFile));
    names = {'SourceXlsx', 'ProjectRoot', 'ProjectFolderName', 'ArchitectureFolder', ...
        'SlddFile', 'ParametersFile'};
    allowed = [names, {'ExportXlsx'}]; % Accept legacy configs; export path is unused.
    if ~isstruct(config) || ~isscalar(config) || ...
            ~all(isfield(config, names)) || ~all(ismember(fieldnames(config), allowed))
        error('InterfaceTools:Config', 'Config must contain exactly: %s.', strjoin(names, ', '));
    end
    for k = 1:numel(names)
        name = names{k};
        value = config.(name);
        if ~(ischar(value) && (isrow(value) || isempty(value)))
            error('InterfaceTools:Config', 'Config %s must be a text value.', name);
        end
        config.(name) = strtrim(value);
        if k > 2 && isempty(config.(name))
            error('InterfaceTools:Config', 'Config %s must not be empty.', name);
        end
    end
    if ~isempty(config.ProjectRoot)
        config.ProjectRoot = local_resolvePath(config.ProjectRoot, configFolder);
    end
    if ~isempty(config.SourceXlsx)
        config.SourceXlsx = local_resolvePath(config.SourceXlsx, configFolder);
    end
end

function path = local_resolvePath(path, root)
% Resolve relative paths without requiring the output file to exist.
    if ispc
        absolute = ~isempty(regexp(path, '^([A-Za-z]:[\\/]|\\\\)', 'once'));
    else
        absolute = startsWith(path, '/');
    end
    if ~absolute, path = fullfile(root, path); end
end
