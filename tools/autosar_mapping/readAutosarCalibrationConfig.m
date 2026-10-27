function config = readAutosarCalibrationConfig(filename)
%READAUTOSARCALIBRATIONCONFIG Load global calibration naming rules (v1.3.0).
%   CONFIG = readAutosarCalibrationConfig() loads the adjacent
%   autosar_calibration_config.json, shared across all models and both CLI/GUI.
%   Pass a JSON path to use another global file, or '' to disable for a call.
%   IncludePatterns/ExcludePatterns are MATLAB regexp patterns. A parameter
%   matches any include and no exclude. Empty IncludePatterns matches nothing.
%   IgnoreCase controls regexpi versus regexp. Patterns are validated on read.
%   PreserveExplicitMappings keeps existing non-Auto parameter roles. Matching
%   Auto parameters use ModelParameterMapping or ArgumentMapping; matching
%   parameters receive SwCalibrationAccess unless overridden by a model CSV.
%   Requires MATLAB R2024a+. No config values are evaluated as MATLAB code.
    config = struct('Enabled', true, 'IncludePatterns', strings(1, 0), ...
        'ExcludePatterns', strings(1, 0), 'IgnoreCase', false, ...
        'PreserveExplicitMappings', true, 'ModelParameterMapping', "SharedParameter", ...
        'ArgumentMapping', "PerInstanceParameter", 'SwCalibrationAccess', "ReadWrite");
    if nargin == 0
        filename = fullfile(fileparts(mfilename('fullpath')), 'autosar_calibration_config.json');
    end
    validateattributes(filename, {'char', 'string'}, {'scalartext'});
    if strlength(string(filename)) == 0
        config.Enabled = false;
        config.File = "";
        return;
    end
    if ~isfile(filename)
        resolved = which(char(filename));
        if ~isempty(resolved), filename = resolved; end
    end
    if ~isfile(filename), error('AutosarMapping:CalibrationConfig', 'Calibration JSON not found: %s', filename); end
    value = jsondecode(fileread(filename));
    if ~isstruct(value) || ~isscalar(value) || any(~ismember(fieldnames(value), fieldnames(config)))
        error('AutosarMapping:CalibrationConfig', 'Calibration config must be a JSON object with known fields.');
    end
    for name = string(fieldnames(value))', config.(char(name)) = value.(char(name)); end
    for name = ["Enabled", "IgnoreCase", "PreserveExplicitMappings"]
        if ~islogical(config.(char(name))) || ~isscalar(config.(char(name)))
            error('AutosarMapping:CalibrationConfig', '%s must be a JSON boolean.', name);
        end
    end
    for name = ["IncludePatterns", "ExcludePatterns"]
        patterns = config.(char(name));
        if isempty(patterns)
            patterns = strings(1, 0);
        elseif ischar(patterns) && isrow(patterns)
            patterns = string(patterns);
        elseif isstring(patterns) || iscellstr(patterns)
            patterns = reshape(string(patterns), 1, []);
        else
            error('AutosarMapping:CalibrationConfig', '%s must contain regexp strings.', name);
        end
        for pattern = patterns
            if ismissing(pattern) || strlength(pattern) == 0
                error('AutosarMapping:CalibrationRegexp', 'Empty regexp entries are not allowed; use an empty array.');
            end
            try
                local_validateRegexp(pattern);
            catch cause
                failure = MException('AutosarMapping:CalibrationRegexp', 'Invalid calibration regexp: %s', pattern);
                throwAsCaller(addCause(failure, cause));
            end
        end
        config.(char(name)) = patterns;
    end
    enumNames = ["ModelParameterMapping", "ArgumentMapping", "SwCalibrationAccess"];
    choices = {["SharedParameter", "ConstantMemory"], "PerInstanceParameter", ...
        ["ReadOnly", "ReadWrite", "NotAccessible"]};
    for k = 1:numel(enumNames)
        name = char(enumNames(k));
        entry = config.(name);
        if ~(ischar(entry) && isrow(entry)) && ~(isstring(entry) && isscalar(entry))
            error('AutosarMapping:CalibrationConfig', '%s must be a scalar string.', name);
        end
        entry = string(entry);
        if ~any(entry == choices{k}), error('AutosarMapping:CalibrationConfig', 'Invalid %s: %s', name, entry); end
        config.(name) = entry;
    end
    [~, info] = fileattrib(filename);
    config.File = string(info.Name);
end

function local_validateRegexp(pattern)
    if any(contains(pattern, ["(?@", "(??"]))
        error('AutosarMapping:CalibrationRegexp', 'Dynamic MATLAB commands are not supported in naming patterns.');
    end
    previousWarnings = warning;
    [previousMessage, previousId] = lastwarn;
    restore = onCleanup(@() local_restoreWarnings(previousWarnings, previousMessage, previousId));
    warning('off', 'all');
    lastwarn('');
    % MATLAB accepts several malformed expressions literally unless warnings
    % are requested. Inspect diagnostics without changing the caller's state.
    validated = regexp('CalibrationConfigValidation', char(pattern), 'once', 'warnings'); %#ok<NASGU>
    [message, identifier] = lastwarn;
    if ~isempty(message)
        error('AutosarMapping:CalibrationRegexp', '%s: %s', identifier, message);
    end
end

function local_restoreWarnings(state, message, identifier)
    warning(state);
    lastwarn(message, identifier);
end
