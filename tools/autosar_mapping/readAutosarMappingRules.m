function rules = readAutosarMappingRules(source)
%READAUTOSARMAPPINGRULES Read per-model SwAddrMethod rules (version 1.3.3).
%   RULES = readAutosarMappingRules(CSVFILE) reads a UTF-8 comma-delimited file
%   with exactly these columns: Model, Type, SwAddrMethod. SOURCE can also be
%   a table with the same columns. Whitespace is trimmed; Type ignores case.
%   Each (Model, Type) must occur once, even if duplicate values agree.
%   Relative files resolve in the current folder, then on the MATLAB path.
%
%   Types: Runnable, RunnableInternalData, ConstantMemory, SharedParameter,
%   StaticMemory, ArTypedPerInstanceMemory. Models use exact, case-sensitive
%   names without folders/extensions. SwAddrMethod uses a unique SHORT-NAME.
%
%   Example: rules = readAutosarMappingRules('legacy_mapping.csv');
%   New configurations use the five-column autosar_code_mapping.csv schema.
%   Dependencies: MATLAB R2024a or later. No external CSV/YAML library.

    columns = {'Model', 'Type', 'SwAddrMethod'};
    if istable(source)
        rules = source;
    else
        validateattributes(source, {'char', 'string'}, {'scalartext'}, mfilename, 'source');
        if ~isfile(source)
            resolved = which(char(source));
            if ~isempty(resolved), source = resolved; end
        end
        [~, ~, extension] = fileparts(source);
        if ~strcmpi(extension, '.csv') || ~isfile(source)
            error('AutosarMapping:ConfigFile', 'Expected an existing .csv file: %s', source);
        end
        options = detectImportOptions(source, 'FileType', 'text', 'Delimiter', ',', ...
            'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');
        options = setvartype(options, options.VariableNames, 'string');
        options.VariableNamesLine = 1;
        options.DataLines = [2 Inf];
        options.ExtraColumnsRule = 'error';
        options.ImportErrorRule = 'error';
        rules = readtable(source, options);
    end
    if ~isequal(sort(rules.Properties.VariableNames), sort(columns)) || isempty(rules)
        error('AutosarMapping:Schema', ...
            'Rules must contain rows and exactly these columns: Model, Type, SwAddrMethod.');
    end
    rules = rules(:, columns);
    for k = 1:numel(columns)
        name = columns{k};
        value = string(rules.(name));
        if size(value, 2) ~= 1 || any(ismissing(value) | strlength(strtrim(value)) == 0)
            error('AutosarMapping:Schema', 'Column %s must contain one nonempty value per row.', name);
        end
        rules.(name) = strtrim(value);
    end
    types = ["Runnable", "RunnableInternalData", "ConstantMemory", ...
        "SharedParameter", "StaticMemory", "ArTypedPerInstanceMemory"];
    for k = 1:height(rules)
        if ~isvarname(char(rules.Model(k)))
            error('AutosarMapping:ModelName', 'Use a bare MATLAB model name: %s', rules.Model(k));
        end
        index = find(strcmpi(rules.Type(k), types));
        if isempty(index)
            error('AutosarMapping:Type', 'Unsupported mapping type: %s', rules.Type(k));
        end
        rules.Type(k) = types(index);
        if isempty(regexp(char(rules.SwAddrMethod(k)), '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
            error('AutosarMapping:MethodName', ...
                'Use an AUTOSAR SwAddrMethod SHORT-NAME: %s', rules.SwAddrMethod(k));
        end
    end
    keys = rules.Model + "/" + rules.Type;
    if numel(unique(keys)) ~= height(rules)
        error('AutosarMapping:DuplicateRule', 'Each (Model, Type) must have exactly one rule.');
    end
end
