function testInterfaceTools(scope)
%TESTINTERFACETOOLS Exercise interface tools using temporary synthetic data.
% Requires live MATLAB/Simulink R2024a+. No production files are read or edited.
% testInterfaceTools('review') runs only the review regression cases.
    if nargin < 1, scope = 'all'; end
    scope = validatestring(scope, {'all', 'review'});
    repo = fileparts(fileparts(mfilename('fullpath')));
    toolFolder = fullfile(repo, 'tools', 'interface_tools');
    previousPath = path;
    previousFolder = pwd;
    sandbox = tempname;
    mkdir(sandbox);
    restore = onCleanup(@() local_restore(previousPath, previousFolder, sandbox));
    addpath(toolFolder);
    addpath(sandbox, '-begin');
    cd(sandbox);
    mkdir('arch');
    if strcmp(scope, 'review')
        local_testReviewedRegressions(sandbox);
        return;
    end
    dictionary = fullfile(sandbox, 'arch', 'test.sldd');
    dd = Simulink.dictionary.archdata.create(dictionary);
    dictCleanup = onCleanup(@() local_close(dd));
    bus = addDataInterface(dd, 'BusA');
    source = {'Bus', 'Element', 'DataType', 'Dim', 'Status', 'Parameter', 'Value'};
    for k = 1:25
        name = sprintf('Keep%02d', k);
        elem = addElement(bus, name);
        elem.Type.DataType = 'uint8';
        elem.Dimensions = '1';
        source(end+1, :) = {'BusA', name, 'double', '1', 'Accept', sprintf('pA%02d', k), k}; %#ok<AGROW>
    end
    for k = 1:35
        source(end+1, :) = {'BusA', sprintf('New%02d', k), 'double', '1', '', '', ''}; %#ok<AGROW>
    end
    source(end+1, :) = {'BusA', 'Old', '', '', 'remove', '', ''};
    addElement(bus, 'Old');
    addElement(bus, 'Shared');
    other = addDataInterface(dd, 'BusB');
    addElement(other, 'Safe');
    save(dd);
    close(dd);
    writecell(source, 'source.xlsx', 'Sheet', 'ModelA');
    sourceB = [source(1, :); {'BusA', 'Shared', 'double', '1', 'Accept', 'pShared', 9}; ...
        {'BusB', 'Safe', 'double', '1', 'Accept', 'pSafe', 10}];
    writecell(sourceB, 'source.xlsx', 'Sheet', 'ModelB');
    local_write('sldd2excel_main.m', ...
        'error(''Exporter must never be called.'');');
    config = jsondecode(fileread(fullfile(toolFolder, 'interface_tools_config.json')));
    config.SourceXlsx = 'source.xlsx';
    config.ProjectRoot = ''; % Discover via the custom architecture marker.
    config.ArchitectureFolder = 'arch';
    config.SlddFile = 'arch/test.sldd';
    config.ParametersFile = 'arch/parameters.m';
    % Legacy config/path remains accepted but must never be touched.
    config.ExportXlsx = 'missing/export.xlsx';
    local_write('export.xlsx', 'legacy export sentinel');
    legacyExport = local_bytes('export.xlsx');
    configFile = fullfile(sandbox, 'config.json');
    local_write(configFile, jsonencode(config));
    before = local_bytes(dictionary);
    [console, summary] = evalc('sync_bus_interfaces_from_excel(''source.xlsx'', dictionary, ''ModelA'', ''export.xlsx'', ''preview'')');
    assert(summary.ToAdd == 35 && summary.ToRemove == 1 && summary.MetadataMismatch == 25);
    assert(height(summary.Changes) == 61 && ~summary.Saved);
    add = summary.Changes(strcmp(summary.Changes.Interface, 'BusA.New01'), :);
    removed = summary.Changes(strcmp(summary.Changes.Interface, 'BusA.Old'), :);
    assert(strcmp(add.Property{1}, 'element') && contains(add.SourceValue{1}, 'DataType=double'));
    assert(contains(add.SourceValue{1}, 'Dim=1') && strcmp(add.TargetValue{1}, '<missing>'));
    assert(strcmp(removed.SourceValue{1}, 'Status=remove'));
    assert(contains(removed.TargetValue{1}, 'DataType=double') && contains(removed.TargetValue{1}, 'Dim=1'));
    assert(contains(console, 'BusA.New35') && contains(console, 'BusA.Keep25'));
    assert(isequal(before, local_bytes(dictionary)), 'Preview changed the dictionary.');
    assert(isequal(legacyExport, local_bytes('export.xlsx')));
    assert(~any(strcmp(summary.Changes.Interface, 'BusA.Shared')));
    assert(~any(startsWith(summary.Changes.Interface, 'BusB.')));

    fig = interface_tools_gui(struct('ConfigFile', configFile));
    figCleanup = onCleanup(@() delete(fig));
    sheets = findall(fig, 'Tag', 'SyncSheets');
    assert(numel(sheets.Items) == 2);
    sheets.Value = {'ModelA'};
    sheets.ValueChangedFcn(sheets, []);
    button = findall(fig, 'Tag', 'PreviewSldd');
    button.ButtonPushedFcn(button, []);
    details = findall(fig, 'Tag', 'InterfaceDifferences');
    assert(size(details.Data, 1) == 61);
    drawnow;
    assert(isequal(sheets.Layout.Column, [1 2]) && sheets.Position(3) > 500 && sheets.Position(4) > 130);
    selectChanges = findall(fig, 'Tag', 'SelectChanges');
    clearChanges = findall(fig, 'Tag', 'ClearChanges');
    assert(isscalar(selectChanges) && isscalar(clearChanges));
    assert(strcmp(selectChanges.Visible, 'on') && strcmp(clearChanges.Visible, 'on'));
    assert(selectChanges.Layout.Row == 1 && selectChanges.Layout.Column == 1);
    assert(clearChanges.Layout.Row == 1 && clearChanges.Layout.Column == 2);
    assert(strcmp(fig.AutoResizeChildren, 'off'));
    originalPosition = fig.Position;
    fig.Position = [40 40 1180 668];
    drawnow;
    assert(details.Position(4) >= 220, 'Short windows must retain a usable differences table.');
    assert(strcmp(details.Parent.Scrollable, 'on'));
    fig.Position(3) = 720;
    drawnow; pause(0.2);
    assert(selectChanges.Position(3) >= 145 && clearChanges.Position(3) >= 120);
    assert(selectChanges.Position(1) < clearChanges.Position(1));
    assert(sum(clearChanges.Position([1 3])) <= clearChanges.Parent.Position(3) + 1);
    assert(selectChanges.Parent.Position(4) >= 32);
    exportapp(fig, fullfile(sandbox, 'gui-change-buttons-narrow.png'));
    fig.Position(3) = 1180;
    drawnow;
    scroll(details.Parent, 'bottom');
    drawnow;
    pause(0.2);
    exportapp(fig, fullfile(sandbox, 'gui-short-window.png'));
    scroll(details.Parent, 'top');
    fig.Position = originalPosition;
    drawnow;
    activity = findall(fig, 'Tag', 'ActivityLog');
    follow = findall(fig, 'Tag', 'FollowLog');
    assert(follow.Value && numel(activity.Value) > 60);
    logText = strjoin(activity.Value, newline);
    assert(contains(logText, '[READ XLSX]') && contains(logText, '[READ SLDD]'));
    assert(contains(logText, '[COMPARE]') && contains(logText, '[ADD] BusA.New35'));
    assert(contains(logText, '[REMOVE] BusA.Old') && contains(logText, '[PROPERTY_DIFF]'));
    assert(any(strcmp(details.Data(:, 3), 'BusA.New35')));
    assert(isequal(before, local_bytes(dictionary)));
    applyButton = findall(fig, 'Tag', 'SyncSldd');
    assert(strcmp(applyButton.Enable, 'off') && ~any(cell2mat(details.Data(:, 1))));
    selectChanges = findall(fig, 'Tag', 'SelectChanges');
    selectChanges.ButtonPushedFcn(selectChanges, []);
    assert(sum(cell2mat(details.Data(:, 1))) == 61);
    clearChanges = findall(fig, 'Tag', 'ClearChanges');
    clearChanges.ButtonPushedFcn(clearChanges, []);
    assert(strcmp(applyButton.Enable, 'off'));
    propertyRow = find(strcmp(details.Data(:, 2), 'PROPERTY_DIFF'), 1);
    details.CellEditCallback(details, struct('Indices', [propertyRow 1], 'NewData', true));
    assert(details.Data{propertyRow, 1});
    addRow = find(strcmp(details.Data(:, 3), 'BusA.New01'), 1);
    removeRow = find(strcmp(details.Data(:, 3), 'BusA.Old'), 1);
    assert(strcmp(details.Data{addRow, 4}, 'element') && contains(details.Data{addRow, 5}, 'DataType=double'));
    assert(strcmp(details.Data{addRow, 6}, '<missing>'));
    assert(strcmp(details.Data{removeRow, 5}, 'Status=remove') && contains(details.Data{removeRow, 6}, 'Dim=1'));
    details.CellEditCallback(details, struct('Indices', [addRow 1], 'NewData', true));
    details.CellEditCallback(details, struct('Indices', [removeRow 1], 'NewData', true));
    assert(strcmp(applyButton.Enable, 'on') && contains(applyButton.Text, '(3)'));
    drawnow; pause(0.2); % Let the web UI paint before capturing the controls.
    exportapp(fig, fullfile(sandbox, 'gui-selected.png'));
    applyButton.ButtonPushedFcn(applyButton, []);
    assert(size(details.Data, 1) == 58 && strcmp(applyButton.Enable, 'off'));
    logText = strjoin(activity.Value, newline);
    assert(contains(logText, '[+] BusA.New01') && contains(logText, '[-] BusA.Old'));
    assert(contains(logText, '[SAVED]') && contains(logText, 'Applied: ADD=1 REMOVE=1 UPDATE=1 SAVED=1'));
    assert(contains(logText, '[~] BusA.Keep01 [dataType]'));
    dd = Simulink.dictionary.archdata.open(dictionary);
    bus = getInterface(dd, 'BusA');
    assert(any(strcmp({bus.Elements.Name}, 'New01')) && ~any(strcmp({bus.Elements.Name}, 'New02')));
    assert(~any(strcmp({bus.Elements.Name}, 'Old')));
    assert(strcmp(getElement(bus, 'Keep01').Type.DataType, 'double'));
    assert(strcmp(getElement(bus, 'Keep02').Type.DataType, 'uint8'));
    close(dd);
    sheets.Value = {'ModelB'};
    sheets.ValueChangedFcn(sheets, []);
    assert(isempty(details.Data) && strcmp(applyButton.Enable, 'off'));
    assert(isempty(findall(fig, 'Text', 'Sync + Generate ALL sheets')));
    writecell({'Notes only: no parameter headers'}, 'source.xlsx', 'Sheet', 'Notes');
    follow.Value = false;
    follow.ValueChangedFcn(follow, []);
    pausedLog = activity.Value;
    button = findall(fig, 'Tag', 'GenerateParameters');
    button.ButtonPushedFcn(button, []);
    assert(isequal(pausedLog, activity.Value), 'Paused log view moved while backend ran.');
    follow.Value = true;
    follow.ValueChangedFcn(follow, []);
    logText = strjoin(activity.Value, newline);
    assert(contains(logText, '[WARNING]') && contains(logText, 'required headers not found'));
    assert(contains(logText, '[READ PARAMETERS]') && contains(logText, 'exported 25 parameter(s)'));
    assert(contains(logText, '27 parameter(s) written') && contains(logText, '[ADD] BusA.New35'));
    assert(contains(activity.Value{1}, 'Finished successfully.'));
    output = fileread(fullfile(sandbox, 'arch', 'parameters.m'));
    assert(contains(output, 'pShared = Simulink.Parameter;'));
    assert(contains(output, 'pSafe = Simulink.Parameter;'));
    assert(strcmp(button.Enable, 'on') && strcmp(sheets.Enable, 'on'));
    drawnow; pause(0.2);
    exportapp(fig, fullfile(sandbox, 'gui-preview.png'));
    sourceField = findall(fig, 'Tag', 'SourceXlsx');
    sourceField.Value = '';
    sourceField.ValueChangedFcn(sourceField, []);
    assert(isempty(details.Data) && isempty(sheets.Items));
    clear figCleanup;

    summary = sync_bus_interfaces_from_excel('source.xlsx', dictionary, 'ModelA', 'export.xlsx', 'apply');
    assert(summary.Added == 34 && summary.Removed == 0 && summary.Updated == 24 && summary.Saved);
    dd = Simulink.dictionary.archdata.open(dictionary);
    bus = getInterface(dd, 'BusA');
    names = string({bus.Elements.Name});
    assert(any(names == 'Shared') && any(names == 'New35') && ~any(names == 'Old'));
    elem = getElement(bus, 'Keep01');
    assert(strcmp(elem.Type.DataType, 'double'));
    other = getInterface(dd, 'BusB');
    assert(isequal(string({other.Elements.Name}), "Safe"));
    close(dd);
    clear dictCleanup;

    % Direct reads must observe Apply immediately, without a workbook snapshot.
    [~, summary] = evalc('sync_bus_interfaces_from_excel(''source.xlsx'', dictionary, ''ModelA'', ''export.xlsx'', ''preview'')');
    assert(summary.ToAdd == 0 && summary.ToRemove == 0 && summary.MetadataMismatch == 0);
    assert(isempty(summary.Changes) && ~summary.Saved);
    for k = 2:26, source{k, 3} = 'uint8'; end
    writecell(source, 'source.xlsx', 'Sheet', 'ModelA');
    summary = sync_bus_interfaces_from_excel('source.xlsx', dictionary, 'ModelA', 'apply');
    assert(summary.Updated == 25 && summary.Added == 0 && summary.Removed == 0 && summary.Saved);
    [~, summary] = evalc('sync_bus_interfaces_from_excel(''source.xlsx'', dictionary, ''ModelA'', ''export.xlsx'', ''preview'')');
    assert(isempty(summary.Changes) && width(summary.Changes) == 5 && ~summary.Saved);

    config = rmfield(config, 'ExportXlsx'); % New configs need no exporter setting.
    config.ProjectRoot = sandbox; % Explicit root and absolute source/output paths.
    config.SourceXlsx = fullfile(sandbox, 'source.xlsx');
    config.ParametersFile = fullfile(sandbox, 'arch', 'absolute.m');
    local_write(configFile, jsonencode(config));
    fig = interface_tools_gui(struct('ConfigFile', configFile));
    figCleanup = onCleanup(@() delete(fig));
    button = findall(fig, 'Tag', 'GenerateParameters');
    button.ButtonPushedFcn(button, []);
    assert(isfile(config.ParametersFile));
    button = findall(fig, 'Tag', 'PreviewSldd');
    button.ButtonPushedFcn(button, []);
    details = findall(fig, 'Tag', 'InterfaceDifferences');
    assert(isempty(details.Data) && size(details.Data, 2) == 6);
    clear figCleanup;
    config.SourceXlsx = 1;
    local_write(configFile, jsonencode(config));
    rejected = false;
    try
        interface_tools_gui(struct('ConfigFile', configFile));
    catch ME
        rejected = strcmp(ME.identifier, 'InterfaceTools:Config');
    end
    assert(rejected, 'Invalid config must fail before creating a GUI.');
    local_testDirectSnapshot(sandbox);
    local_testSelectedChanges(sandbox);
    local_testStatusRemoval(sandbox);
    local_testComparisonScope(sandbox);
    local_testPropertyUpdates(sandbox);
    local_testReviewedRegressions(sandbox);
    fprintf('PASS: CLI preview/apply, complete GUI preview, all-sheet parameters, config paths/validation.\n');
    fprintf('Synthetic fixtures and GUI screenshot: %s\n', sandbox);
