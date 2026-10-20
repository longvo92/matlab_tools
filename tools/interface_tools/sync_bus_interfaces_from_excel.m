function summary = sync_bus_interfaces_from_excel(xlsxFile, slddFile, selectedSheets, modeOrLegacyExport, mode)
%SYNC_BUS_INTERFACES_FROM_EXCEL Compare Excel with SLDD Data Interfaces directly.
% Version: 1.8.0 (Interface tools bundle).
%
% Requires MATLAB/Simulink R2024a+. Reads ARCHITECTURAL DATA Data Interfaces.
% Returns summary.Changes: complete Action/Interface/Property/SourceValue/TargetValue table.
% summary.Interfaces inventories Data Interfaces in the selected Excel buses only.
% summary.Selectable marks editable ADD/REMOVE rows in summary.Changes.
% Standalone backend; no exporter or intermediate workbook is needed.
%
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile)
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile, "HVBat")
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile, ["HVBat","LVS"])
%   summary = sync_bus_interfaces_from_excel(sourceXlsx, slddFile, "all", "preview")
%   sync_bus_interfaces_from_excel(sourceXlsx, slddFile, "HVBat", "apply")
%   opts = struct('Mode', 'apply', 'SelectedChanges', preview.Changes(rows, :), ...
%       'ExpectedSnapshot', {preview.Snapshot});
%   summary = sync_bus_interfaces_from_excel(sourceXlsx, slddFile, "all", opts)
% opts.Mode defaults to preview. SelectedChanges is an Action/Interface table;
% an empty selection applies nothing. Omit it to retain legacy apply-all behavior.
% ExpectedSnapshot rejects changes to compared data since Preview.
% Legacy (source, sldd, sheets, exportXlsx, mode) calls remain accepted;
% the export path is ignored and never read, written, or deleted.
%
% Reads Bus, Element, Status, DataType, Dim, Unit, Description from the source XLSX,
% and matching Data Interfaces from the specified SLDD and its references.
% Service/Physical Interfaces and Design Data buses are excluded.
% Compares in memory, then saves only successfully applied element changes.
%
% NOTES / SAFETY:
%   - Only Status=remove (case-insensitive, trimmed) proposes a deletion.
%     Missing/blank/other Status values never authorize removal. Elements
%     absent from Excel are kept. Remove rows never propose additions.
%   - Conflicting remove/keep rows for the same Bus.Element abort comparison.
%   - A selected sheet identifies the affected buses. For those buses,
%     expected elements are collected from ALL source sheets, protecting
%     elements shared across sheets from accidental deletion.
%   - Buses absent from the selected sheets are NEVER deleted/changed.
%     Buses not named in Excel are ignored, including in all-sheet mode.
%   - Empty Data Interfaces are inventoried but never removed.
%   - Referenced SLDD interfaces are NEVER changed by this function.
%   - Differences in existing element DataType/Dim/Unit/Description are
%     printed as warnings only; these do not trigger SLDD writes.
%   - "preview" never edits or saves the dictionary.
%   - Apply refuses dictionaries with unsaved changes, protecting user edits.
%
% MathWorks references (API available since R2023b):
%   https://www.mathworks.com/help/simulink/slref/adddatainterface.html
%   https://www.mathworks.com/help/simulink/slref/removeinterface.html
%   https://www.mathworks.com/help/simulink/slref/datainterface.simulink.dictionary.archdata.removeelement.html
%   https://www.mathworks.com/help/simulink/slref/simulink.dictionary.archdata.dataelement.html
%
    if nargin < 3 || isempty(selectedSheets), selectedSheets = "all"; end
    if nargin < 4, modeOrLegacyExport = ""; end
    if nargin < 5 || isempty(mode), mode = "apply"; end
    opts = struct();
    if isstruct(modeOrLegacyExport)
        opts = modeOrLegacyExport;
        validateattributes(opts, {'struct'}, {'scalar'});
        mode = 'preview';
        if isfield(opts, 'Mode'), mode = opts.Mode; end
    elseif nargin < 5 && isscalar(string(modeOrLegacyExport)) && ...
            ismember(lower(string(modeOrLegacyExport)), ["apply", "preview"])
        mode = modeOrLegacyExport;
    end

    mode = lower(strtrim(string(mode)));
    if ~isscalar(mode) || ~ismember(mode, ["apply", "preview"])
        error('mode must be "apply" or "preview".');
    end

    % Helps detect an older copy of this tool earlier on MATLAB's path.
    fprintf('[TOOL] sync_bus_interfaces_from_excel v1.8.0\n');
    fprintf('[TOOL PATH] %s.m\n', mfilename('fullpath'));

    xlsxFile = existingFullPath(xlsxFile, 'Source XLSX');
    slddFile = existingFullPath(slddFile, 'SLDD');

    sourceSheets = cellstr(sheetnames(xlsxFile));
    targetSheets = resolveSheets(selectedSheets, sourceSheets);

    % Read expected rows first; fail early on invalid source.
    [expected, selectedBuses] = readSourceWorkbook(xlsxFile, sourceSheets, targetSheets);

    summary = struct('Sheets', numel(targetSheets), 'Buses', numel(keys(selectedBuses)), ...
        'Compared', 0, 'ToAdd', 0, 'ToRemove', 0, 'MetadataMismatch', 0, ...
        'Added', 0, 'Removed', 0, 'NewInterfaces', 0, 'ReferencedSkipped', 0, ...
        'OutOfScope', 0, 'SelectedAdd', 0, 'SelectedRemove', 0, 'Saved', false);
    summary.Changes = cell2table(cell(0, 5), 'VariableNames', ...
        {'Action', 'Interface', 'Property', 'SourceValue', 'TargetValue'});

    fprintf('[SOURCE] %s\n', xlsxFile);
    fprintf('[SHEETS] %s\n', strjoin(targetSheets, ', '));

    wasOpen = any(strcmpi(Simulink.data.dictionary.getOpenDictionaryPaths(), slddFile));
    archData = Simulink.dictionary.archdata.open(slddFile);
    cleanup = onCleanup(@() local_closeDictionary(archData, wasOpen));
    [actual, summary.Interfaces] = local_readDataInterfaces(archData, selectedBuses);
    fprintf('[SLDD] %s: %d Data Interfaces, %d elements\n', ...
        slddFile, height(summary.Interfaces), actual.Count);
    scope = selectedBuses;
    [addKeys, removeKeys, metadataDiff, compared, changes] = compareInterfaces(expected, actual, scope);
    summary.Changes = cell2table(changes, 'VariableNames', summary.Changes.Properties.VariableNames);
    summary.Changes = sortrows(summary.Changes, {'Action', 'Interface', 'Property'});
    summary.Compared = compared;
    summary.ToAdd = numel(addKeys);
    summary.ToRemove = numel(removeKeys);
    summary.MetadataMismatch = numel(metadataDiff);
    referenced = summary.Interfaces.Name(summary.Interfaces.Referenced);
    summary.Selectable = ismember(string(summary.Changes.Action), ["ADD", "REMOVE"]);
    for i = 1:height(summary.Changes)
        bus = extractBefore(string(summary.Changes.Interface{i}), '.');
        summary.Selectable(i) = summary.Selectable(i) && ~ismember(char(bus), referenced);
    end
    summary.Snapshot = local_createSnapshot(expected, actual, scope);
    if isfield(opts, 'ExpectedSnapshot') && ~isequaln(opts.ExpectedSnapshot, summary.Snapshot)
        error('InterfaceTools:StalePreview', 'Compared Excel or SLDD data changed. Run Preview again.');
    end

    fprintf('[COMPARE] %d entries in selected buses; ADD=%d, REMOVE=%d, PROPERTY_DIFF=%d\n', ...
        compared, summary.ToAdd, summary.ToRemove, summary.MetadataMismatch);
    printChanges('ADD', addKeys, expected, inf);
    printChanges('REMOVE', removeKeys, actual, inf);
    for i = 1:numel(metadataDiff)
        fprintf('  [PROPERTY_DIFF] %s\n', metadataDiff{i});
    end

    % Matching keys and metadata-only differences never trigger writes.
    if isempty(addKeys) && isempty(removeKeys)
        fprintf('[UNCHANGED] No Bus/Element additions or deletions. SLDD untouched.\n');
        return;
    end
    if mode == "preview"
        fprintf('[PREVIEW] Differences found, but SLDD was NOT modified.\n');
        return;
    end

    if isfield(opts, 'SelectedChanges')
        [addKeys, removeKeys] = local_selectChanges(opts.SelectedChanges, summary.Changes, summary.Selectable);
    end
    summary.SelectedAdd = numel(addKeys);
    summary.SelectedRemove = numel(removeKeys);
    if isempty(addKeys) && isempty(removeKeys)
        fprintf('[UNCHANGED] No changes selected.\n');
        return;
    end
    checked = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    local_requireCleanDictionary(slddFile, checked);

    % Validate all pending additions before mutating Architectural Data.
    for i = 1:numel(addKeys)
        rec = expected(addKeys{i});
        if isempty(rec.dataType)
            error('Missing DataType for %s.%s (%s). Aborted.', ...
                rec.bus, rec.element, rec.origin);
        end
        formatDimensionsForDataElement(rec.dimensions);
    end

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
    catch ME
        % Do not save a partially modified dictionary on failure.
        try
            discardChanges(archData);
        catch
        end
        rethrow(ME);
    end
    fprintf('[DONE] Added=%d, Removed=%d, NewInterfaces=%d, ReferencedSkipped=%d\n', ...
        summary.Added, summary.Removed, summary.NewInterfaces, ...
        summary.ReferencedSkipped);
