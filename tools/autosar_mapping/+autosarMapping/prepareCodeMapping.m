function after = prepareCodeMapping(adapter, record, before, edited)
%PREPARECODEMAPPING Validate scalar rules and assemble native tuple (v1.3.1).
    after = before;
    for name = string(fieldnames(edited))'
        after.(char(name)) = edited.(char(name));
    end
    if isfield(after, 'MappedTo')
        role = after.MappedTo;
        roles = ["Auto", "StaticMemory", "ArTypedPerInstanceMemory"];
        if record.Category == "ModelParameters", roles = ["Auto", "SharedParameter", "ConstantMemory"]; end
        if record.Category == "ModelParameterArguments", roles = ["Auto", "PerInstanceParameter", "PortParameter"]; end
        if ~any(role == roles), error('AutosarMapping:Value', 'Invalid MappedTo: %s', role); end
        valid = ["MappedTo", adapter.dataProperties(record.Category, role)];
        if any(record.Category == ["Signals", "SynthesizedDataStores"]), valid = [valid, "Registered"]; end
        for name = string(fieldnames(after))'
            if ~any(name == valid)
                if isfield(edited, char(name))
                    error('AutosarMapping:Property', '%s is unavailable for %s.', name, role);
                end
                after = rmfield(after, char(name));
            end
        end
    else
        valid = string(fieldnames(before))';
        if any(record.Category == ["Signals", "SynthesizedDataStores"])
            valid = ["Registered", "MappedTo", adapter.dataProperties(record.Category, "StaticMemory"), ...
                adapter.dataProperties(record.Category, "ArTypedPerInstanceMemory")];
        end
    end
    inactiveNvBlockNeeds = isfield(after, 'MappedTo') && ...
        after.MappedTo == "ArTypedPerInstanceMemory" && ...
        isfield(after, 'NeedsNVRAMAccess') && after.NeedsNVRAMAccess == "false";
    for name = string(fieldnames(edited))'
        if ~any(name == valid), error('AutosarMapping:Property', 'Unavailable setting %s/%s.', record.Category, name); end
        if isfield(before, 'MappedTo') && before.MappedTo == after.MappedTo && ...
                ~isfield(before, char(name)) && name ~= "Registered" && ...
                ~(isfield(before, 'NeedsNVRAMAccess') && ...
                any(name == ["RestoreAtStart", "StoreAtShutdown"]))
            error('AutosarMapping:Property', 'Setting %s is not exposed for this element on the installed release.', name);
        end
        value = after.(char(name));
        allowed = strings(0, 1);
        switch name
            case {"Registered", "IsConst", "IsVolatile", "NeedsNVRAMAccess", "RestoreAtStart", "StoreAtShutdown"}
                allowed = ["true", "false"];
            case "GroupInternalDataByFunction", allowed = ["on", "off"];
            case "SwCalibrationAccess", allowed = ["ReadOnly", "ReadWrite", "NotAccessible"];
            case "DataAccessMode"
                if record.Category == "Inports"
                    allowed = ["ImplicitReceive", "ExplicitReceive", "ExplicitReceiveByVal", ...
                        "QueuedExplicitReceive", "ErrorStatus", "IsUpdated", "EndToEndRead", "ModeReceive"];
                elseif record.Category == "Outports"
                    allowed = ["ImplicitSend", "ImplicitSendByRef", "ExplicitSend", ...
                        "QueuedExplicitSend", "EndToEndWrite", "ModeSend"];
                else
                    allowed = ["Implicit", "Explicit"];
                end
            case "EndToEndProtectionMethod"
                allowed = ["ProtectionWrapper", "TransformerError", "TransformerErrorWrapper"];
            case "Packaging", allowed = ["Default", "PrivateGlobal", "PrivateStructure", "PublicGlobal", "PublicStructure"];
        end
        if ~isempty(allowed) && ~any(value == allowed)
            error('AutosarMapping:Value', 'Invalid %s value: %s.', name, value);
        end
        if any(name == ["SwAddrMethod", "SwAddrMethodForInternalData"]) && value ~= ""
            properties = autosar.api.getAUTOSARProperties(char(adapter.Model));
            paths = string(properties.find([], 'SwAddrMethod', 'PathType', 'FullyQualified'));
            index = find(regexprep(paths, '^.*/', '') == value);
            if numel(index) ~= 1
                error('AutosarMapping:MethodResolution', 'SwAddrMethod %s must exist exactly once.', value);
            end
            allowed = "Var";
            if record.Category == "Functions" && name == "SwAddrMethod", allowed = "Code"; end
            if isfield(after, 'MappedTo')
                if after.MappedTo == "ConstantMemory", allowed = "Const"; end
                if any(after.MappedTo == ["SharedParameter", "PerInstanceParameter", "PortParameter"])
                    allowed = ["Const", "Calprm"];
                end
            end
            if record.Category == "Defaults" && record.Element == "Constants", allowed = "Const"; end
            section = string(properties.get(char(paths(index)), 'SectionType'));
            if ~any(strcmpi(section, allowed))
                error('AutosarMapping:SectionType', '%s has incompatible SectionType %s.', value, section);
            end
        end
    end
    if inactiveNvBlockNeeds
        for name = ["RestoreAtStart", "StoreAtShutdown"]
            if isfield(after, char(name)), after = rmfield(after, char(name)); end
        end
    end
    if isfield(after, 'Registered') && after.Registered == "false"
        if numel(fieldnames(edited)) ~= 1 || ~isfield(edited, 'Registered')
            error('AutosarMapping:Registration', 'Registered=false must be the only setting for the element.');
        end
        after = struct('Registered', "false");
    elseif isfield(after, 'Registered') && after.Registered == "true" && ~isfield(after, 'MappedTo')
        after.MappedTo = "Auto";
    end
    if isfield(after, 'MappedTo') && after.MappedTo == "PortParameter" && ...
            (~isfield(after, 'Port') || ~isfield(after, 'DataElement') || after.Port == "" || after.DataElement == "")
        error('AutosarMapping:PortParameter', 'PortParameter requires Port and DataElement.');
    end
end