end

function local_testDirectSnapshot(sandbox)
    referenceFile = fullfile(sandbox, 'reference.sldd');
    ref = Simulink.dictionary.archdata.create(referenceFile);
    refCleanup = onCleanup(@() local_close(ref));
    refBus = addDataInterface(ref, 'Referenced');
    addElement(refBus, 'Keep');
    save(ref);
    close(ref);

    file = fullfile(sandbox, 'direct.sldd');
    dd = Simulink.dictionary.archdata.create(file);
    cleanup = onCleanup(@() local_close(dd));
    addReference(dd, 'reference.sldd');
    inner = addDataInterface(dd, 'Inner');
    addElement(inner, 'Value');
    bus = addDataInterface(dd, 'Bus');
    elem = addElement(bus, 'Vector');
    elem.Type.DataType = 'single';
    elem.Dimensions = '[2 3]';
    elem.Type.Unit = 'm/s';
    elem.Description = 'Vehicle speed';
    elem = addElement(bus, 'Nested');
    elem.Type = inner;
    record = addStructType(dd, 'Record');
    elem = addElement(bus, 'Struct');
    elem.Type = record;
    alias = addAliasType(dd, 'Counter');
    alias.BaseType = 'uint8';
    elem = addElement(bus, 'Alias');
    elem.Type = alias;
    value = addValueType(dd, 'Speed');
    value.DataType = 'single';
    value.Unit = 'm/s';
    elem = addElement(bus, 'NamedValue');
    elem.Type = value;
    addDataInterface(dd, 'Empty');
    orphan = addDataInterface(dd, 'OnlyInSldd');
    addElement(orphan, 'Preserve');
    addServiceInterface(dd, 'Service');
    addPhysicalInterface(dd, 'Physical');
    save(dd);
    close(dd);
    design = Simulink.data.dictionary.open(file);
    section = getSection(design, 'Design Data');
    addEntry(section, 'DesignBus', Simulink.Bus);
    saveChanges(design);
    close(design);
    before = local_bytes(file);
    refBefore = local_bytes(referenceFile);

    source = fullfile(sandbox, 'direct.xlsx');
    rows = {'Bus', 'Element', 'DataType', 'Dim', 'Unit', 'Description'; ...
        'Bus', 'Vector', 'single', '2x3', 'm/s', 'Vehicle speed'; ...
        'Bus', 'Nested', 'Bus: Inner', '1', '', ''; ...
        'Bus', 'Struct', 'Bus: Record', '1', '', ''; ...
        'Bus', 'Alias', 'Counter', '1', '', ''; ...
        'Bus', 'NamedValue', 'single', '1', 'm/s', ''; ...
        'Inner', 'Value', 'double', '1', '', ''; ...
        'Referenced', 'Keep', 'uint8', '1', '', ''; ...
        'Referenced', 'New', 'double', '1', '', ''; ...
        'NewBus', 'New', 'uint16', '2', '', ''};
    writecell(rows, source);
    [~, report] = evalc('sync_bus_interfaces_from_excel(source, file, "all", "preview")');
    assert(report.ToAdd == 2 && report.ToRemove == 0 && report.MetadataMismatch == 1);
    assert(report.OutOfScope == 0 && height(report.Interfaces) == 3);
    assert(~any(ismember({'Empty', 'OnlyInSldd'}, report.Interfaces.Name)));
    assert(~any(startsWith(report.Changes.Interface, 'OnlyInSldd.')));
    assert(~any(ismember({'Service', 'Physical', 'DesignBus'}, report.Interfaces.Name)));
    assert(report.Interfaces.Referenced(strcmp(report.Interfaces.Name, 'Referenced')));
    assert(~any(report.Selectable(startsWith(report.Changes.Interface, 'Referenced.'))));
    assert(isequal(before, local_bytes(file)) && isequal(refBefore, local_bytes(referenceFile)));
    report = sync_bus_interfaces_from_excel(source, file, 'all', 'apply');
    assert(report.Added == 1 && report.NewInterfaces == 1 && report.Removed == 0);
    assert(report.Saved && report.ReferencedSkipped == 2 && report.OutOfScope == 0);
    ref = Simulink.dictionary.archdata.open(referenceFile);
    assert(isequal(string({getInterface(ref, 'Referenced').Elements.Name}), "Keep"));
    assert(strcmp(getElement(getInterface(ref, 'Referenced'), 'Keep').Type.DataType, 'double'));
    assert(~isDirty(ref));
    close(ref);
    dd = Simulink.dictionary.archdata.open(file);
    assert(isscalar(getInterface(dd, 'OnlyInSldd').Elements));
    assert(ismember('Empty', getInterfaceNames(dd)));
    assert(strcmp(getElement(getInterface(dd, 'NewBus'), 'New').Type.DataType, 'uint16'));

    % Preview retains an already open dictionary and all unsaved user edits.
    bus = getInterface(dd, 'Bus');
    addElement(bus, 'UserUnsaved');
    [~, report] = evalc('sync_bus_interfaces_from_excel(source, file, "all", "preview")');
    assert(isDirty(dd) && ~any(strcmp(report.Changes.Interface, 'Bus.UserUnsaved')));
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', 'apply'), ...
        'InterfaceTools:DirtyDictionary');
    assert(isDirty(dd) && numel(getInterface(dd, 'Bus').Elements) == 6);
    discardChanges(dd);
    close(dd);

    % Native save/discard includes references; reject their pending edits too.
    ref = Simulink.dictionary.archdata.open(referenceFile);
    addElement(getInterface(ref, 'Referenced'), 'UserPending');
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', 'apply'), ...
        'InterfaceTools:DirtyDictionary');
    assert(isDirty(ref) && numel(getInterface(ref, 'Referenced').Elements) == 2);
    discardChanges(ref);
    close(ref);

    % A late API error must roll back earlier successful additions as well.
    before = local_bytes(file);
    rows(end+1, :) = {'Bus', 'AValid', 'double', '1', '', ''};
    rows(end+1, :) = {'Bus', 'ZInvalid', 'Bus: MissingType', '1', 'm/s', ''};
    writecell(rows, source);
    failed = false;
    try
        sync_bus_interfaces_from_excel(source, file, 'all', 'apply');
    catch
        failed = true;
    end
    assert(failed && isequal(before, local_bytes(file)));
    dd = Simulink.dictionary.archdata.open(file);
    assert(~any(strcmp({getInterface(dd, 'Bus').Elements.Name}, 'AValid')));
    close(dd);
    clear cleanup refCleanup;
    fprintf('PASS: direct inventory, typed elements, references, dirty edits, rollback, no exporter.\n');