end

function local_closeDictionary(archData, wasOpen)
    if ~wasOpen, close(archData); end
end

function local_requireCleanDictionary(file, checked)
% Native save/discard includes references: protect pending edits in all of them.
    dictionary = Simulink.data.dictionary.open(file);
    if isKey(checked, dictionary.filepath), return; end
    checked(dictionary.filepath) = true;
    if dictionary.HasUnsavedChanges
        error('InterfaceTools:DirtyDictionary', ...
            'SLDD has unsaved changes: %s. Save or discard them before applying interface changes.', ...
            dictionary.filepath);
    end
    references = dictionary.DataSources;
    for i = 1:numel(references)
        local_requireCleanDictionary(references{i}, checked);
    end
end

function [expected, selectedBuses] = readSourceWorkbook(file, sheets, selectedSheets)
    expected = containers.Map('KeyType', 'char', 'ValueType', 'any');
    selectedBuses = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    for i = 1:numel(sheets)
        sheet = sheets{i};
        raw = readcell(file, 'Sheet', sheet);
        [headerRow, cols] = detectHeaders(raw, {'Bus', 'Element'});
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
                'removeRequested', strcmpi(getText(raw, r, cols.status), 'remove'), ...
                'origin', sprintf('%s:%d', sheet, r));
            k = pairKey(bus, elem);
            if isKey(expected, k)
                other = expected(k);
                if other.removeRequested ~= rec.removeRequested
                    error('InterfaceTools:SourceConflict', ...
                        'Conflicting remove/keep Status for %s.%s in %s and %s.', ...
                        bus, elem, other.origin, rec.origin);
                end
                if ~rec.removeRequested && (~strcmp(other.dataType, rec.dataType) || ...
                   ~strcmp(normalDim(other.dimensions), normalDim(rec.dimensions)))
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

