function matches = calibrationMatches(records, config)
%CALIBRATIONMATCHES Classify parameter names using global regexp (v1.2.0).
    matches = array2table(strings(0, 3), 'VariableNames', {'Category', 'Element', 'Pattern'});
    if ~config.Enabled || isempty(config.IncludePatterns), return; end
    for k = 1:numel(records)
        record = records(k);
        if ~any(record.Category == ["ModelParameters", "ModelParameterArguments"]), continue; end
        included = local_match(record.Element, config.IncludePatterns, config.IgnoreCase);
        if included == "" || local_match(record.Element, config.ExcludePatterns, config.IgnoreCase) ~= "", continue; end
        matches(end + 1, :) = {record.Category, record.Element, included}; %#ok<AGROW>
    end
end

function pattern = local_match(name, patterns, ignoreCase)
    pattern = "";
    for candidate = patterns
        if ignoreCase, result = regexpi(char(name), char(candidate), 'once');
        else, result = regexp(char(name), char(candidate), 'once');
        end
        if ~isempty(result), pattern = candidate; return; end
    end
end
