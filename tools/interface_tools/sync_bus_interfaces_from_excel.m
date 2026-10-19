function summary = sync_bus_interfaces_from_excel(xlsxFile, slddFile, selectedSheets, exportXlsxFile, mode)
%SYNC_BUS_INTERFACES_FROM_EXCEL Compare 2 XLSX files before modifying SLDD.
% Version: 1.5.0 (Interface tools bundle).
%
% MATLAB R2024b. Writes to ARCHITECTURAL DATA, never to Design Data.
% Returns summary.Changes: complete Action/Interface/Property/SourceValue/TargetValue table.
% Standalone backend; requires only the project sldd2excel_main exporter.
%
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile)
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile, "HVBat")
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile, ["HVBat","LVS"])
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile, "all", exportXlsx)
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile, "all", exportXlsx, "preview")
%
% Workflow:
%   1) Run sldd2excel_main (must be on MATLAB path / callable with NO args).
%   2) Read SOURCE XLSX: Bus, Element, DataType, Dim, Unit, Description.
%   3) Read EXPORTED XLSX: BusElement sheet: Port, Element, DataType, etc.
%   4) Compare (Bus, Element) pairs IN MEMORY; do not open SLDD yet.
%   5) Only if there are additions/deletions: open Architectural Data ONCE,
%      add missing elements and remove extra elements in the selected buses.
%      No full interface deletion; no modifications to existing properties.
%   6) Save only when changes were successfully applied.
%
% NOTES / SAFETY:
%   - All valid source rows are included regardless of Status.
%   - A selected sheet identifies the affected buses. For those buses,
%     expected elements are collected from ALL source sheets, protecting
%     elements shared across sheets from accidental deletion.
%   - Buses absent from the selected sheets are NEVER deleted/changed.
%   - Referenced SLDD interfaces are NEVER changed by this function.
%   - Differences in existing element DataType/Dim/Unit/Description are
%     printed as warnings only; these do not trigger SLDD writes.
%   - "preview" computes and prints the plan without opening SLDD for edits.
%   - Export XLSX is deleted BEFORE running sldd2excel_main to avoid stale
%     comparison; close that workbook in Excel beforehand.
%   - sldd2excel_main must export the SAME dictionary passed as slddFile.
%     If it takes arguments, adapt runSlddExporter() below accordingly.
%
% MathWorks references (API available since R2023b):
%   https://www.mathworks.com/help/simulink/slref/adddatainterface.html
%   https://www.mathworks.com/help/simulink/slref/removeinterface.html
%   https://www.mathworks.com/help/simulink/slref/datainterface.simulink.dictionary.archdata.removeelement.html
%   https://www.mathworks.com/help/simulink/slref/simulink.dictionary.archdata.dataelement.html
%
    if nargin < 3 || isempty(selectedSheets), selectedSheets = "all"; end
    if nargin < 4, exportXlsxFile = ""; end
    if nargin < 5 || isempty(mode), mode = "apply"; end

    mode = lower(strtrim(string(mode)));
    if ~isscalar(mode) || ~ismember(mode, ["apply", "preview"])
        error('mode must be "apply" or "preview".');
    end

    % Helps detect an older copy of this tool earlier on MATLAB's path.
    fprintf('[TOOL] sync_bus_interfaces_from_excel v1.5.0\n');
    fprintf('[TOOL PATH] %s.m\n', mfilename('fullpath'));

    xlsxFile = existingFullPath(xlsxFile, 'Source XLSX');
    slddFile = existingFullPath(slddFile, 'SLDD');
    if strlength(string(exportXlsxFile)) == 0
        exportXlsxFile = locateExportFile(slddFile);
    else
        exportXlsxFile = makeAbsolutePath(exportXlsxFile);
    end
    if strcmpi(xlsxFile, exportXlsxFile)
        error('Source XLSX and export XLSX cannot be the same file.');
    end

    sourceSheets = cellstr(sheetnames(xlsxFile));
    targetSheets = resolveSheets(selectedSheets, sourceSheets);

    % Read expected rows before exporting; fail early on invalid source.
    [expected, selectedBuses] = readSourceWorkbook(xlsxFile, sourceSheets, targetSheets);

    summary = struct('Sheets', numel(targetSheets), 'Buses', numel(keys(selectedBuses)), ...
        'Compared', 0, 'ToAdd', 0, 'ToRemove', 0, 'MetadataMismatch', 0, ...
        'Added', 0, 'Removed', 0, 'NewInterfaces', 0, 'ReferencedSkipped', 0, ...
        'Saved', false);
    summary.Changes = cell2table(cell(0, 5), 'VariableNames', ...
        {'Action', 'Interface', 'Property', 'SourceValue', 'TargetValue'});

    if selectedBuses.Count == 0
        fprintf('[NO SCOPE] No valid Bus/Element entries in selected sheets.\n');
        return;
    end

    fprintf('[SOURCE] %s\n', xlsxFile);
    fprintf('[SHEETS] %s\n', strjoin(targetSheets, ', '));

    % Force freshly generated XLSX: never compare against yesterday's export.
    fprintf('[EXPORT] Running sldd2excel_main ...\n');
    if isfile(exportXlsxFile)
        delete(exportXlsxFile);
    end
    runSlddExporter();
    if ~isfile(exportXlsxFile)
        error(['sldd2excel_main did not generate the expected output: %s\n' ...
               'Pass the actual output path as the 4th argument if different.'], ...
               exportXlsxFile);
    end

    actual = readExportWorkbook(exportXlsxFile);
    [addKeys, removeKeys, metadataDiff, compared, changes] = compareWorkbooks(expected, actual, selectedBuses);
    summary.Changes = cell2table(changes, 'VariableNames', summary.Changes.Properties.VariableNames);
    summary.Changes = sortrows(summary.Changes, {'Action', 'Interface', 'Property'});
    summary.Compared = compared;
    summary.ToAdd = numel(addKeys);
    summary.ToRemove = numel(removeKeys);
    summary.MetadataMismatch = numel(metadataDiff);

    fprintf('[COMPARE] %d entries in selected buses; ADD=%d, REMOVE=%d, PROPERTY_DIFF=%d\n', ...
        compared, summary.ToAdd, summary.ToRemove, summary.MetadataMismatch);
    printChanges('ADD', addKeys, expected, inf);
    printChanges('REMOVE', removeKeys, actual, inf);
    for i = 1:numel(metadataDiff)
        fprintf('  [PROPERTY_DIFF] %s\n', metadataDiff{i});
    end

    % IMPORTANT: zero SLDD edits/open calls when the XLSX keys match.
    if isempty(addKeys) && isempty(removeKeys)
        fprintf('[UNCHANGED] No Bus/Element additions or deletions. SLDD untouched.\n');
        return;
    end
    if mode == "preview"
        fprintf('[PREVIEW] Differences found, but SLDD was NOT modified.\n');
        return;
    end

    % Validate all pending additions before opening/mutating Architectural Data.
    for i = 1:numel(addKeys)
        rec = expected(addKeys{i});
        if isempty(rec.dataType)
            error('Missing DataType for %s.%s (%s). Aborted.', ...
                rec.bus, rec.element, rec.origin);
        end
        formatDimensionsForDataElement(rec.dimensions);
    end

    % An incomplete/unrelated exporter output could otherwise delete many
    % legitimate elements. Scope is always limited to source-selected buses.
    archData = Simulink.dictionary.archdata.open(slddFile);
    try
        [summary.Added, summary.Removed, summary.NewInterfaces, ...
            summary.ReferencedSkipped] = applyDifferences(archData, ...
            expected, addKeys, removeKeys);

        if summary.Added > 0 || summary.Removed > 0
            save(archData);
            summary.Saved = true;
            fprintf('[SAVED] Architectural Data -> %s\n', slddFile);
        else
            fprintf('[UNCHANGED] No editable differences in target SLDD.\n');
        end
        close(archData);
    catch ME
        % Do not save a partially modified dictionary on failure.
        try
            close(archData, 'DiscardChanges', true);
        catch
        end
        rethrow(ME);
    end
    fprintf('[DONE] Added=%d, Removed=%d, NewInterfaces=%d, ReferencedSkipped=%d\n', ...
        summary.Added, summary.Removed, summary.NewInterfaces, ...
        summary.ReferencedSkipped);
