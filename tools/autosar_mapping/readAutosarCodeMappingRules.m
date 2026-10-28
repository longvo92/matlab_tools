function rules = readAutosarCodeMappingRules(source)
%READAUTOSARCODEMAPPINGRULES Read property-based Code Mappings CSV (v1.3.1).
%   Columns: Model, Category, Element, Property, Value. Element is an exact
%   exported identifier, '*' for the category, 'type:StaticMemory' for a
%   required current mapping type, or 'type?:StaticMemory' for an optional
%   type. Empty Value explicitly clears a value.
%   SOURCE can also be a table. No MATLAB expressions are evaluated.
%   See configureAutosarMapping and exportAutosarMapping. MATLAB R2024a+.
    names = {'Model', 'Category', 'Element', 'Property', 'Value'};
    if istable(source)
        rules = source;
    else
        validateattributes(source, {'char', 'string'}, {'scalartext'});
        if ~isfile(source)
            resolved = which(char(source));
            if ~isempty(resolved), source = resolved; end
        end
        [~, ~, ext] = fileparts(source);
        if ~strcmpi(ext, '.csv') || ~isfile(source)
            error('AutosarMapping:ConfigFile', 'Expected an existing CSV file: %s', source);
        end
        options = detectImportOptions(source, 'FileType', 'text', 'Delimiter', ',', ...
            'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');
        options = setvartype(options, options.VariableNames, 'string');
        options.VariableNamesLine = 1;
        options.DataLines = [2 Inf];
        options.ExtraColumnsRule = 'error';
        rules = readtable(source, options);
    end
    if isempty(rules) || ~isequal(sort(rules.Properties.VariableNames), sort(names))
        error('AutosarMapping:Schema', 'Expected nonempty Model,Category,Element,Property,Value columns.');
    end
    rules = rules(:, names);
    for k = 1:numel(names)
        value = string(rules.(names{k}));
        if size(value, 2) ~= 1
            error('AutosarMapping:Schema', 'Each field must be a scalar per row.');
        end
        if k == 5
            value(ismissing(value)) = "";
        elseif any(ismissing(value) | strlength(strtrim(value)) == 0)
            error('AutosarMapping:Schema', '%s cannot be empty.', names{k});
        end
        if k ~= 5, value = strtrim(value); end
        rules.(names{k}) = value;
    end
    categories = autosarMapping.CodeMappingAdapter.categories();
    for k = 1:height(rules)
        if ~isvarname(char(rules.Model(k)))
            error('AutosarMapping:ModelName', 'Use a bare MATLAB model name.');
        end
        index = find(strcmpi(rules.Category(k), categories));
        if isempty(index), error('AutosarMapping:Category', 'Unknown category: %s', rules.Category(k)); end
        rules.Category(k) = categories(index);
        if isempty(regexp(char(rules.Property(k)), '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
            error('AutosarMapping:Property', 'Invalid property: %s', rules.Property(k));
        end
    end
    if height(unique(rules(:, 1:4), 'rows')) ~= height(rules)
        error('AutosarMapping:DuplicateRule', 'Each model/category/element/property may occur once.');
    end
end
