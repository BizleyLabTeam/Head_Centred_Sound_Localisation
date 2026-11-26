%% CalculateWorldPreferenceIndex
% Calculate the world preference index (WPI) for trained or orthogonal
% comparisons and assess its significance using a permutation test.
%
% Author: Nadia Aghili (2026)
%
% Inputs:
%   - Summary table containing driven unit IDs, spatial tuning labels,
%     model preference values and cortical field assignments (.xlsx)
%   - Stimulus onset times and behavioural data (.mat)
%   - Recording information and optional bad-block information (.csv)
%   - Spike sorting outputs (.npy and .tsv)
%
% Outputs (.mat):
%   - WPI values (DeltaCI_obs), permutation p-values (DeltaCI_p) and significance flags (DeltaCI_sig)
%   - PSTHs and associated time bins
%   - Trial-level spike data and behavioural information
%   - Session-specific baseline statistics
%   - Unit IDs, tuning classifications and model preference values
%   - Cortical field assignments and recording metadata
%   - Analysis parameters

% clc
% clear
% close all

% % % summaryExcel = "Summary_Table_WithDepth.xlsx";
% % % ferretName = "Crumble";
% % % sideName = "Right";
% % % basePath = "D:\Stephen_Nadia_Jenny\Crumble_RESULTS\Right";  % "D:\Stephen_Nadia_Jenny\Crumble_RESULTS\Left"; "F:\Spontage_results\Left";"F:\Ursula_Results\Left"
% % condition = "Orthogonal"; % "Trained" or "Orthogonal"

unit_state_total = ["Head","World","Mixed"];
bin_size = 0.02;
sampling_rate = 20000;

%% Analysis parameters
time_window_plot = [-0.1, 0.35];  % s
time_window = [0 0.25];
pre_win = [-0.1 0];
% Map loudspeaker indices to world-centred angles
deg_map = [150 120 90 60 30 0 -30 -60 -90 -120 -150 -180];

modelPrefThr = 0.2;

%%
% READ EXCEL

Tsum = readtable(summaryExcel);
Tsum.FerretName = string(Tsum.FerretName);
Tsum.Side = string(Tsum.Side);
Tsum.GroupName  = string(Tsum.GroupName);
Tsum = Tsum(Tsum.FerretName == ferretName & Tsum.Side == sideName, :);

if isempty(Tsum)
    error("No rows found for %s %s in %s", ferretName, sideName, summaryExcel);
end

groupList = unique(Tsum.GroupName, 'stable');

%%
% FIND GROUP FOLDERS
allGroupFolders = dir(fullfile(basePath,ferretName + "_*_Group*"));
allGroupFolders = allGroupFolders([allGroupFolders.isdir]);

if isempty(allGroupFolders)
    error("No group folders found in: " + basePath);
end

%%
% RUN GROUP BY GROUP