end

function runSlddExporter()
% Isolated helper: supports sldd2excel_main as a no-input script or function.
% If your exporter requires input arguments, change ONLY the next line.
    previousFolder = pwd;
    restoreFolder = onCleanup(@() cd(previousFolder)); %#ok<NASGU>
    sldd2excel_main;
end

function [expected, selectedBuses] = readSourceWorkbook(file, sheets, selectedSheets)
    expected = containers.Map('KeyType', 'char', 'ValueType', 'any');
    selectedBuses = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    for i = 1:numel(sheets)
        sheet = sheets{i};
        raw = readcell(file, 'Sheet', sheet);
        [headerRow, cols] = detectHeaders(raw, {'Bus', 'Element'}, false);
        if headerRow == 0
            if ismember(sheet, selectedSheets) && numel(selectedSheets) < numel(sheets)
                error('Selected sheet "%s" does not contain Bus/Element columns.', sheet);
            end
            continue; % Ignore notes/metadata sheets in all-sheet mode.
        end
        selected = ismember(sheet, selectedSheets);
        previousBus = '';
        for r = headerRow+1:size(raw, 1)
            bus = getText(raw, r, cols.bus);
            elem = getText(raw, r, cols.element);
            if ~isempty(bus), previousBus = bus; end
            if isempty(bus) && ~isempty(elem), bus = previousBus; end
            if isempty(bus) && isempty(elem), continue; end
            if isempty(elem), continue; end  % Bus heading, no element row.
            if ~isvarname(bus) || ~isvarname(elem)
                error('Invalid Bus/Element in source %s row %d: %s / %s', ...
                    sheet, r, bus, elem);
            end

            rec = struct('bus', bus, 'element', elem, ...
                'dataType', getText(raw, r, cols.datatype), ...
                'dimensions', getText(raw, r, cols.dimensions), ...
                'unit', getText(raw, r, cols.unit), ...
                'description', getText(raw, r, cols.description), ...
                'origin', sprintf('%s:%d', sheet, r));
            k = pairKey(bus, elem);
            if isKey(expected, k)
                other = expected(k);
                if ~strcmp(other.dataType, rec.dataType) || ...
                   ~strcmp(normalDim(other.dimensions), normalDim(rec.dimensions))
                    error(['Source conflict for %s.%s in %s and %s: ' ...
                        'DataType or Dimensions differ.'], ...
                        bus, elem, other.origin, rec.origin);
                end
            else
                expected(k) = rec;
            end
            if selected, selectedBuses(bus) = true; end
        end
    end
