function testAutosarCalibrationAndGui(screenshotFile)
%TESTAUTOSARCALIBRATIONANDGUI Native global regexp and GUI regression tests.
%   Optional screenshotFile exports the rendered GUI before closing fixtures.
    if nargin == 0, screenshotFile = ''; end
    oldPath = path;
    restorePath = onCleanup(@() path(oldPath));
    repo = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repo, 'tools', 'autosar_mapping'));
    sandbox = tempname;
    mkdir(sandbox);
    removeSandbox = onCleanup(@() rmdir(sandbox, 's'));
    [~, model] = fileparts(tempname);
    [~, second] = fileparts(tempname);
    new_system(model);
    closeModel = onCleanup(@() close_system(model, 0));
    local_fixture(model);
    new_system(second);
    closeSecond = onCleanup(@() close_system(second, 0));
    local_fixture(second);
    baseline = exportAutosarMapping(model);
    config = readAutosarCalibrationConfig('');
    config = rmfield(config, 'File');
    config.Enabled = true;
    config.IncludePatterns = "^Cal_";
    config.ExcludePatterns = "Excluded";
    filename = fullfile(sandbox, 'global_calibration.json');
    local_json(filename, config);
    options = struct('CalibrationConfig', filename);
    disabled = struct('Mode', 'apply', 'CalibrationConfig', '');
    save_system(model, fullfile(sandbox, [model '.slx']));
    fileBefore = local_bytes(fullfile(sandbox, [model '.slx']));
    preview = configureAutosarMapping(model, [], options);
    assert(height(preview.CalibrationMatches) == 3 && preview.Changed == 5);
    assert(all(contains(preview.Elements.Reason, 'Global calibration regexp')));
    assert(strcmp(get_param(model, 'Dirty'), 'off') && isequal(baseline, exportAutosarMapping(model)));
    another = configureAutosarMapping(second, [], options);
    assert(isequal(another.CalibrationMatches, preview.CalibrationMatches));
    assert(configureAutosarMapping(model, [], struct('CalibrationConfig', '')).Changed == 0);
    local_configErrors(filename, config, model, baseline);

    % Explicit CSV fields override global defaults; calibration:* selects
    % names even while their current roles are still Auto.
    rules = table(repmat(string(model), 2, 1), repmat("ModelParameters", 2, 1), ...
        ["calibration:*"; "Cal_Speed"], ["SwAddrMethod"; "SwCalibrationAccess"], ...
        ["CONST"; "ReadOnly"], 'VariableNames', {'Model', 'Category', 'Element', 'Property', 'Value'});
    csv = fullfile(sandbox, 'model_mapping.csv');
    writetable(rules, csv);
    report = configureAutosarMapping(model, csv, options);
    matching = report.Elements.Element == "Cal_Speed" & report.Elements.Property == "SwCalibrationAccess";
    assert(report.Elements.Desired(matching) == "ReadOnly" && report.Elements.Reason(matching) == "");
    apply = options;
    apply.Mode = 'apply';
    apply.ExpectedSnapshot = report.Snapshot;
    applied = configureAutosarMapping(model, csv, apply);
    assert(applied.Applied == report.Changed && applied.Compliant);
    mapping = autosar.api.getSimulinkMapping(model);
    assert(strcmp(mapping.getParameter('Cal_Speed'), 'SharedParameter'));
    assert(strcmp(mapping.getParameter('Cal_Speed', 'SwCalibrationAccess'), 'ReadOnly'));
    assert(strcmp(mapping.getParameter('Cal_Existing'), 'ConstantMemory'));
    assert(strcmp(mapping.getParameter('Cal_Arg'), 'PerInstanceParameter'));
    assert(strcmp(mapping.getParameter('Cal_Excluded'), 'Auto') && strcmp(mapping.getParameter('Normal'), 'Auto'));
    assert(isequal(fileBefore, local_bytes(fullfile(sandbox, [model '.slx']))));
    assert(configureAutosarMapping(model, csv, struct('Mode', 'apply', 'CalibrationConfig', filename)).Applied == 0);
    local_restore(model, baseline, disabled);

    config.IgnoreCase = true;
    local_json(filename, config);
    insensitive = configureAutosarMapping(model, [], options);
    assert(height(insensitive.CalibrationMatches) == 4);
    config.IgnoreCase = false;
    config.PreserveExplicitMappings = false;
    local_json(filename, config);
    enforced = configureAutosarMapping(model, [], options);
    row = enforced.Elements.Element == "Cal_Existing" & enforced.Elements.Property == "MappedTo";
    assert(enforced.Elements.Desired(row) == "SharedParameter");
    config.PreserveExplicitMappings = true;
    local_json(filename, config);
    optOut = rules(2, :);
    optOut.Property = "MappedTo";
    optOut.Value = "Auto";
    keepAuto = configureAutosarMapping(model, optOut, options);
    rows = keepAuto.Elements.Element == "Cal_Speed";
    assert(sum(rows) == 1 && keepAuto.Elements.Desired(rows) == "Auto");

    unchangedRule = rules(1, :);
    unchangedRule.Element = "Cal_Existing";
    unchangedRule.Property = "MappedTo";
    unchangedRule.Value = "ConstantMemory";
    writetable([rules; unchangedRule], csv);
    fig = autosarMappingGui(model, struct('Source', csv, 'CalibrationConfig', filename, 'Visible', 'off'));
    closeGui = onCleanup(@() delete(fig));
    previewButton = findall(fig, 'Tag', 'AutosarMappingPreview');
    applyButton = findall(fig, 'Tag', 'AutosarMappingApply');
    results = findall(fig, 'Tag', 'AutosarMappingResults');
    assert(strcmp(applyButton.Enable, 'off'));
    local_click(previewButton);
    guiPreview = fig.UserData.Report;
    if ~isempty(fig.UserData.LastError), rethrow(fig.UserData.LastError); end
    assert(isempty(fig.UserData.LastError) && ~fig.UserData.Busy);
    assert(isequal(guiPreview.Elements, configureAutosarMapping(model, csv, options).Elements));
    assert(strcmp(applyButton.Enable, 'on') && size(results.Data, 1) == height(guiPreview.Elements));
    assert(isequal(results.Data, cellstr(guiPreview.Elements{:,:})));
    assert(any(guiPreview.Elements.Status == "Change") && any(guiPreview.Elements.Status == "Unchanged"));
    assert(all(guiPreview.Elements.Status(1:guiPreview.Changed) == "Change"));
    assert(all(guiPreview.Elements.Status(guiPreview.Changed + 1:end) == "Unchanged"));
    config.IgnoreCase = true;
    local_json(filename, config);
    local_click(applyButton);
    assert(strcmp(fig.UserData.LastError.identifier, 'AutosarMapping:StalePreview'));
    assert(isequal(baseline, exportAutosarMapping(model)) && strcmp(applyButton.Enable, 'off'));
    config.IgnoreCase = false;
    local_json(filename, config);
    local_click(previewButton);
    rules.Value(2) = "ReadWrite";
    writetable(rules, csv);
    local_click(applyButton);
    assert(strcmp(fig.UserData.LastError.identifier, 'AutosarMapping:StalePreview'));
    local_click(previewButton);
    mapping.mapParameter('Normal', 'SharedParameter');
    changedModel = exportAutosarMapping(model);
    local_click(applyButton);
    assert(strcmp(fig.UserData.LastError.identifier, 'AutosarMapping:StalePreview'));
    assert(isequal(changedModel, exportAutosarMapping(model)));
    local_restore(model, baseline, disabled);
    local_click(previewButton);
    if ~isempty(screenshotFile)
        fig.Visible = 'on';
        drawnow;
        exportapp(fig, screenshotFile);
        fig.Visible = 'off';
    end
    local_click(applyButton);
    assert(isempty(fig.UserData.LastError) && fig.UserData.Report.Applied > 0 && strcmp(applyButton.Enable, 'off'));
    assert(isequal(fileBefore, local_bytes(fullfile(sandbox, [model '.slx']))));
    source = findall(fig, 'Tag', 'AutosarMappingSource');
    models = findall(fig, 'Tag', 'AutosarMappingModel');
    source.Value = '';
    source.ValueChangedFcn(source, []);
    models.Value = second;
    models.ValueChangedFcn(models, []);
    assert(isempty(fig.UserData.Report) && strcmp(applyButton.Enable, 'off'));
    local_click(previewButton);
    assert(fig.UserData.Report.Model == string(second) && height(fig.UserData.Report.CalibrationMatches) == 3);
    fprintf('PASS: global calibration regexp, include/exclude/case, model isolation, overrides, CLI/GUI, stale model/CSV/JSON rejection, no-save.\n');