function [actual, inventory] = local_readDataInterfaces(archData, scope)
    actual = containers.Map('KeyType', 'char', 'ValueType', 'any');
    rows = cell(0, 3);
    names = sort(getInterfaceNames(archData));
    localNames = getInterfaceNames(archData, 'LookInsideDictReferences', false);
    for i = 1:numel(names)
        if ~isKey(scope, names{i}), continue; end
        interfaceObj = getInterface(archData, names{i});
        if ~isa(interfaceObj, 'Simulink.dictionary.archdata.DataInterface'), continue; end
        elements = interfaceObj.Elements;
        rows(end+1, :) = {names{i}, numel(elements), ~ismember(names{i}, localNames)}; %#ok<AGROW>
        for j = 1:numel(elements)
            elementObj = elements(j);
            typeObj = elementObj.Type;
            if isa(typeObj, 'Simulink.dictionary.archdata.DataInterface') || ...
                    isa(typeObj, 'Simulink.dictionary.archdata.StructType')
                dataType = ['Bus: ' typeObj.Name];
                unit = '';
            else
                dataType = char(typeObj.DataType);
                unit = char(typeObj.Unit);
            end
            rec = struct('bus', names{i}, 'element', elementObj.Name, ...
                'dataType', strtrim(dataType), ...
                'dimensions', strtrim(char(elementObj.Dimensions)), ...
                'unit', strtrim(unit), 'description', strtrim(char(elementObj.Description)), ...
                'removeRequested', false, ...
                'origin', names{i});
            actual(pairKey(rec.bus, rec.element)) = rec;
        end
    end
    inventory = table(rows(:, 1), reshape(cell2mat(rows(:, 2)), [], 1), ...
        reshape(logical(cell2mat(rows(:, 3))), [], 1), ...
        'VariableNames', {'Name', 'ElementCount', 'Referenced'});