end

function actual = readExportWorkbook(file)
    actual = containers.Map('KeyType', 'char', 'ValueType', 'any');
    sheets = cellstr(sheetnames(file));
    ix = find(strcmpi(sheets, 'BusElement'), 1);
    if isempty(ix)
        error('Exported XLSX has no BusElement sheet: %s', file);
    end
    raw = readcell(file, 'Sheet', sheets{ix});
    [headerRow, cols] = detectHeaders(raw, {'Port', 'Element'}, true);
    if headerRow == 0
        error('Exported BusElement sheet does not contain Port/Element columns.');
    end

    previousBus = '';
    for r = headerRow+1:size(raw, 1)
        bus = getText(raw, r, cols.bus);
        elem = getText(raw, r, cols.element);
        rowType = getText(raw, r, cols.type);
        if ~isempty(rowType) && ~strcmpi(rowType, 'BusElement')
            continue;
        end
        if ~isempty(bus), previousBus = bus; end
        if isempty(bus) && ~isempty(elem), bus = previousBus; end
        if isempty(bus) && isempty(elem), continue; end
        if isempty(elem), continue; end
        if ~isvarname(bus) || ~isvarname(elem)
            error('Invalid Port/Element in exported BusElement row %d: %s / %s', ...
                r, bus, elem);
        end
        rec = struct('bus', bus, 'element', elem, ...
            'dataType', getText(raw, r, cols.datatype), ...
            'dimensions', getText(raw, r, cols.dimensions), ...
            'unit', getText(raw, r, cols.unit), ...
            'description', getText(raw, r, cols.description), ...
            'origin', sprintf('BusElement:%d', r));
        k = pairKey(bus, elem);
        if isKey(actual, k)
            error('Duplicate exported interface element: %s.%s', bus, elem);
        end
        actual(k) = rec;
    end
    if actual.Count == 0
        fprintf('[EXPORT] No BusElements found. Comparison will only propose additions.\n');
    end
