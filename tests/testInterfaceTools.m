function testInterfaceTools()
%TESTINTERFACETOOLS Exercise interface tools using temporary synthetic data.
% Requires live MATLAB/Simulink R2024a+. No production files are read or edited.
    repo = fileparts(fileparts(mfilename('fullpath')));
    toolFolder = fullfile(repo, 'tools', 'interface_tools');
    previousPath = path;
    previousFolder = pwd;
    sandbox = tempname;
    mkdir(sandbox);
    restore = onCleanup(@() local_restore(previousPath, previousFolder));
    addpath(toolFolder);
    addpath(sandbox, '-begin');
    cd(sandbox);
    mkdir('arch');
    dictionary = fullfile(sandbox, 'arch', 'test.sldd');
    dd = Simulink.dictionary.archdata.create(dictionary);
    dictCleanup = onCleanup(@() local_close(dd));
    bus = addDataInterface(dd, 'BusA');
    source = {'Bus', 'Element', 'DataType', 'Dim', 'Status', 'Parameter', 'Value'};
    actual = {'Port', 'Element', 'DataType', 'Dim'};
    for k = 1:25
        name = sprintf('Keep%02d', k);
        elem = addElement(bus, name);
        elem.Type.DataType = 'uint8';
        elem.Dimensions = '1';
        source(end+1, :) = {'BusA', name, 'double', '1', 'Accept', sprintf('pA%02d', k), k}; %#ok<AGROW>
        actual(end+1, :) = {'BusA', name, 'uint8', '1'}; %#ok<AGROW>
    end
    for k = 1:35
        source(end+1, :) = {'BusA', sprintf('New%02d', k), 'double', '1', '', '', ''}; %#ok<AGROW>
    end
    addElement(bus, 'Old');
    addElement(bus, 'Shared');
    actual(end+1, :) = {'BusA', 'Old', 'double', '1'};
    actual(end+1, :) = {'BusA', 'Shared', 'double', '1'};
    other = addDataInterface(dd, 'BusB');
    addElement(other, 'Safe');
    actual(end+1, :) = {'BusB', 'Safe', 'double', '1'};
    save(dd);
    close(dd);
    writecell(source, 'source.xlsx', 'Sheet', 'ModelA');
    sourceB = [source(1, :); {'BusA', 'Shared', 'double', '1', 'Accept', 'pShared', 9}; ...
        {'BusB', 'Safe', 'double', '1', 'Accept', 'pSafe', 10}];
    writecell(sourceB, 'source.xlsx', 'Sheet', 'ModelB');
    writecell(actual, 'snapshot.xlsx', 'Sheet', 'BusElement');
    local_write('sldd2excel_main.m', ...
        'copyfile(fullfile(pwd, ''snapshot.xlsx''), fullfile(pwd, ''export.xlsx''));');
    config = jsondecode(fileread(fullfile(toolFolder, 'interface_tools_config.json')));
    config.SourceXlsx = 'source.xlsx';
    config.ProjectRoot = ''; % Discover via the custom architecture marker.
    config.ArchitectureFolder = 'arch';
    config.SlddFile = 'arch/test.sldd';
    config.ParametersFile = 'arch/parameters.m';
    config.ExportXlsx = 'export.xlsx';
    configFile = fullfile(sandbox, 'config.json');
    local_write(configFile, jsonencode(config));
    before = local_bytes(dictionary);
    [console, summary] = evalc('sync_bus_interfaces_from_excel(''source.xlsx'', dictionary, ''ModelA'', ''export.xlsx'', ''preview'')');
    assert(summary.ToAdd == 35 && summary.ToRemove == 1 && summary.MetadataMismatch == 25);
    assert(height(summary.Changes) == 61 && ~summary.Saved);
    assert(contains(console, 'BusA.New35') && contains(console, 'BusA.Keep25'));
    assert(isequal(before, local_bytes(dictionary)), 'Preview changed the dictionary.');
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
    assert(any(strcmp(details.Data(:, 2), 'BusA.New35')));
    assert(isequal(before, local_bytes(dictionary)));
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
    assert(summary.Added == 35 && summary.Removed == 1 && summary.Saved);
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

    % Refresh the synthetic exporter snapshot after Apply. Metadata-only plans
    % and empty plans must still return a complete, correctly shaped table.
    actual = actual(~strcmp(actual(:, 2), 'Old'), :);
    for k = 1:35
        actual(end+1, :) = {'BusA', sprintf('New%02d', k), 'double', '1'}; %#ok<AGROW>
    end
    delete('snapshot.xlsx');
    writecell(actual, 'snapshot.xlsx', 'Sheet', 'BusElement');
    [~, summary] = evalc('sync_bus_interfaces_from_excel(''source.xlsx'', dictionary, ''ModelA'', ''export.xlsx'', ''preview'')');
    assert(summary.ToAdd == 0 && summary.ToRemove == 0 && summary.MetadataMismatch == 25);
    assert(height(summary.Changes) == 25 && ~summary.Saved);
    for k = 2:26, source{k, 3} = 'uint8'; end
    writecell(source, 'source.xlsx', 'Sheet', 'ModelA');
    [~, summary] = evalc('sync_bus_interfaces_from_excel(''source.xlsx'', dictionary, ''ModelA'', ''export.xlsx'', ''preview'')');
    assert(isempty(summary.Changes) && width(summary.Changes) == 5 && ~summary.Saved);

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
    assert(isempty(details.Data) && size(details.Data, 2) == 5);
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
    fprintf('PASS: CLI preview/apply, complete GUI preview, all-sheet parameters, config paths/validation.\n');
    fprintf('Synthetic fixtures and GUI screenshot: %s\n', sandbox);
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

function local_restore(previousPath, previousFolder)
    cd(previousFolder);
    path(previousPath);
    clear sldd2excel_main;
end