end

function local_testSelectedChanges(sandbox)
    file = fullfile(sandbox, 'selected.sldd');
    dd = Simulink.dictionary.archdata.create(file);
    cleanup = onCleanup(@() local_close(dd));
    bus = addDataInterface(dd, 'Selected');
    addElement(bus, 'RemoveA');
    addElement(bus, 'RemoveB');
    addElement(bus, 'Keep');
    save(dd);
    close(dd);
    source = fullfile(sandbox, 'selected.xlsx');
    rows = {'Bus', 'Element', 'DataType', 'Status'; 'Selected', 'Keep', 'uint8', ''; ...
        'Selected', 'AddA', 'double', ''; 'Selected', 'AddB', 'single', ''; ...
        'Selected', 'RemoveA', '', 'remove'; 'Selected', 'RemoveB', '', 'remove'};
    writecell(rows, source);
    [~, report] = evalc('sync_bus_interfaces_from_excel(source, file, "all", "preview")');
    assert(report.ToAdd == 2 && report.ToRemove == 2 && report.MetadataMismatch == 1);
    chosen = ismember(report.Changes.Interface, {'Selected.AddA', 'Selected.RemoveA'});
    opts = struct('Mode', 'apply', 'SelectedChanges', report.Changes(chosen, :), ...
        'ExpectedSnapshot', {report.Snapshot});
    empty = opts;
    empty.SelectedChanges = report.Changes([], :);
    before = local_bytes(file);
    result = sync_bus_interfaces_from_excel(source, file, 'all', empty);
    assert(~result.Saved && isequal(before, local_bytes(file)));
    invalid = opts;
    invalid.SelectedChanges = report.Changes(strcmp(report.Changes.Action, 'PROPERTY_DIFF'), {'Action', 'Interface'});
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', invalid), ...
        'InterfaceTools:Selection');
    invalid.SelectedChanges = table({'ADD'}, {'OtherBus.New'}, 'VariableNames', {'Action', 'Interface'});
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', invalid), ...
        'InterfaceTools:Selection');
    % A changed type on a pending addition must invalidate an old selection.
    rows{3, 3} = 'uint16';
    writecell(rows, source);
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', opts), ...
        'InterfaceTools:StalePreview');
    assert(isequal(before, local_bytes(file)));
    rows{3, 3} = 'double';
    writecell(rows, source);
    dd = Simulink.dictionary.archdata.open(file);
    element = getElement(getInterface(dd, 'Selected'), 'Keep');
    element.Type.DataType = 'single';
    save(dd);
    close(dd);
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', opts), ...
        'InterfaceTools:StalePreview');
    dd = Simulink.dictionary.archdata.open(file);
    element = getElement(getInterface(dd, 'Selected'), 'Keep');
    element.Type.DataType = 'double';
    save(dd);
    close(dd);
    result = sync_bus_interfaces_from_excel(source, file, 'all', opts);
    assert(result.Added == 1 && result.Removed == 1 && result.Saved);
    dd = Simulink.dictionary.archdata.open(file);
    names = string({getInterface(dd, 'Selected').Elements.Name});
    assert(all(ismember(["Keep", "AddA", "RemoveB"], names)));
    assert(~any(ismember(["AddB", "RemoveA"], names)));
    assert(strcmp(getElement(getInterface(dd, 'Selected'), 'Keep').Type.DataType, 'double'));
    close(dd);
    % An Excel bus absent from SLDD yields additions and a typed empty inventory.
    missing = fullfile(sandbox, 'missing.xlsx');
    writecell({'Bus', 'Element', 'DataType'; 'NewBus', 'New', 'double'}, missing);
    [~, report] = evalc('sync_bus_interfaces_from_excel(missing, file, "all", "preview")');
    assert(report.ToAdd == 1 && isempty(report.Interfaces));
    clear cleanup;
    fprintf('PASS: selected changes, empty/invalid selections, stale preview, Excel-only scope.\n');