end

function [addKeys, removeKeys, differences, compared, changes] = compareWorkbooks(expected, actual, scope)
    addKeys = {};
    removeKeys = {};
    differences = {};
    changes = cell(0, 5);
    compared = 0;

    sourceKeys = sort(keys(expected));
    for i = 1:numel(sourceKeys)
        k = sourceKeys{i};
        x = expected(k);
        if ~isKey(scope, x.bus), continue; end
        compared = compared + 1;
        if ~isKey(actual, k)
            addKeys{end+1} = k; %#ok<AGROW>
            changes(end+1, :) = {'ADD', [x.bus '.' x.element], '', '', ''}; %#ok<AGROW>
        else
            y = actual(k);
            fields = {'dataType', 'dimensions', 'unit', 'description'};
            for j = 1:numel(fields)
                f = fields{j};
                a = x.(f);
                b = y.(f);
                if isempty(a), continue; end % Unspecified source property.
                if strcmp(f, 'dimensions')
                    a = normalDim(a);
                    b = normalDim(b);
                end
                if ~strcmp(a, b)
                    differences{end+1} = sprintf('%s.%s [%s]: XLSX="%s", SLDD="%s"', ...
                        x.bus, x.element, f, x.(f), y.(f)); %#ok<AGROW>
                    changes(end+1, :) = {'PROPERTY_DIFF', [x.bus '.' x.element], ...
                        f, x.(f), y.(f)}; %#ok<AGROW>
                end
            end
        end
    end

    exportKeys = sort(keys(actual));
    for i = 1:numel(exportKeys)
        k = exportKeys{i};
        x = actual(k);
        if isKey(scope, x.bus) && ~isKey(expected, k)
            removeKeys{end+1} = k; %#ok<AGROW>
            changes(end+1, :) = {'REMOVE', [x.bus '.' x.element], '', '', ''}; %#ok<AGROW>
        end
    end
end