end

function snapshot = local_createSnapshot(expected, actual, scope)
    snapshot = cell(0, 8);
    inventories = {expected, actual};
    for side = 1:2
        inventory = inventories{side};
        names = sort(keys(inventory));
        for i = 1:numel(names)
            row = inventory(names{i});
            if ~isKey(scope, row.bus), continue; end
            snapshot(end+1, :) = {side, row.bus, row.element, row.dataType, ...
                row.dimensions, row.unit, row.description, row.removeRequested}; %#ok<AGROW>
        end
    end
end

function [addKeys, removeKeys] = local_selectChanges(selected, changes, selectable)
    if ~istable(selected) || ~all(ismember({'Action', 'Interface'}, selected.Properties.VariableNames))
        error('InterfaceTools:Selection', 'SelectedChanges must be a table with Action and Interface columns.');
    end
    chosen = string(selected.Action) + ":" + string(selected.Interface);
    available = string(changes.Action) + ":" + string(changes.Interface);
    if any(~ismember(chosen, available(selectable)))
        error('InterfaceTools:Selection', 'Select only current, editable ADD/REMOVE rows. Run Preview again.');
    end
    addKeys = {};
    removeKeys = {};
    for i = 1:height(changes)
        if ~ismember(available(i), chosen), continue; end
        parts = split(string(changes.Interface{i}), '.');
        key = pairKey(char(parts(1)), char(parts(2)));
        if strcmp(changes.Action{i}, 'ADD')
            addKeys{end+1} = key; %#ok<AGROW>
        else
            removeKeys{end+1} = key; %#ok<AGROW>
        end
    end
end

function [addKeys, removeKeys, differences, compared, changes] = compareInterfaces(expected, actual, scope)
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
        if x.removeRequested
            if isKey(actual, k)
                removeKeys{end+1} = k; %#ok<AGROW>
                changes(end+1, :) = {'REMOVE', [x.bus '.' x.element], '', '', ''}; %#ok<AGROW>
            end
            continue; % Already absent: do not add or compare deletion-row metadata.
        end
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
                error('InterfaceTools:MissingInterface', 'Data Interface %s disappeared during sync.', bus);
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
                error('Dictionary mismatch: %s.%s already exists in SLDD.', bus, row.element);
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
                error('Dictionary mismatch: %s.%s not found in target SLDD.', bus, elemName);
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

function [headerRow, cols] = detectHeaders(raw, required)
    headerRow = 0;
    cols = struct('bus', [], 'element', [], 'datatype', [], ...
        'dimensions', [], 'unit', [], 'description', [], 'status', []);
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
        cols.bus = find(headers == "bus", 1);
        cols.element = find(headers == "element", 1);
        cols.datatype = pickCol(headers, ["datatype", "datatypeelement"]);
        cols.dimensions = pickCol(headers, ["dim", "dimension", "dimensions"]);
        cols.unit = pickCol(headers, ["unit", "units"]);
        cols.description = pickCol(headers, "description");
        cols.status = pickCol(headers, "status");
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
