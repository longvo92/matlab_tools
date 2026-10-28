function rules = exportAutosarMapping(model, filename)
%EXPORTAUTOSARMAPPING Export readable AUTOSAR Code Mappings (version 1.3.1).
%   RULES = exportAutosarMapping(MODEL) returns property rules for the loaded
%   AUTOSAR Classic model. [] uses the current model. No model changes occur.
%   exportAutosarMapping(MODEL, CSVFILE) writes a new UTF-8 CSV. Existing files
%   are never overwritten. Edit the exported rules and pass them to
%   configureAutosarMapping. Requires MATLAB/Simulink R2024a+, AUTOSAR Blockset.
%   Unsupported, inapplicable and unavailable-release properties are excluded.
%   Inactive NvBlockNeeds fields are omitted when NeedsNVRAMAccess=false.
    adapter = autosarMapping.CodeMappingAdapter(model);
    records = adapter.inventory();
    rules = array2table(strings(0, 5), 'VariableNames', {'Model', 'Category', 'Element', 'Property', 'Value'});
    for k = 1:numel(records)
        values = adapter.read(records(k));
        for name = string(fieldnames(values))'
            rules(end + 1, :) = {adapter.Model, records(k).Category, records(k).Element, name, values.(char(name))}; %#ok<AGROW>
        end
    end
    if nargin >= 2
        validateattributes(filename, {'char', 'string'}, {'scalartext'});
        [~, ~, ext] = fileparts(filename);
        if ~strcmpi(ext, '.csv'), error('AutosarMapping:ConfigFile', 'Export requires a .csv file.'); end
        if isfile(filename), error('AutosarMapping:FileExists', 'File already exists: %s', filename); end
        writetable(rules, filename, 'Encoding', 'UTF-8');
    end
end