function [added, removed, newInterfaces, referencedSkipped] = applyDifferences(archData, expected, addKeys, removeKeys)
    added = 0;
    removed = 0;
    newInterfaces = 0;
    referencedSkipped = 0;

    localNames = string(getInterfaceNames(archData, 'LookInsideDictReferences', false));
    allNames = string(getInterfaceNames(archData));
    changedBuses = {};
    for i = 1:numel(addKeys)
        row = expected(addKeys{i});
        changedBuses{end+1} = row.bus; %#ok<AGROW>
    end
    % For remove-only buses use the key to recover bus name.
    for i = 1:numel(removeKeys)
        changedBuses{end+1} = getBusFromKey(removeKeys{i}); %#ok<AGROW>
    end
    changedBuses = unique(changedBuses, 'stable');

    for b = 1:numel(changedBuses)
        bus = changedBuses{b};
        busAdd = filterKeysForBus(addKeys, bus);
        busRemove = filterKeysForBus(removeKeys, bus);

        if any(strcmp(localNames, bus))
            interfaceObj = getInterface(archData, bus);
            if ~isa(interfaceObj, 'Simulink.dictionary.archdata.DataInterface')
                error('Interface "%s" is not a DataInterface; cannot sync.', bus);
            end
        elseif any(strcmp(allNames, bus))
            warning('Interface "%s" is defined in a referenced SLDD. Skipped.', bus);
            referencedSkipped = referencedSkipped + numel(busAdd) + numel(busRemove);
            continue;
        else
            if isempty(busAdd)
                % Could be stale exporter output; do not create bus just to delete.
                warning('Export lists %s, but it is not present locally. Skipping removals.', bus);
                continue;
            end
            interfaceObj = addDataInterface(archData, bus);
            newInterfaces = newInterfaces + 1;
            localNames(end+1) = string(bus); %#ok<AGROW>
            allNames(end+1) = string(bus); %#ok<AGROW>
            fprintf('  [NEW INTERFACE] %s\n', bus);
        end

        for i = 1:numel(busAdd)
            row = expected(busAdd{i});
            if isempty(row.dataType)
                error('Missing DataType for %s.%s (%s). Aborted.', ...
                    row.bus, row.element, row.origin);
            end
            if any(strcmp(string({interfaceObj.Elements.Name}), row.element))
                error('Exporter mismatch: %s.%s already exists in SLDD.', bus, row.element);
            end
            % Important: DataElement.Dimensions expects char, NOT a double.
            % Do not assign a numeric vector to elementObj.Type.Dimensions.
            dimensionsText = formatDimensionsForDataElement(row.dimensions);
            elementObj = addElement(interfaceObj, row.element);
            elementObj.Type.DataType = row.dataType;
            elementObj.Dimensions = dimensionsText;
            if ~isempty(row.unit), elementObj.Type.Unit = row.unit; end
            if ~isempty(row.description), elementObj.Description = row.description; end
            added = added + 1;
            fprintf('  [+] %s.%s\n', bus, row.element);
        end

        for i = 1:numel(busRemove)
            elemName = getElementFromKey(busRemove{i});
            if ~any(strcmp(string({interfaceObj.Elements.Name}), elemName))
                error('Exporter mismatch: %s.%s not found in target SLDD.', bus, elemName);
            end
            removeElement(interfaceObj, elemName);
            removed = removed + 1;
            fprintf('  [-] %s.%s\n', bus, elemName);
        end
    end
end

function list = filterKeysForBus(allKeys, bus)
    list = {};
    for i = 1:numel(allKeys)
        if strcmp(getBusFromKey(allKeys{i}), bus)
            list{end+1} = allKeys{i}; %#ok<AGROW>
        end
    end
end

function k = pairKey(bus, elem)
    k = [bus char(31) elem];
end

function bus = getBusFromKey(k)
    p = find(k == char(31), 1);
    bus = k(1:p-1);
end

function elem = getElementFromKey(k)
    p = find(k == char(31), 1);
    elem = k(p+1:end);
end

function printChanges(tag, changeKeys, inventory, limit)
    for i = 1:min(limit, numel(changeKeys))
        x = inventory(changeKeys{i});
        fprintf('  [%s] %s.%s\n', tag, x.bus, x.element);
    end
    if numel(changeKeys) > limit
        fprintf('  ... %d more %s entries.\n', numel(changeKeys)-limit, tag);
    end
end

function [headerRow, cols] = detectHeaders(raw, required, isExport)
    headerRow = 0;
    cols = struct('bus', [], 'element', [], 'datatype', [], ...
        'dimensions', [], 'unit', [], 'description', [], 'type', []);
    for r = 1:min(40, size(raw, 1))
        headers = strings(1, size(raw, 2));
        for c = 1:size(raw, 2)
            headers(c) = normalizeHeader(getText(raw, r, c));
        end
        ok = true;
        for j = 1:numel(required)
            if ~any(headers == normalizeHeader(required{j}))
                ok = false;
                break;
            end
        end
        if ~ok, continue; end
        headerRow = r;
        if isExport
            cols.bus = find(headers == "port", 1);
        else
            cols.bus = find(headers == "bus", 1);
        end
        cols.element = find(headers == "element", 1);
        cols.datatype = pickCol(headers, ["datatype", "datatypeelement"]);
        cols.dimensions = pickCol(headers, ["dim", "dimension", "dimensions"]);
        cols.unit = pickCol(headers, ["unit", "units"]);
        cols.description = pickCol(headers, "description");
        cols.type = pickCol(headers, "type");
        return;
    end