end

function local_testStatusRemoval(sandbox)
    file = fullfile(sandbox, 'status.sldd');
    dd = Simulink.dictionary.archdata.create(file);
    cleanup = onCleanup(@() local_close(dd));
    bus = addDataInterface(dd, 'StatusBus');
    names = {'AbsentFromExcel', 'Blank', 'Accepted', 'OtherStatus', 'Marked', 'Unchecked'};
    for k = 1:numel(names), addElement(bus, names{k}); end
    save(dd);
    close(dd);
    source = fullfile(sandbox, 'status.xlsx');
    rows = {'Bus', 'Element', 'Status'; 'StatusBus', 'Blank', ''; ...
        'StatusBus', 'Accepted', 'Accept'; 'StatusBus', 'OtherStatus', 'removed'; ...
        'StatusBus', 'Marked', ' ReMoVe '; 'StatusBus', 'Unchecked', 'remove'; ...
        'StatusBus', 'NotPresent', 'remove'; 'MissingBus', 'MissingElement', 'remove'};
    writecell(rows, source, 'Sheet', 'Selected');
    before = local_bytes(file);
    [~, preview] = evalc('sync_bus_interfaces_from_excel(source, file, "all", "preview")');
    assert(preview.ToAdd == 0 && preview.ToRemove == 2 && preview.MetadataMismatch == 0);
    assert(all(strcmp(preview.Changes.Action, 'REMOVE')));
    assert(all(ismember(preview.Changes.Interface, {'StatusBus.Marked', 'StatusBus.Unchecked'})));
    chosen = strcmp(preview.Changes.Interface, 'StatusBus.Marked');
    opts = struct('Mode', 'apply', 'SelectedChanges', preview.Changes(chosen, :), ...
        'ExpectedSnapshot', {preview.Snapshot});
    rows{5, 3} = '';
    writecell(rows, source, 'Sheet', 'Selected');
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', opts), ...
        'InterfaceTools:StalePreview');
    assert(isequal(before, local_bytes(file)));
    rows{5, 3} = ' ReMoVe ';
    writecell(rows, source, 'Sheet', 'Selected');
    result = sync_bus_interfaces_from_excel(source, file, 'all', opts);
    assert(result.Removed == 1 && result.Added == 0 && result.Saved);
    dd = Simulink.dictionary.archdata.open(file);
    remaining = string({getInterface(dd, 'StatusBus').Elements.Name});
    assert(~any(remaining == 'Marked') && all(ismember(string(names(~strcmp(names, 'Marked'))), remaining)));
    assert(~any(strcmp(getInterfaceNames(dd), 'MissingBus')));
    close(dd);
    [~, after] = evalc('sync_bus_interfaces_from_excel(source, file, "all", "preview")');
    assert(after.ToAdd == 0 && after.ToRemove == 1);
    % A conflicting keep row in another sheet must prevent deletion.
    writecell({'Bus', 'Element', 'Status'; 'StatusBus', 'Unchecked', 'Accept'}, ...
        source, 'Sheet', 'Shared');
    before = local_bytes(file);
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'Selected', 'apply'), ...
        'InterfaceTools:SourceConflict');
    assert(isequal(before, local_bytes(file)));
    % Workbooks without Status never infer deletions from absent elements.
    noStatus = fullfile(sandbox, 'no-status.xlsx');
    writecell({'Bus', 'Element'; 'StatusBus', 'Blank'}, noStatus);
    result = sync_bus_interfaces_from_excel(noStatus, file, 'all', 'apply');
    assert(result.ToRemove == 0 && ~result.Saved && isequal(before, local_bytes(file)));
    clear cleanup;
    fprintf('PASS: explicit remove Status, missing Status, stale Status, shared conflicts, selected deletion.\n');