for g = 1:numel(groupList)

    for state = 1:3

        unit_state = unit_state_total(state);
        groupName = groupList(g);

        disp("Running: " + ferretName + " | " + sideName + " | " + groupName);

        %% Driven units for this group from Excel

        pick_cindx = Tsum.DrivenUnit(Tsum.GroupName == groupName).';
        pick_cindx = double(pick_cindx);

        disp("Preselected units: " + num2str(pick_cindx));

        rowsGroup = Tsum.GroupName == groupName;
        pick_all = double(Tsum.DrivenUnit(rowsGroup)).';
        Label_all = string(Tsum.DrivenLabel(rowsGroup)).';
        ModelPref_all = str2double(string(Tsum.ModelPreference(rowsGroup))).';
        Field_all = string(Tsum.Field(rowsGroup)).';

        if unit_state == "Head"
            keepUnit = isfinite(ModelPref_all) & Label_all == "Head" & abs(ModelPref_all) > modelPrefThr;
        elseif unit_state == "World"
            keepUnit = isfinite(ModelPref_all) & Label_all == "World" & abs(ModelPref_all) > modelPrefThr;
        elseif unit_state == "Mixed"
            keepUnit = isfinite(ModelPref_all) & Label_all ~= "NotTuned" & Label_all ~= "FitError" & abs(ModelPref_all) <= modelPrefThr;
        else
            error("Unknown unit state: " + unit_state);
        end

        pick_cindx = pick_all(keepUnit);
        UnitLabel = Label_all(keepUnit);
        UnitModelPref = ModelPref_all(keepUnit);
        UnitField = Field_all(keepUnit);

        UnitFinalLabel = repmat(unit_state, size(pick_cindx));

        if unit_state == "Mixed"
            UnitFinalLabel(:) = "Mix";
        end
        UnitFerret = repmat(ferretName, size(pick_cindx));
        UnitSide = repmat(sideName, size(pick_cindx));
        UnitGroup = repmat(groupName, size(pick_cindx));

        %% Find matching group folder
        groupPath = "";
        for ff = 1:numel(allGroupFolders)

            folderName = string(allGroupFolders(ff).name);
            pattern = groupName + "(?!\d)";
            if ~isempty(regexp(folderName, pattern, "once"))
                groupPath = string(fullfile(allGroupFolders(ff).folder, allGroupFolders(ff).name));
                break
            end
        end

        if groupPath == ""
            warning("No folder containing " + groupName + " was found. Skipping.");
            continue
        end

        %% Build paths automatically
        folderPath = fullfile(groupPath, "recording_info.csv");
        bad_block_path = fullfile(groupPath, "bad_blocks.csv");
        badchannelpath = fullfile(groupPath, "channel_removed.csv");
        phyPath = fullfile(groupPath, "data", "mountainsort4", "phy");

        if ~isfile(folderPath)
            warning("recording_info.csv not found for %s. Skipping.", groupName);
            continue
        end

        if ~isfile(bad_block_path)
            bad_block_path = [];
        end

        if ~isfolder(phyPath)
            warning("phy folder not found for %s. Skipping.", groupName);
            continue
        end

        %% Run this group
        runOneGroup(groupPath, phyPath, folderPath, bad_block_path, badchannelpath, pick_cindx, UnitLabel, UnitModelPref, UnitField, ...
            UnitFinalLabel, UnitFerret, UnitSide, UnitGroup, ferretName, sideName, groupName, sampling_rate, deg_map, ...
            time_window, time_window_plot, pre_win, unit_state, bin_size, modelPrefThr, condition);
    end
end

disp("All groups finished.");

%% FUNCTION

function runOneGroup(groupPath, phyPath, folderPath, bad_block_path,badchannelpath, pick_cindx, UnitLabel, UnitModelPref, UnitField, ...
    UnitFinalLabel, UnitFerret, UnitSide, UnitGroup, ferretName, sideName, groupName, sampling_rate, deg_map, ...
    time_window, time_window_plot, pre_win, unit_state, bin_size, modelPrefThr, condition)

close all;

%% Save name for this group

saveFileName = "WPI_" + condition + "_" + unit_state + "_" + ferretName + "_" + sideName + "_" + groupName + ".mat";
saveFilePath = fullfile(phyPath, saveFileName);
%% Load exact behavior/onset file

if ferretName == "Ursula"
    groupForFile = regexprep(groupName, "^Group_?", "G");
else
    % Crumble / Sponge keep the original group name
    groupForFile = groupName;
end

behaviorFileName = ferretName + "_" + sideName + "_" + groupForFile + ".mat";

behaviorFilePath = fullfile(phyPath,behaviorFileName);

if ~isfile(behaviorFilePath)
    error("Behavior file not found: %s",behaviorFilePath);
end

%% Safety check: must contain the required behavioral variables

fileInfo = whos('-file',behaviorFilePath);
variableNames = string({fileInfo.name});

if ~all(ismember(["onset_times","Behavior_"],variableNames))
    error( "File %s does not contain both onset_times and Behavior_.", behaviorFileName);
end

% Load ONLY the required behavioral variables

clear onset_times Behavior_

S = load(behaviorFilePath, 'onset_times', 'Behavior_');
onset_times = S.onset_times;
Behavior_ = S.Behavior_;

