function testQuickSimEnv()
%TESTQUICKSIMENV Verify SLDD resolution outside the MATLAB path.
    previousPath = path;
    previousFolder = pwd;
    restore = onCleanup(@() local_restore(previousPath, previousFolder));
    repo = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repo, 'tools', 'quick_sim'));
    sandbox = tempname;
    mkdir(sandbox);
    cd(sandbox);
    mkdir('external');
    [~, name] = fileparts(tempname);
    file = fullfile(sandbox, 'external', [name '.sldd']);
    dictionary = Simulink.data.dictionary.create(file);
    saveChanges(dictionary);
    close(dictionary);
    [model, report] = quickSimEnv(file);
    modelCleanup = onCleanup(@() close_system(model, 0));
    assert(strcmp(report.sldd, file));
    linked = get_param(model, 'DataDictionary');
    resolved = Simulink.data.dictionary.open(linked);
    dictionaryCleanup = onCleanup(@() close(resolved));
    assert(strcmp(resolved.filepath, file));
    clear dictionaryCleanup modelCleanup;
    rmpath(fullfile(sandbox, 'external'));
    [model, report] = quickSimEnv(fullfile('external', [name '.sldd']));
    modelCleanup = onCleanup(@() close_system(model, 0));
    assert(strcmp(report.sldd, file));
    clear modelCleanup;
    [model, report] = quickSimEnv(fullfile(sandbox, 'missing.sldd'));
    modelCleanup = onCleanup(@() close_system(model, 0));
    assert(isempty(report.sldd) && isempty(get_param(model, 'DataDictionary')));
    clear modelCleanup;
    invalid = fullfile(sandbox, 'invalid.sldd');
    fid = fopen(invalid, 'w');
    fprintf(fid, 'Not a data dictionary.');
    fclose(fid);
    before = path;
    [model, report] = quickSimEnv(invalid);
    modelCleanup = onCleanup(@() close_system(model, 0));
    assert(isempty(report.sldd) && isempty(get_param(model, 'DataDictionary')));
    assert(strcmp(path, before), 'Failed linking changed the session path.');
    fprintf('PASS: external absolute/relative SLDD paths, missing/invalid dictionary reporting.\n');
end

function local_restore(previousPath, previousFolder)
    cd(previousFolder);
    path(previousPath);
end