end

function local_testComparisonScope(sandbox)
    file = fullfile(sandbox, 'scope.sldd');
    dd = Simulink.dictionary.archdata.create(file);
    cleanup = onCleanup(@() local_close(dd));
    bus = addDataInterface(dd, 'Valid');
    addElement(bus, 'Keep');
    addElement(bus, 'Old');
    addServiceInterface(dd, 'Service');
    addPhysicalInterface(dd, 'Physical');
    save(dd);
    close(dd);
    source = fullfile(sandbox, 'scope.xlsx');
    header = {'Bus', 'Element', 'DataType', 'Status'};
    % The unselected sheet is first: scope must not depend on workbook order.
    writecell([header; {'Ignored', 'Value', 'double', 'Accept'; ...
        'Ignored', 'Value', 'single', 'remove'; 'Valid', 'Keep', 'double', ''}], ...
        source, 'Sheet', 'Unselected');
    selected = [header; {'Valid', 'New', 'double', ''; 'Valid', 'Old', '', 'remove'; ...
        'Service', 'Value', 'double', ''; 'Service', 'Value', '', 'remove'; ...
        'Physical', 'Value', 'double', ''}];
    writecell(selected, source, 'Sheet', 'Selected');
    before = local_bytes(file);
    preview = sync_bus_interfaces_from_excel(source, file, 'Selected', 'preview');
    assert(preview.ToAdd == 1 && preview.ToRemove == 1 && preview.MetadataMismatch == 0);
    assert(preview.Buses == 1 && preview.OutOfScope == 2);
    assert(all(startsWith(preview.Changes.Interface, 'Valid.')) && all(preview.Selectable));
    assert(isequal(before, local_bytes(file)));
    config = jsondecode(fileread(fullfile(fileparts(mfilename('fullpath')), ...
        '..', 'tools', 'interface_tools', 'interface_tools_config.json')));
    config.SourceXlsx = source;
    config.ProjectRoot = sandbox;
    config.SlddFile = file;
    config.ParametersFile = fullfile(sandbox, 'scope-parameters.m');
    configFile = fullfile(sandbox, 'scope-config.json');
    local_write(configFile, jsonencode(config));
    fig = interface_tools_gui(struct('ConfigFile', configFile));
    figCleanup = onCleanup(@() delete(fig));
    sheets = findall(fig, 'Tag', 'SyncSheets');
    sheets.Value = {'Selected'};
    sheets.ValueChangedFcn(sheets, []);
    button = findall(fig, 'Tag', 'PreviewSldd');
    button.ButtonPushedFcn(button, []);
    details = findall(fig, 'Tag', 'InterfaceDifferences');
    assert(size(details.Data, 1) == 2 && all(startsWith(details.Data(:, 3), 'Valid.')));
    selectAll = findall(fig, 'Tag', 'SelectChanges');
    selectAll.ButtonPushedFcn(selectAll, []);
    assert(all(cell2mat(details.Data(:, 1))));
    clear figCleanup;
    opts = struct('Mode', 'apply', 'SelectedChanges', preview.Changes, ...
        'ExpectedSnapshot', {preview.Snapshot});
    result = sync_bus_interfaces_from_excel(source, file, 'Selected', opts);
    assert(result.Added == 1 && result.Removed == 1 && result.Saved);
    dd = Simulink.dictionary.archdata.open(file);
    assert(isequal(sort(string({getInterface(dd, 'Valid').Elements.Name})), ["Keep", "New"]));
    assert(isa(getInterface(dd, 'Service'), 'Simulink.dictionary.archdata.ServiceInterface'));
    assert(isa(getInterface(dd, 'Physical'), 'Simulink.dictionary.archdata.PhysicalInterface'));
    close(dd);
    % Legacy apply-all also ignores unsupported types instead of aborting a batch.
    selected(end+1, :) = {'Valid', 'Next', 'single', ''};
    writecell(selected, source, 'Sheet', 'Selected');
    result = sync_bus_interfaces_from_excel(source, file, 'Selected', 'apply');
    assert(result.Added == 1 && result.Saved);
    % Still reject conflicts for compared buses, including an earlier shared sheet.
    writecell([header; {'Valid', 'Keep', 'double', 'remove'}], source, 'Sheet', 'Unselected');
    selected(end+1, :) = {'Valid', 'Keep', 'double', 'Accept'};
    writecell(selected, source, 'Sheet', 'Selected');
    before = local_bytes(file);
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'Selected', 'apply'), ...
        'InterfaceTools:SourceConflict');
    assert(isequal(before, local_bytes(file)));
    clear cleanup;
    fprintf('PASS: non-data interfaces excluded, out-of-scope conflicts ignored, shared scope protected.\n');
