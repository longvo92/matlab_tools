function testInterfaceTools()
%TESTINTERFACETOOLS Exercise interface tools using temporary synthetic data.
% Requires live MATLAB/Simulink R2024a+. No production files are read or edited.
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
    assert(any(strcmp(details.Data(:, 3), 'BusA.New35')));
    assert(isequal(before, local_bytes(dictionary)));
    applyButton = findall(fig, 'Tag', 'SyncSldd');
    assert(strcmp(applyButton.Enable, 'off') && ~any(cell2mat(details.Data(:, 1))));
    selectChanges = findall(fig, 'Tag', 'SelectChanges');
    selectChanges.ButtonPushedFcn(selectChanges, []);
    assert(sum(cell2mat(details.Data(:, 1))) == 36);
    clearChanges = findall(fig, 'Tag', 'ClearChanges');
    clearChanges.ButtonPushedFcn(clearChanges, []);
    assert(strcmp(applyButton.Enable, 'off'));
    propertyRow = find(strcmp(details.Data(:, 2), 'PROPERTY_DIFF'), 1);
    details.CellEditCallback(details, struct('Indices', [propertyRow 1], 'NewData', true));
    assert(~details.Data{propertyRow, 1});
    addRow = find(strcmp(details.Data(:, 3), 'BusA.New01'), 1);
    removeRow = find(strcmp(details.Data(:, 3), 'BusA.Old'), 1);
    details.CellEditCallback(details, struct('Indices', [addRow 1], 'NewData', true));
    details.CellEditCallback(details, struct('Indices', [removeRow 1], 'NewData', true));
    assert(strcmp(applyButton.Enable, 'on') && contains(applyButton.Text, '(2)'));
    exportapp(fig, fullfile(sandbox, 'gui-selected.png'));
    applyButton.ButtonPushedFcn(applyButton, []);
    assert(size(details.Data, 1) == 59 && strcmp(applyButton.Enable, 'off'));
    dd = Simulink.dictionary.archdata.open(dictionary);
    bus = getInterface(dd, 'BusA');
    assert(any(strcmp({bus.Elements.Name}, 'New01')) && ~any(strcmp({bus.Elements.Name}, 'New02')));
    assert(~any(strcmp({bus.Elements.Name}, 'Old')));
    close(dd);
    sheets.Value = {'ModelB'};
    sheets.ValueChangedFcn(sheets, []);
    assert(isempty(details.Data) && strcmp(applyButton.Enable, 'off'));
    assert(isempty(findall(fig, 'Text', 'Sync + Generate ALL sheets')));
    button = findall(fig, 'Tag', 'GenerateParameters');
    button.ButtonPushedFcn(button, []);
    output = fileread(fullfile(sandbox, 'arch', 'parameters.m'));
    assert(contains(output, 'pShared = Simulink.Parameter;'));
    assert(contains(output, 'pSafe = Simulink.Parameter;'));
    assert(strcmp(button.Enable, 'on') && strcmp(sheets.Enable, 'on'));
    exportapp(fig, fullfile(sandbox, 'gui-preview.png'));
    sourceField = findall(fig, 'Tag', 'SourceXlsx');
    sourceField.Value = '';
    sourceField.ValueChangedFcn(sourceField, []);
    assert(isempty(details.Data) && isempty(sheets.Items));
    clear figCleanup;

    summary = sync_bus_interfaces_from_excel('source.xlsx', dictionary, 'ModelA', 'export.xlsx', 'apply');
    assert(summary.Added == 34 && summary.Removed == 0 && summary.Saved);
    dd = Simulink.dictionary.archdata.open(dictionary);
    bus = getInterface(dd, 'BusA');
    names = string({bus.Elements.Name});
    assert(any(names == 'Shared') && any(names == 'New35') && ~any(names == 'Old'));
    elem = getElement(bus, 'Keep01');
    assert(strcmp(elem.Type.DataType, 'uint8'), 'Property differences must remain report-only.');
    other = getInterface(dd, 'BusB');
    assert(isequal(string({other.Elements.Name}), "Safe"));
    close(dd);
    clear dictCleanup;

    % Direct reads must observe Apply immediately, without a workbook snapshot.
    [~, summary] = evalc('sync_bus_interfaces_from_excel(''source.xlsx'', dictionary, ''ModelA'', ''export.xlsx'', ''preview'')');
    assert(summary.ToAdd == 0 && summary.ToRemove == 0 && summary.MetadataMismatch == 25);
    assert(height(summary.Changes) == 25 && ~summary.Saved);
    for k = 2:26, source{k, 3} = 'uint8'; end
    writecell(source, 'source.xlsx', 'Sheet', 'ModelA');
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
    assert(report.Saved && report.ReferencedSkipped == 1 && report.OutOfScope == 0);
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
    assert(isDirty(dd) && any(strcmp(report.Changes.Interface, 'Bus.UserUnsaved')));
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
    rows = {'Bus', 'Element', 'DataType'; 'Selected', 'Keep', 'uint8'; ...
        'Selected', 'AddA', 'double'; 'Selected', 'AddB', 'single'};
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
    invalid.SelectedChanges = report.Changes(strcmp(report.Changes.Action, 'PROPERTY_DIFF'), :);
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