end

function ix = pickCol(headers, names)
    ix = find(ismember(headers, names), 1);
end

function normalized = normalizeHeader(val)
    normalized = lower(regexprep(string(val), '[\s_\-]+', ''));
end

function out = getText(raw, row, col)
    out = '';
    if isempty(col) || row > size(raw,1) || col > size(raw,2), return; end
    value = raw{row, col};
    if isempty(value), return; end
    if ischar(value)
        out = strtrim(value);
    elseif isstring(value) && isscalar(value) && ~ismissing(value)
        out = strtrim(char(value));
    elseif isnumeric(value) && isscalar(value) && isfinite(value)
        out = strtrim(num2str(value, 15));
    end
end

function normalized = normalDim(s)
% Make '[1]', '1' and '1x1' comparable (scalar element).
    normalized = strtrim(char(string(s)));
    if isempty(normalized), return; end
    try
        d = parseDimension(normalized);
        if isequal(d, [1,1]), d = 1; end
        normalized = strtrim(sprintf('%d ', d));
    catch
        normalized = lower(regexprep(normalized, '[\[\]\s,]', ''));
    end
end

function dimensionsText = formatDimensionsForDataElement(raw)
% Architectural Data's DataElement.Dimensions needs a char vector.
% Input examples: 1, '1', '[1 1]', '1x2', '[2, 3]'.
    vec = parseDimension(raw);
    if isscalar(vec)
        dimensionsText = sprintf('%d', vec);
    else
        dimensionsText = mat2str(vec);
    end
end

function vec = parseDimension(raw)
    if isempty(raw), vec = 1; return; end
    if isempty(regexp(raw, '^[\[\]0-9,\sxX]+$', 'once'))
        error('Unsupported Dimensions: %s', raw);
    end
    nums = sscanf(regexprep(raw, '[\[\],xX]', ' '), '%f').';
    if isempty(nums) || any(nums < 1) || any(nums ~= fix(nums))
        error('Dimensions must contain positive integers: %s', raw);
    end
    vec = nums;
end

function selected = resolveSheets(requested, allSheets)
    requested = cellstr(string(requested));
    if numel(requested) == 1 && strcmpi(strtrim(requested{1}), 'all')
        selected = allSheets;
    else
        selected = unique(requested, 'stable');
        for i = 1:numel(selected)
            if ~any(strcmp(allSheets, selected{i}))
                error('Sheet "%s" does not exist in the source XLSX.', selected{i});
            end
        end
    end
end

function out = existingFullPath(file, label)
    file = char(string(file));
    if ~isfile(file), error('%s not found: %s', label, file); end
    [ok, info] = fileattrib(file);
    if ~ok, error('Cannot resolve path: %s', file); end
    out = info.Name;
end

function out = makeAbsolutePath(path)
    path = char(string(path));
    if ispc
        absolute = ~isempty(regexp(path, '^([A-Za-z]:[\\/]|\\\\)', 'once'));
    else
        absolute = startsWith(path, '/');
    end
    if absolute, out = path; else, out = fullfile(pwd, path); end
end

function exported = locateExportFile(slddFile)
% Recognize EBUS_12M project root whether MATLAB starts in it or beside it.
    subpath = fullfile('06_Tool', 'interface_tools', 'common');
    roots = {pwd, fileparts(slddFile)};
    for i = 1:numel(roots)
        folder = roots{i};
        for level = 1:12
            c1 = fullfile(folder, subpath);
            c2 = fullfile(folder, 'EBUS_12M', subpath);
            if isfolder(c1)
                exported = fullfile(c1, 'sldd_interface_export.xlsx');
                return;
            end
            if isfolder(c2)
                exported = fullfile(c2, 'sldd_interface_export.xlsx');
                return;
            end
            parent = fileparts(folder);
            if strcmp(parent, folder), break; end
            folder = parent;
        end
    end
    error(['Cannot locate EBUS_12M/06_Tool/interface_tools/common. ' ...
           'Specify exportXlsxFile as the 4th argument.']);
end