end

function local_testPropertyUpdates(sandbox)
    reference = fullfile(sandbox, 'propertyReference.sldd');
    ref = Simulink.dictionary.archdata.create(reference);
    refCleanup = onCleanup(@() local_close(ref));
    sharedRef = addValueType(ref, 'SharedRef');
    sharedRef.Unit = 'm/s';
    refBus = addDataInterface(ref, 'RefConsumer');
    refElem = addElement(refBus, 'Keep');
    refElem.Type = sharedRef;
    save(ref);
    close(ref);
    file = fullfile(sandbox, 'properties.sldd');
    dd = Simulink.dictionary.archdata.create(file);
    cleanup = onCleanup(@() local_close(dd));
    addReference(dd, 'propertyReference.sldd');
    bus = addDataInterface(dd, 'Properties');
    elem = addElement(bus, 'APlain');
    elem.Type.Unit = 'm/s';
    elem.Description = 'Old plain';
    value = addValueType(dd, 'Shared');
    value.Unit = 'm/s';
    value.Minimum = '-10';
    value.Maximum = '100';
    value.Description = 'Old shared';
    for name = {'Named', 'Peer'}
        elem = addElement(bus, name{1});
        elem.Type = value;
    end
    elem = addElement(bus, 'NamedRef');
    elem.Type = getDataType(dd, 'SharedRef');
    alias = addAliasType(dd, 'Counter');
    alias.BaseType = 'uint8';
    elem = addElement(bus, 'Alias');
    elem.Type = alias;
    inner = addDataInterface(dd, 'Inner');
    elem = addElement(bus, 'Nested');
    elem.Type = inner;
    save(dd);
    close(dd);
    source = fullfile(sandbox, 'properties.xlsx');
    rows = {'Bus', 'Element', 'DataType', 'Dim', 'Unit', 'Description'; ...
        'Properties', 'APlain', 'single', '2x3', 'km/h', 'New plain'; ...
        'Properties', 'Named', 'single', '2', 'km/h', 'New named'; ...
        'Properties', 'NamedRef', 'single', '2', 'km/h', 'New ref'; ...
        'Properties', 'Alias', 'uint16', '2', '', 'New alias'; ...
        'Properties', 'Nested', 'double', '2', '', 'New nested'};
    writecell(rows, source);
    before = local_bytes(file);
    refBefore = local_bytes(reference);
    preview = sync_bus_interfaces_from_excel(source, file, 'all', 'preview');
    assert(preview.ToAdd == 0 && preview.ToRemove == 0 && preview.MetadataMismatch > 4);
    assert(all(preview.Selectable) && isequal(before, local_bytes(file)));
    selected = strcmp(preview.Changes.Interface, 'Properties.APlain') & strcmp(preview.Changes.Property, 'unit');
    opts = struct('Mode', 'apply', 'SelectedChanges', preview.Changes(selected, :), ...
        'ExpectedSnapshot', {preview.Snapshot});
    invalid = opts;
    invalid.SelectedChanges.Property{1} = 'unknown';
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', invalid), 'InterfaceTools:Selection');
    rows{2, 5} = 'm';
    writecell(rows, source);
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', opts), 'InterfaceTools:StalePreview');
    rows{2, 5} = 'km/h';
    writecell(rows, source);
    result = sync_bus_interfaces_from_excel(source, file, 'all', opts);
    assert(result.Updated == 1 && result.SelectedUpdate == 1 && result.Saved);
    dd = Simulink.dictionary.archdata.open(file);
    elem = getElement(getInterface(dd, 'Properties'), 'APlain');
    assert(strcmp(elem.Type.Unit, 'km/h') && strcmp(elem.Type.DataType, 'double'));
    assert(strcmp(elem.Dimensions, '1') && strcmp(elem.Description, 'Old plain'));
    close(dd);
    % Description-only updates on named types must be effective and isolated.
    preview = sync_bus_interfaces_from_excel(source, file, 'all', 'preview');
    selected = strcmp(preview.Changes.Interface, 'Properties.Named') & strcmp(preview.Changes.Property, 'description');
    opts.SelectedChanges = preview.Changes(selected, :);
    opts.ExpectedSnapshot = preview.Snapshot;
    result = sync_bus_interfaces_from_excel(source, file, 'all', opts);
    assert(result.Updated == 1);
    dd = Simulink.dictionary.archdata.open(file);
    elem = getElement(getInterface(dd, 'Properties'), 'Named');
    assert(strcmp(elem.Description, 'New named') && strcmp(elem.Type.DataType, 'double'));
    assert(strcmp(elem.Type.Unit, 'm/s') && strcmp(elem.Dimensions, '1'));
    assert(strcmp(elem.Type.Minimum, '-10') && strcmp(elem.Type.Maximum, '100'));
    assert(strcmp(getElement(getInterface(dd, 'Properties'), 'Peer').Description, 'Old shared'));
    close(dd);
    % An error after the first property write must discard the whole transaction.
    preview = sync_bus_interfaces_from_excel(source, file, 'all', 'preview');
    opts.SelectedChanges = preview.Changes;
    opts.ExpectedSnapshot = preview.Snapshot;
    opts.LogFcn = @local_failAfterProperty;
    before = local_bytes(file);
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', opts), 'InterfaceTools:TestFailure');
    assert(isequal(before, local_bytes(file)) && isequal(refBefore, local_bytes(reference)));
    opts.LogFcn = @(message) local_failAfterProperty(message, 'Properties.Named');
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'all', opts), 'InterfaceTools:TestFailure');
    assert(isequal(before, local_bytes(file)) && isequal(refBefore, local_bytes(reference)));
    % Apply a properties-only plan through the GUI, then verify the refresh is empty.
    config = jsondecode(fileread(fullfile(fileparts(mfilename('fullpath')), ...
        '..', 'tools', 'interface_tools', 'interface_tools_config.json')));
    config.SourceXlsx = source;
    config.ProjectRoot = sandbox;
    config.SlddFile = file;
    config.ParametersFile = fullfile(sandbox, 'property-parameters.m');
    configFile = fullfile(sandbox, 'property-config.json');
    local_write(configFile, jsonencode(config));
    fig = interface_tools_gui(struct('ConfigFile', configFile));
    figCleanup = onCleanup(@() delete(fig));
    button = findall(fig, 'Tag', 'PreviewSldd');
    button.ButtonPushedFcn(button, []);
    details = findall(fig, 'Tag', 'InterfaceDifferences');
    assert(size(details.Data, 1) == preview.MetadataMismatch);
    assert(all(strcmp(details.Data(:, 2), 'PROPERTY_DIFF')));
    button = findall(fig, 'Tag', 'SelectChanges');
    button.ButtonPushedFcn(button, []);
    drawnow; pause(0.2);
    exportapp(fig, fullfile(sandbox, 'gui-property-updates.png'));
    button = findall(fig, 'Tag', 'SyncSldd');
    assert(strcmp(button.Enable, 'on'));
    button.ButtonPushedFcn(button, []);
    assert(isempty(details.Data) && strcmp(button.Enable, 'off'));
    clear figCleanup;
    after = sync_bus_interfaces_from_excel(source, file, 'all', 'preview');
    assert(isempty(after.Changes) && ~after.Saved);
    dd = Simulink.dictionary.archdata.open(file);
    bus = getInterface(dd, 'Properties');
    assert(strcmp(getElement(bus, 'APlain').Dimensions, '[2 3]'));
    assert(strcmp(getElement(bus, 'Named').Type.Minimum, '-10'));
    assert(strcmp(getElement(bus, 'Peer').Type.DataType, 'double'));
    assert(strcmp(getElement(bus, 'Peer').Type.Unit, 'm/s'));
    assert(strcmp(getDataType(dd, 'Shared').Description, 'Old shared'));
    assert(strcmp(getDataType(dd, 'Counter').BaseType, 'uint8'));
    close(dd);
    % Native save can rewrite reference bookkeeping when a type use is detached.
    % Its definitions and elements must remain unchanged and clean.
    ref = Simulink.dictionary.archdata.open(reference);
    sharedRef = getDataType(ref, 'SharedRef');
    assert(strcmp(sharedRef.DataType, 'double') && strcmp(sharedRef.Unit, 'm/s'));
    assert(strcmp(sharedRef.Dimensions, '1') && isempty(sharedRef.Description) && ~isDirty(ref));
    refElem = getElement(getInterface(ref, 'RefConsumer'), 'Keep');
    assert(strcmp(refElem.Type.Name, 'SharedRef') && strcmp(refElem.Type.DataType, 'double'));
    assert(strcmp(refElem.Type.Unit, 'm/s') && strcmp(refElem.Dimensions, '1'));
    close(ref);
    % Cross-sheet metadata conflicts must not silently choose one value to write.
    writecell([rows(1, :); {'Properties', 'APlain', 'single', '2x3', 'm/s', 'New plain'}], ...
        source, 'Sheet', 'Shared');
    before = local_bytes(file);
    local_expectError(@() sync_bus_interfaces_from_excel(source, file, 'Sheet1', 'apply'), ...
        'InterfaceTools:SourceConflict');
    assert(isequal(before, local_bytes(file)));
    clear cleanup refCleanup;
    fprintf('PASS: property-only CLI/GUI, per-property selection, named/reference types, stale preview, rollback.\n');
