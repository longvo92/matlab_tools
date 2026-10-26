classdef CodeMappingAdapter
%CODEMAPPINGADAPTER Native AUTOSAR Code Mappings adapter (version 1.2.0).
%   Internal bundle implementation. Uses documented mapping methods only;
%   unavailable properties are not exported and cannot silently be ignored.
    properties (SetAccess = private)
        Model
        Mapping
    end
    methods
        function obj = CodeMappingAdapter(model)
            if isempty(model), model = bdroot; end
            try
                model = get_param(bdroot(model), 'Name');
            catch cause
                failure = MException('AutosarMapping:Model', 'Specify an already loaded model.');
                throwAsCaller(addCause(failure, cause));
            end
            if ~strcmp(get_param(model, 'BlockDiagramType'), 'model') || ...
                    ~strcmp(get_param(model, 'SimulationStatus'), 'stopped')
                error('AutosarMapping:Model', 'A stopped, loaded model is required.');
            end
            if ~strcmp(get_param(model, 'SystemTargetFile'), 'autosar.tlc')
                error('AutosarMapping:Platform', 'This adapter requires an AUTOSAR Classic component model.');
            end
            obj.Model = string(model);
            obj.Mapping = autosar.api.getSimulinkMapping(model);
        end

        function records = inventory(obj)
            records = repmat(local_record("", "", []), 0, 1);
            categories = obj.categories();
            for category = categories(1:end-2)
                targets = obj.Mapping.find(char(category));
                for k = 1:numel(targets)
                    if iscell(targets), target = targets{k}; else, target = targets(k); end
                    if isstring(target), target = char(target); end
                    if any(category == ["Inports", "Outports"])
                        % Bus-element ports are identified by the block name,
                        % exactly as required by the native port mapping API.
                        element = string(get_param(target, 'Name'));
                        target = char(element);
                    elseif category == "Signals"
                        element = obj.relative(getfullname(get_param(target, 'Parent'))) + ...
                            ":" + string(get_param(target, 'PortNumber'));
                    elseif any(category == ["States", "DataStores"])
                        element = obj.relative(getfullname(target));
                    elseif category == "FunctionCallers" && startsWith(string(target), obj.Model + "/")
                        element = obj.relative(target);
                    else
                        element = string(target);
                    end
                    records(end + 1, 1) = local_record(category, element, target); %#ok<AGROW>
                end
            end
            workspace = get_param(char(obj.Model), 'ModelWorkspace');
            variables = whos(workspace);
            for k = 1:numel(variables)
                if ~strcmp(variables(k).class, 'Simulink.Signal'), continue; end
                name = variables(k).name;
                try
                    obj.Mapping.getSynthesizedDataStore(name);
                catch
                    continue; % Workspace signals need not be synthesized stores.
                end
                records(end + 1, 1) = local_record("SynthesizedDataStores", string(name), name); %#ok<AGROW>
            end
            records(end + 1, 1) = local_record("Defaults", "InternalData", 'InternalData');
            records(end + 1, 1) = local_record("Defaults", "InportsOutports", 'InportsOutports');
            % Newer releases expose Constants defaults. Absence is explicit
            % when a rule requests it; never emulate it through private APIs.
            try
                obj.Mapping.getDataDefaults('Constants', 'SwAddrMethod');
                records(end + 1, 1) = local_record("Defaults", "Constants", 'Constants');
            catch
            end
            [~, categoryOrder] = ismember([records.Category]', categories);
            [~, order] = sortrows(table(categoryOrder, [records.Element]'), [1 2]);
            records = records(order);
        end

        function record = resolve(obj, category, element)
            if category == "Signals"
                parts = regexp(char(element), '^(.*):([1-9][0-9]*)$', 'tokens', 'once');
                if isempty(parts), error('AutosarMapping:Element', 'Signal identifiers use block/path:port.'); end
                ports = get_param(char(obj.Model + "/" + string(parts{1})), 'PortHandles');
                index = str2double(parts{2});
                if index > numel(ports.Outport), error('AutosarMapping:Element', 'Output port does not exist.'); end
                record = local_record(category, element, ports.Outport(index));
            elseif category == "SynthesizedDataStores"
                workspace = get_param(char(obj.Model), 'ModelWorkspace');
                if ~hasVariable(workspace, char(element)) || ...
                        ~isa(getVariable(workspace, char(element)), 'Simulink.Signal')
                    error('AutosarMapping:Element', 'Synthesized store requires a model-workspace Simulink.Signal.');
                end
                record = local_record(category, element, char(element));
            elseif category == "States" && contains(element, "#")
                parts = regexp(char(element), '^(.*)#([^#]+)$', 'tokens', 'once');
                block = char(obj.Model + "/" + string(parts{1}));
                get_param(block, 'Handle');
                record = local_record(category, element, block);
                record.StateName = parts{2};
            else
                error('AutosarMapping:Element', 'Unknown %s element: %s', category, element);
            end
        end

        function values = read(obj, record)
            mapping = obj.Mapping;
            target = record.Target;
            switch record.Category
                case "Inports"
                    [p, d, a] = mapping.getInport(target);
                    values = struct('Port', string(p), 'DataElement', string(d), 'DataAccessMode', string(a));
                case "Outports"
                    [p, d, a] = mapping.getOutport(target);
                    values = struct('Port', string(p), 'DataElement', string(d), 'DataAccessMode', string(a));
                case "Functions"
                    [r, c, d] = mapping.getFunction(target);
                    values = struct('Runnable', string(r), 'SwAddrMethod', local_method(c));
                    if strcmp(target, 'Periodic') || startsWith(target, ...
                            {'Periodic:', 'Partition:', 'ExportedFunction:', 'SimulinkFunction:'})
                        values.SwAddrMethodForInternalData = local_method(d);
                    end
                case "FunctionCallers"
                    [p, o] = mapping.getFunctionCaller(target);
                    values = struct('Port', string(p), 'Operation', string(o));
                case "DataTransfers"
                    [r, a] = mapping.getDataTransfer(target);
                    values = struct('InterRunnableVariable', string(r), 'DataAccessMode', string(a));
                case "Defaults"
                    values = struct();
                    if record.Element == "InternalData"
                        values.Packaging = string(mapping.getInternalDataPackaging());
                        values.GroupInternalDataByFunction = string(get_param(char(obj.Model), 'GroupInternalDataByFunction'));
                        try
                            values.SwAddrMethod = string(mapping.getDataDefaults('InternalData', 'SwAddrMethod'));
                        catch
                        end
                    elseif record.Element == "Constants"
                        values.SwAddrMethod = string(mapping.getDataDefaults('Constants', 'SwAddrMethod'));
                    else
                        values.EndToEndProtectionMethod = string(mapping.getDataDefaults('InportsOutports', 'EndToEndProtectionMethod'));
                    end
                otherwise
                    registered = true;
                    if any(record.Category == ["Signals", "SynthesizedDataStores"])
                        registered = obj.registered(record);
                    end
                    values = struct('Registered', string(registered));
                    if ~registered, return; end
                    role = string(obj.getData(record, ''));
                    values.MappedTo = role;
                    for name = obj.dataProperties(record.Category, role)
                        % Native releases expose different parameter properties.
                        % Keep only those actually readable for this element.
                        try
                            values.(char(name)) = string(obj.getData(record, char(name)));
                        catch
                        end
                    end
                    if ~any(record.Category == ["Signals", "SynthesizedDataStores"])
                        values = rmfield(values, 'Registered');
                    end
            end
        end

        function value = getData(obj, record, property)
            args = {record.Target};
            if record.Category == "States", args{end + 1} = record.StateName; end
            if ~isempty(property), args{end + 1} = property; end
            switch record.Category
                case {"ModelParameters", "ModelParameterArguments"}, value = obj.Mapping.getParameter(args{:});
                case "Signals", value = obj.Mapping.getSignal(args{:});
                case "States", value = obj.Mapping.getState(args{:});
                case "DataStores", value = obj.Mapping.getDataStore(args{:});
                case "SynthesizedDataStores", value = obj.Mapping.getSynthesizedDataStore(args{:});
            end
        end

        function write(obj, record, values)
            mapping = obj.Mapping;
            t = record.Target;
            switch record.Category
                case "Inports"
                    mapping.mapInport(t, char(values.Port), char(values.DataElement), char(values.DataAccessMode));
                case "Outports"
                    mapping.mapOutport(t, char(values.Port), char(values.DataElement), char(values.DataAccessMode));
                case "Functions"
                    args = {'SwAddrMethod', local_nativeMethod(values.SwAddrMethod)};
                    if isfield(values, 'SwAddrMethodForInternalData') && ...
                            strcmp(get_param(char(obj.Model), 'GroupInternalDataByFunction'), 'on')
                        args = [args, {'SwAddrMethodForInternalData', local_nativeMethod(values.SwAddrMethodForInternalData)}];
                    end
                    mapping.mapFunction(t, char(values.Runnable), args{:});
                case "FunctionCallers"
                    mapping.mapFunctionCaller(t, char(values.Port), char(values.Operation));
                case "DataTransfers"
                    mapping.mapDataTransfer(t, char(values.InterRunnableVariable), char(values.DataAccessMode));
                case "Defaults"
                    if isfield(values, 'GroupInternalDataByFunction')
                        set_param(char(obj.Model), 'GroupInternalDataByFunction', char(values.GroupInternalDataByFunction));
                    end
                    if isfield(values, 'Packaging'), mapping.setInternalDataPackaging(char(values.Packaging)); end
                    if isfield(values, 'EndToEndProtectionMethod')
                        mapping.setDataDefaults('InportsOutports', 'EndToEndProtectionMethod', char(values.EndToEndProtectionMethod));
                    end
                    if isfield(values, 'SwAddrMethod')
                        mapping.setDataDefaults(char(record.Element), 'SwAddrMethod', char(values.SwAddrMethod));
                    end
                otherwise
                    if isfield(values, 'Registered')
                        registered = obj.registered(record);
                        desired = values.Registered == "true";
                        if registered ~= desired
                            if record.Category == "Signals"
                                if desired, mapping.addSignal(t); else, mapping.removeSignal(t); end
                            else
                                if desired, mapping.addSynthesizedDataStore(t); else, mapping.removeSynthesizedDataStore(t); end
                            end
                        end
                        if ~desired, return; end
                    end
                    if ~isfield(values, 'MappedTo'), return; end
                    role = values.MappedTo;
                    args = {t};
                    if record.Category == "States", args{end + 1} = record.StateName; end
                    args{end + 1} = char(role);
                    for name = obj.dataProperties(record.Category, role)
                        if isfield(values, char(name))
                            args = [args, {char(name), char(values.(char(name)))}]; %#ok<AGROW>
                        end
                    end
                    switch record.Category
                        case {"ModelParameters", "ModelParameterArguments"}, mapping.mapParameter(args{:});
                        case "Signals", mapping.mapSignal(args{:});
                        case "States", mapping.mapState(args{:});
                        case "DataStores", mapping.mapDataStore(args{:});
                        case "SynthesizedDataStores", mapping.mapSynthesizedDataStore(args{:});
                    end
            end
        end

        function value = registered(obj, record)
            if record.Category == "Signals"
                value = any(obj.Mapping.find('Signals') == record.Target);
            else
                try
                    obj.Mapping.getSynthesizedDataStore(record.Target);
                    value = true;
                catch
                    value = false;
                end
            end
        end

        function value = relative(obj, value)
            value = extractAfter(string(value), strlength(obj.Model) + 1);
        end
    end
    methods (Static)
        function value = categories()
            value = ["Inports", "Outports", "Functions", "FunctionCallers", ...
                "DataTransfers", "ModelParameters", "ModelParameterArguments", ...
                "Signals", "States", "DataStores", "SynthesizedDataStores", "Defaults"];
        end

        function names = dataProperties(category, role)
            names = strings(1, 0);
            if role == "Auto", return; end
            names = ["LongName", "SwAddrMethod", "SwCalibrationAccess", "DisplayFormat"];
            if any(category == ["ModelParameters", "ModelParameterArguments"])
                if role == "ConstantMemory", names = [names, "IsConst", "IsVolatile", "Qualifier"]; end
                if role == "PortParameter", names = [names, "Port", "DataElement"]; end
                % ShortName is release-dependent; getter probing determines
                % whether this parameter exposes it on the installed release.
                names = [names, "ShortName"];
            else
                names = [names, "ShortName"];
                if role == "StaticMemory", names = [names, "IsVolatile", "Qualifier"]; end
                if role == "ArTypedPerInstanceMemory"
                    names = [names, "NeedsNVRAMAccess", "RestoreAtStart", "StoreAtShutdown"];
                end
            end
        end
    end
end

function record = local_record(category, element, target)
    record = struct('Category', category, 'Element', element, 'Target', target, 'StateName', '');
end

function value = local_method(value)
    value = string(value);
    if value == "<None>", value = ""; end
end

function value = local_nativeMethod(value)
    value = char(value);
    if isempty(value), value = '<None>'; end
end