end

function local_fixture(model)
    set_param(model, 'SystemTargetFile', 'autosar.tlc', 'Solver', 'FixedStepDiscrete', 'FixedStep', '0.1');
    workspace = get_param(model, 'ModelWorkspace');
    add_block('simulink/Sources/Constant', [model '/Input']);
    previous = 'Input';
    names = {'Cal_Speed', 'cal_Lower', 'Cal_Excluded', 'Normal', 'Cal_Existing', 'Cal_Arg'};
    for k = 1:numel(names)
        name = names{k};
        assignin(workspace, name, Simulink.Parameter(1));
        add_block('simulink/Math Operations/Gain', [model '/' name], 'Gain', name);
        add_line(model, [previous '/1'], [name '/1']);
        previous = name;
    end
    add_block('simulink/Sinks/Terminator', [model '/End']);
    add_line(model, [previous '/1'], 'End/1');
    set_param(model, 'ParameterArgumentNames', 'Cal_Arg');
    autosar.api.create(model, 'default');
    mapping = autosar.api.getSimulinkMapping(model);
    mapping.mapParameter('Cal_Existing', 'ConstantMemory', 'SwCalibrationAccess', 'ReadOnly');
end

function local_configErrors(filename, config, model, before)
    bad = config;
    bad.IncludePatterns = "[";
    local_json(filename, bad);
    local_error(@() configureAutosarMapping(model, [], struct('CalibrationConfig', filename)), 'AutosarMapping:CalibrationRegexp');
    bad.IncludePatterns = "(?@error('Test:ShouldNotExecute'))";
    local_json(filename, bad);
    local_error(@() readAutosarCalibrationConfig(filename), 'AutosarMapping:CalibrationRegexp');
    bad = config;
    bad.IgnoreCase = 1;
    local_json(filename, bad);
    local_error(@() readAutosarCalibrationConfig(filename), 'AutosarMapping:CalibrationConfig');
    bad = config;
    bad.Model = "NotGlobal";
    local_json(filename, bad);
    local_error(@() readAutosarCalibrationConfig(filename), 'AutosarMapping:CalibrationConfig');
    bad = config;
    bad.IncludePatterns = strings(1, 0);
    local_json(filename, bad);
    assert(configureAutosarMapping(model, [], struct('CalibrationConfig', filename)).Changed == 0);
    local_json(filename, config);
    assert(isequal(before, exportAutosarMapping(model)));
end

function local_restore(model, rules, options)
    restored = configureAutosarMapping(model, rules, options);
    assert(restored.Compliant);
    set_param(model, 'Dirty', 'off');
end

function local_json(filename, config)
    fid = fopen(filename, 'w', 'n', 'UTF-8');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(config, 'PrettyPrint', true));
end

function local_click(button)
    button.ButtonPushedFcn(button, []);
    drawnow;
end

function bytes = local_bytes(filename)
    fid = fopen(filename, 'rb');
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
end

function local_error(action, identifier)
    try
        action();
    catch cause
        if ~strcmp(cause.identifier, identifier), rethrow(cause); end
        return;
    end
    error('Test:MissingError', 'Expected %s.', identifier);
end