%% Go to phy folder
oldFolder = pwd;
cleanupObj = onCleanup(@() cd(oldFolder));

cd(phyPath);

%% Load session information and spike sorting data

if isempty(pick_cindx)
    warning("No units found in this category: " + ferretName + " | " + sideName + " | " + unit_state);
    return
end

Cinfo = readtable('cluster_info.tsv','FileType','text','Delimiter','\t');
valid_clusters = Cinfo.cluster_id;

spike_times_all = double(readNPY('spike_times.npy'));
spike_clusters_all = double(readNPY('spike_clusters.npy'));
keep_idx = ismember(spike_clusters_all, valid_clusters);
spike_times_all = spike_times_all(keep_idx);
spike_clusters_all = spike_clusters_all(keep_idx);
Sessionss = generateSessionCells(folderPath, bad_block_path);
McStStimOnsetTimes = onset_times(~cellfun('isempty',onset_times));
Behaviors = Behavior_(~cellfun('isempty',Behavior_));

aa = 0;
trial_count = 0;

CI_all = nan(numel(pick_cindx),1);
II_all = nan(numel(pick_cindx),1);
DeltaCI_obs = nan(numel(pick_cindx),1);
DeltaCI_p = nan(numel(pick_cindx),1);
DeltaCI_sig = nan(numel(pick_cindx),1);
DeltaCI_lo = nan(numel(pick_cindx),1);
DeltaCI_hi = nan(numel(pick_cindx),1);

%% Calculate preference indices for each unit

PermTrialCounts = nan(numel(pick_cindx),4);
PermTrialLabels = {'Front_A','Front_B','Back_A','Back_B'};
UnitTrialSpikes = cell(numel(pick_cindx),1);
UnitTrialSession = cell(numel(pick_cindx),1);
UnitTrialHead  = cell(numel(pick_cindx),1);
UnitTrialWorld = cell(numel(pick_cindx),1);
UnitTrialCSR = cell(numel(pick_cindx),1);
UnitBaselineMean = cell(numel(pick_cindx),1);
UnitBaselineStd = cell(numel(pick_cindx),1);