end

function local_testReviewedRegressions(sandbox)
    source = fullfile(sandbox, 'review-parameters.xlsx');
    output = fullfile(sandbox, 'reviewParameters.m');
    description = sprintf('First line: 100%% \\path\nSecond ''quoted'' line');
    writecell({'Status', 'Parameter', 'Value', 'DataType', 'Element'; ...
        'Accept', 'reviewParameter', '1,000', 'double', description}, source);
    generate_simulink_parameters(source, output);
    clear reviewParameters;
    run(output);
    assert(reviewParameter.Value == 1000 && strcmp(reviewParameter.Description, description));
    writecell({'Status', 'Parameter', 'Value', 'DataType', 'Element'; ...
        'Accept', 'reviewParameter', '2,000', 'double', description}, source);
    generate_simulink_parameters(source, output);
    % Same-size rewrites within one second can retain MATLAB's script cache.
    assert(contains(fileread(output), 'reviewParameter.Value = 2000;'));
    clear reviewParameters;
    run(output);
    assert(reviewParameter.Value == 2000 && strcmp(reviewParameter.Description, description));
    original = local_bytes(output);
    existingFiles = dir(fullfile(sandbox, '*.m'));
    opts = struct('LogFcn', @local_failParameterRead);
    local_expectError(@() generate_simulink_parameters(source, output, 'all', opts), ...
        'InterfaceTools:TestFailure');
    assert(isequal(original, local_bytes(output)), 'Failed generation overwrote the old output.');
    afterFiles = dir(fullfile(sandbox, '*.m'));
    assert(isequal({existingFiles.name}, {afterFiles.name}), 'Temporary parameter file leaked.');

    dictionary = fullfile(sandbox, 'reviewScope.sldd');
    dd = Simulink.dictionary.archdata.create(dictionary);
    save(dd);
    close(dd);
    workbook = fullfile(sandbox, 'review-scope.xlsx');
    header = {'Bus', 'Element', 'DataType', 'Status', 'Parameter', 'Value'};
    writecell([header; {'VisibleBus', 'V', 'double', 'Accept', 'reviewParameter', '1,000'}], ...
        workbook, 'Sheet', 'Visible');
    writecell([header; {'HiddenBus', 'H', 'double', '', '', ''}], ...
        workbook, 'Sheet', 'Wide', 'Range', 'BA1');
    config = jsondecode(fileread(fullfile(fileparts(mfilename('fullpath')), ...
        '..', 'tools', 'interface_tools', 'interface_tools_config.json')));
    config.SourceXlsx = workbook;
    config.ProjectRoot = sandbox;
    config.SlddFile = dictionary;
    config.ParametersFile = fullfile(sandbox, 'reviewGuiParameters.m');
    configFile = fullfile(sandbox, 'review-config.json');
    local_write(configFile, jsonencode(config));
    fig = interface_tools_gui(struct('ConfigFile', configFile));
    figCleanup = onCleanup(@() delete(fig));
    sheets = findall(fig, 'Tag', 'SyncSheets');
    assert(strcmp(fig.Name, 'Interface Tools'));
    assert(isequal(sort(string(sheets.Items)), ["Visible", "Wide"]));
    sheets.Value = {'Visible'};
    sheets.ValueChangedFcn(sheets, []);
    button = findall(fig, 'Tag', 'PreviewSldd');
    button.ButtonPushedFcn(button, []);
    details = findall(fig, 'Tag', 'InterfaceDifferences');
    assert(isequal(details.Data(:, 3), {'VisibleBus.V'}));
    button = findall(fig, 'Tag', 'SelectChanges');
    button.ButtonPushedFcn(button, []);
    button = findall(fig, 'Tag', 'SyncSldd');
    closeTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.01, ...
        'TimerFcn', @(clock, ~) local_attemptBusyClose(clock, fig, button));
    timerCleanup = onCleanup(@() delete(closeTimer));
    start(closeTimer);
    button.ButtonPushedFcn(button, []);
    assert(isvalid(fig) && getappdata(fig, 'ReviewCloseAttempted'));
    assert(isempty(details.Data) && strcmp(button.Enable, 'off'));
    clear timerCleanup;
    dd = Simulink.dictionary.archdata.open(dictionary);
    assert(isequal(getInterfaceNames(dd), {'VisibleBus'}));
    close(dd);
    button = findall(fig, 'Tag', 'GenerateParameters');
    button.ButtonPushedFcn(button, []);
    run(config.ParametersFile);
    assert(reviewParameter.Value == 1000);
    sourceField = findall(fig, 'Tag', 'SourceXlsx');
    setappdata(fig, 'ReviewCloseAttempted', false);
    closeTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.01, ...
        'TimerFcn', @(clock, ~) local_attemptBusyClose(clock, fig, sourceField));
    timerCleanup = onCleanup(@() delete(closeTimer));
    start(closeTimer);
    sourceField.ValueChangedFcn(sourceField, []);
    assert(isvalid(fig) && getappdata(fig, 'ReviewCloseAttempted'));
    clear timerCleanup;
    close(fig);
    assert(~isvalid(fig), 'Idle GUI must close normally.');
    clear figCleanup;
    fprintf('PASS: numeric/description generation, output preservation, wide sheets, GUI scope/busy close.\n');
end

function local_failParameterRead(message)
    if contains(message, '[READ PARAMETERS]')
        error('InterfaceTools:TestFailure', 'Simulated parameter read failure.');
    end
end

function local_attemptBusyClose(clock, fig, button)
    % A timer may fire before callback entry; close only after work has begun.
    if isvalid(fig) && strcmp(button.Enable, 'off')
        setappdata(fig, 'ReviewCloseAttempted', true);
        close(fig);
        stop(clock);
    end
end

function local_failAfterProperty(message, element)
    if nargin < 2, element = 'Properties.APlain'; end
    if contains(message, ['[~] ' element])
        error('InterfaceTools:TestFailure', 'Simulated failure after property mutation.');
    end
end

function local_expectError(action, identifier)
    rejected = false;
    try
        action();
    catch ME
        rejected = strcmp(ME.identifier, identifier);
    end
    assert(rejected, 'Expected error: %s', identifier);
end

function local_write(file, contents)
    fid = fopen(file, 'w');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', contents);
end

function bytes = local_bytes(file)
    fid = fopen(file, 'rb');
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, inf, '*uint8');
end

function local_close(dd)
    try
        close(dd);
    catch
    end
end

function local_restore(previousPath, previousFolder, sandbox)
    openFiles = Simulink.data.dictionary.getOpenDictionaryPaths();
    for k = 1:numel(openFiles)
        if startsWith(openFiles{k}, [sandbox filesep], 'IgnoreCase', ispc)
            dictionary = Simulink.data.dictionary.open(openFiles{k});
            discardChanges(dictionary);
            close(dictionary);
        end
    end
    cd(previousFolder);
    path(previousPath);
    clear sldd2excel_main;
end