for cl_id = pick_cindx

    aa = aa+1;

    trial_spikes = {};
    trial_head = [];
    trial_world = [];
    trial_session = [];
    trial_csr = [];
    trial_headDir = [];
    trial_tailDir = [];
    trial_rate = [];

    baselineMeanBySession = nan(numel(Sessionss),1);
    baselineStdBySession  = nan(numel(Sessionss),1);

    % Collect trials across sessions
    for s = 1:numel(Sessionss)
        rate_post_sess = [];
        rate_pre_sess  = [];
        if isempty(Sessionss{s}), continue; end
        if isempty(Behaviors{s}) || ischar(Behaviors{s}) || isstring(Behaviors{s})
            continue;
        end
        beh = Behaviors{s};
        if width(beh) < 15, continue, end  % removing FRA

        csr = beh.CenterSpoutRotation;
        sloc = beh.Speaker_Location;
        onset = McStStimOnsetTimes{s};
        [t0, t1] = bounds(Sessionss{s});

        if numel(sloc) ~= numel(onset), continue, end

        in_sess = (spike_clusters_all == cl_id) & (spike_times_all >= t0) & (spike_times_all <= t1);
        spikes_s = (spike_times_all(in_sess) - t0) / sampling_rate;  % s

        for tr = 1:numel(onset)
            if isnan(sloc(tr)), continue, end

            trial_count = trial_count+1;
            % Calculate world- and head-centred sound angles
            wa = deg_map(sloc(tr));
            head_dir = mod(csr(tr), 360) - 180;
            ha = mod(head_dir - wa + 180, 360) - 180;
            tail_dir = csr(tr); % ferret back

            if abs(ha) == 180, ha = -180; end
            if abs(wa) == 180, wa = -180; end
            if abs(head_dir) == 180, head_dir = -180; end
            if abs(tail_dir) == 180, tail_dir = -180; end

            sp = spikes_s(spikes_s >= onset(tr) + time_window_plot(1) & spikes_s < onset(tr) + time_window_plot(2)) - onset(tr);

            sp_post = spikes_s(spikes_s >= onset(tr)+ time_window(1) & spikes_s < onset(tr)+ time_window(2)) - onset(tr);
            sp_pre = spikes_s(spikes_s >= onset(tr)+pre_win(1) & spikes_s < onset(tr)+pre_win(2)) - onset(tr);

            %% Baseline

            rate_post_sess(end+1) = numel(sp_post)/diff(time_window);
            rate_pre_sess(end+1)  = numel(sp_pre)/diff(pre_win);

            trial_spikes{end+1} = sp;
            trial_head(end+1) = ha;
            trial_world(end+1) = wa;
            trial_session(end+1) = s;
            trial_csr(end+1) = tail_dir;   %
            trial_headDir(end+1) = head_dir;
            trial_tailDir(end+1) = tail_dir;
        end


        baseline_mean = mean(rate_pre_sess,'omitnan');
        baseline_std  = std(rate_pre_sess,0,'omitnan');

        baselineMeanBySession(s) = baseline_mean;
        baselineStdBySession(s)  = baseline_std;

        if isfinite(baseline_std) && baseline_std > 0
            z_rates = (rate_post_sess - baseline_mean) ./ baseline_std;
        else
            z_rates = nan(size(rate_post_sess));
        end
        trial_rate = [trial_rate z_rates];
    end

    UnitTrialSpikes{aa} = trial_spikes;
    UnitTrialSession{aa} = trial_session;
    UnitTrialHead{aa} = trial_head;
    UnitTrialWorld{aa} = trial_world;
    UnitTrialCSR{aa} = trial_csr;

    UnitBaselineMean{aa} = baselineMeanBySession;
    UnitBaselineStd{aa} = baselineStdBySession;

    % Group trials by animal orientation and sound location
    CSR_total = unique(trial_csr);

    Front = cell(numel(CSR_total),1);
    Back  = cell(numel(CSR_total),1);
    WorldFront = cell(numel(CSR_total),1);
    WorldBack = cell(numel(CSR_total),1);
    FrontIdx = cell(numel(CSR_total),1);
    BackIdx = cell(numel(CSR_total),1);
    WorldFrontIdx = cell(numel(CSR_total),1);
    WorldBackIdx = cell(numel(CSR_total),1);

    bb = 0;
    for ind_CSR = CSR_total

        bb = bb+1;
        indx = find (trial_csr == ind_CSR);
        if ferretName == "Crumble" || ferretName == "Sponge"

            isFront = (trial_head(indx) == 0);  % Front
            isBack  = (abs(trial_head(indx)) == 180); % Back

            isWorldFront = (trial_world(indx) == 0);
            isWorldBack  = (abs(trial_world(indx)) == 180);

        elseif ferretName == "Ursula"
            isFront = (trial_head(indx) == 90);  % Right
            isBack  = (trial_head(indx) == -90);  % Left

            isWorldFront = (trial_world(indx) == 90);
            isWorldBack  = (trial_world(indx) == -90);

        else

            error("Please add ferret's name")

        end

        Front{bb} = trial_spikes(indx(isFront));
        Back{bb}  = trial_spikes(indx(isBack));

        % world-centred identity sets (wa)

        WorldFront{bb} = trial_spikes(indx(isWorldFront));
        WorldBack{bb}  = trial_spikes(indx(isWorldBack));

        FrontIdx{bb} = indx(isFront);
        BackIdx{bb}  = indx(isBack);

        WorldFrontIdx{bb} = indx(isWorldFront);
        WorldBackIdx{bb}  = indx(isWorldBack);

    end

    % Calculate response preference for opposing sound location at each animal orientation
    nCSR = numel(CSR_total);
    CI_csr = nan(nCSR,1);
    II_csr = nan(nCSR,1);

    for i = 1:nCSR
        FRF  = mean(trial_rate(FrontIdx{i}), 'omitnan');
        FRB  = mean(trial_rate(BackIdx{i}),  'omitnan');
        CI_csr(i) = (FRF - FRB) / (abs(FRF) + abs(FRB) );

        FRWF = mean(trial_rate(WorldFrontIdx{i}), 'omitnan');
        FRWB = mean(trial_rate(WorldBackIdx{i}),  'omitnan');
        II_csr(i) = (FRWF - FRWB) / (abs(FRWF) + abs(FRWB));
    end


    %%%%%%%%%%%%  %% Calculate WPI and assess significance using a permutation test %%%%%%%%%%%%%%%%

    % Select opposing orientations for the trained or orthogonal condition
    if condition == "Trained"

        if ferretName == "Ursula"
            csrA = 90;
            csrB = -90;
        else
            csrA = 0;
            csrB = -180;
        end

    elseif condition == "Orthogonal"

        if ferretName == "Ursula"
            csrA = 0;
            csrB = -180;
        else
            csrA = 90;
            csrB = -90;
        end

    else
        error("Unknown condition: " + condition);
    end


    idxA = find(CSR_total == csrA);
    idxB = find(CSR_total == csrB);

    if ~isempty(idxA) && ~isempty(idxB)
        %% Calculate WPI
        delta_obs = CI_csr(idxA) - CI_csr(idxB);

        FA = trial_rate(FrontIdx{idxA});
        FB = trial_rate(FrontIdx{idxB});

        BA = trial_rate(BackIdx{idxA});
        BB = trial_rate(BackIdx{idxB});

        FA = FA(isfinite(FA));
        FB = FB(isfinite(FB));
        BA = BA(isfinite(BA));
        BB = BB(isfinite(BB));


        nFA = numel(FA);
        nFB = numel(FB);

        nBA = numel(BA);
        nBB = numel(BB);

        poolF = [FA(:); FB(:)];
        poolB = [BA(:); BB(:)];

        PermTrialCounts(aa,:) = [nFA nFB nBA nBB];

        nPerm = 1000;
        delta_perm = nan(nPerm,1);
        % Shuffle orientation labels while preserving trial counts
        for pp = 1:nPerm

            rp = randperm(numel(poolF));

            FAr = poolF(rp(1:nFA));
            FBr = poolF(rp(nFA+1:end));

            rp = randperm(numel(poolB));

            BAr = poolB(rp(1:nBA));
            BBr = poolB(rp(nBA+1:end));

            CIA = (mean(FAr,'omitnan') - mean(BAr,'omitnan')) / (abs(mean(FAr,'omitnan')) + abs(mean(BAr,'omitnan')));

            CIB = (mean(FBr,'omitnan') - mean(BBr,'omitnan')) / (abs(mean(FBr,'omitnan')) + abs(mean(BBr,'omitnan')));

            delta_perm(pp) = CIA - CIB;

        end

        validPerm = isfinite(delta_perm);

        if isfinite(delta_obs) && any(validPerm)

            pval = (sum(abs(delta_perm(validPerm)) >= abs(delta_obs)) + 1) /(sum(validPerm) + 1);
            DeltaCI_obs(aa) = delta_obs;
            DeltaCI_p(aa)   = pval;
            DeltaCI_sig(aa) = pval < 0.05;

        else

            DeltaCI_obs(aa) = delta_obs;
            DeltaCI_p(aa)   = NaN;
            DeltaCI_sig(aa) = NaN;

        end


    end

    %%%%%%%%%%%%%%% End of Permutation test %%%%%%%%%%%%

    CSR_all{aa} = CSR_total(:);
    CI_csr_all{aa} = CI_csr(:);
    II_csr_all{aa} = II_csr(:);

    %% Calculate PSTHs and associated SEMs
    edges = time_window_plot(1):bin_size:time_window_plot(2);
    bin_centers = edges(1:end-1) + bin_size/2;

    % mean + sem for each CSR
    pF = nan(nCSR, numel(bin_centers));
    sF = pF;   %
    pB = pF; sB = pF;   %
    pWF = pF; sWF = pF;   %
    pWB = pF; sWB = pF;   %

    for i = 1:nCSR
        %  ha Front
        X = zeros(numel(Front{i}), numel(bin_centers));
        for tr = 1:numel(Front{i})
            X(tr,:) = histcounts(Front{i}{tr}, edges) / bin_size;
        end
        if ~isempty(X)
            pF(i,:) = mean(X,1);
            sF(i,:) = std(X,0,1) / sqrt(size(X,1));
        end

        %  ha Back
        X = zeros(numel(Back{i}), numel(bin_centers));
        for tr = 1:numel(Back{i})
            X(tr,:) = histcounts(Back{i}{tr}, edges) / bin_size;
        end
        if ~isempty(X)
            pB(i,:) = mean(X,1);
            sB(i,:) = std(X,0,1) / sqrt(size(X,1));
        end

        X = zeros(numel(WorldFront{i}), numel(bin_centers));
        for tr = 1:numel(WorldFront{i})
            X(tr,:) = histcounts(WorldFront{i}{tr}, edges) / bin_size;
        end
        if ~isempty(X)
            pWF(i,:) = mean(X,1);
            sWF(i,:) = std(X,0,1) / sqrt(size(X,1));
        end

        X = zeros(numel(WorldBack{i}), numel(bin_centers));
        for tr = 1:numel(WorldBack{i})
            X(tr,:) = histcounts(WorldBack{i}{tr}, edges) / bin_size;
        end
        if ~isempty(X)
            pWB(i,:) = mean(X,1);
            sWB(i,:) = std(X,0,1) / sqrt(size(X,1));
        end
    end

    PSTH_bin_centers = bin_centers;   % same for all units
    PSTH_CSR{aa} = CSR_total(:);
    PSTH_F{aa} = pF;
    PSTH_B{aa} = pB;
    PSTH_WF{aa} = pWF;
    PSTH_WB{aa} = pWB;

end

%% Calculate population-level preference indices and SEMs
allCSR = [];
for u = 1:numel(CSR_all)
    allCSR = [allCSR; CSR_all{u}];
end
allCSR = sort(unique(allCSR));

CI_pop = nan(size(allCSR));
II_pop = nan(size(allCSR));
CI_sem = nan(size(allCSR));
II_sem = nan(size(allCSR));

for k = 1:numel(allCSR)
    csr0 = allCSR(k);

    v = [];
    for u = 1:numel(CSR_all)
        j = find(CSR_all{u} == csr0);
        if ~isempty(j), v = [v; CI_csr_all{u}(j)]; end
    end
    CI_pop(k) = mean(v,'omitnan');
    n = sum(~isnan(v));
    CI_sem(k) = std(v,'omitnan') / sqrt(max(n,1));

    v = [];
    for u = 1:numel(CSR_all)
        j = find(CSR_all{u} == csr0);
        if ~isempty(j), v = [v; II_csr_all{u}(j)]; end
    end
    II_pop(k) = mean(v,'omitnan');
    n = sum(~isnan(v));
    II_sem(k) = std(v,'omitnan') / sqrt(max(n,1));

end

%% Save results
save(saveFilePath, 'PSTH_bin_centers', 'PSTH_CSR', 'PSTH_F', 'PSTH_B', 'PSTH_WF', 'PSTH_WB', ...
    'CSR_all', 'CI_csr_all', 'II_csr_all', 'pick_cindx', 'UnitLabel', 'UnitFinalLabel', 'UnitModelPref', 'UnitField', ...
    'UnitFerret', 'UnitSide', 'UnitGroup', 'UnitTrialSpikes', 'UnitTrialSession', 'UnitTrialHead', ...
    'UnitTrialWorld', 'UnitTrialCSR', 'UnitBaselineMean', 'UnitBaselineStd', ...
    'DeltaCI_obs', 'DeltaCI_p', 'DeltaCI_sig', 'PermTrialCounts', 'PermTrialLabels', ...
    'bin_size', 'time_window_plot', 'time_window', 'pre_win', 'sampling_rate', 'ferretName', 'sideName', 'groupName', ...
    'unit_state', 'deg_map', 'modelPrefThr', 'condition');

disp("Results saved to: " + saveFilePath);

close all;

end