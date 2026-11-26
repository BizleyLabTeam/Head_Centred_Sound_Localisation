%% IdentifySpatiallyTunedUnits
% Identify spatially tuned units using Poisson GLMMs and quantify head- and world-centred tuning.
%
% Author: Nadia Aghili (2026)
%
% Inputs:
%   - Summary table containing driven unit IDs (.xlsx)
%   - Stimulus onset times and behavioural data (.mat)
%   - Recording information (.csv)
%   - Spike sorting outputs (.npy and .tsv)
%
% Outputs (.mat):
%   - Unit and recording group information
%   - Reference-frame labels (Label) and AIC values
%   - Model fits (Fit_head, Fit_world), model preference (ModelPref) and fit weights (FitWeight)
%   - Trial counts
%
% Note: This script is provided for reproducibility. Subsequent analyses use precomputed unit labels and model fits from the summary table, so running this script is not required.

% clc;
% clear;
% close all;

% Change Input

% % % summaryExcel = "Summary_Table.xlsx";
% % % ferretName = "Ursula";
% % % sideName = "Left";
% % % basePath = "F:\Ursula_Results\Left";

sampling_rate = 20000;  % Hz
% Map loudspeaker indices to world-centred angles
deg_map = [150 120 90 60 30 0 -30 -60 -90 -120 -150 -180];

% Define onset and offset response windows (s)
post_win = [0, 0.15];
late_post_win = [0.25, 0.4];

min_trials = 100;
alpha_gate = 0.05;

%% Load summary table
Tsum = readtable(summaryExcel);
Tsum.FerretName = string(Tsum.FerretName);
Tsum.Side = string(Tsum.Side);
Tsum.GroupName  = string(Tsum.GroupName);
Tsum = Tsum(Tsum.FerretName == ferretName & Tsum.Side == sideName, :);

if isempty(Tsum)
    error("No matching data found in the summary table.");
end

groupList = unique(Tsum.GroupName, 'stable');

% For the following Ursula groups, h1 is excluded because it is constant across trials.

% Right Side
% groupList = ["Group10_1", "Group9_1"];
% Left Side
% groupList = ["Group13_2", "Group14_1"];

allGroupFolders = dir(fullfile(basePath,ferretName + "_*_Group*"));
allGroupFolders = allGroupFolders([allGroupFolders.isdir]);

if isempty(allGroupFolders)
    error("No group folders found in: %s", basePath);
end

%% RUN GROUP BY GROUP by Function

for g = 1:numel(groupList)

    groupName = groupList(g);
    disp("Running: " + ferretName + " | " + sideName + " | " + groupName);

    % Driven units for this group from Excel
    preselected_ids = Tsum.DrivenUnit(Tsum.GroupName == groupName).';
    preselected_ids = double(preselected_ids);
    disp("Preselected driven unit IDs: " + num2str(preselected_ids));


    % Find matching group folder

    groupPath = "";

    for ff = 1:numel(allGroupFolders)

        folderName = string(allGroupFolders(ff).name);
        pattern = groupName + "(?!\d)";

        if ~isempty(regexp(folderName, pattern, "once"))
            groupPath = string(fullfile( allGroupFolders(ff).folder, allGroupFolders(ff).name));

            break
        end
    end

    if groupPath == ""
        warning("No folder containing %s was found. Skipping.", groupName);
        continue
    end

    % Build paths automatically

    folderPath = fullfile(groupPath, "recording_info.csv");
    bad_block_path = fullfile(groupPath, "bad_blocks.csv");
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


    runOneGroup(groupPath, phyPath, folderPath, bad_block_path, preselected_ids, ferretName, sideName, groupName, sampling_rate, deg_map, post_win, late_post_win, min_trials, alpha_gate);

end

disp("All groups finished.");

%% Spatial tuning analysis for individual recording groups

function runOneGroup(groupPath, phyPath, folderPath, bad_block_path, preselected_ids, ferretName, sideName, groupName, sampling_rate, deg_map, post_win, late_post_win, min_trials, alpha_gate)

close all;

% Save name for this group

saveFileName = "SpatialTuning_" + ferretName + "_" + sideName + "_" + groupName + ".mat";
saveFilePath = fullfile(phyPath, saveFileName);

% Load exact behavior file

groupForFile = groupName;

if ferretName == "Ursula"
    groupForFile = regexprep(groupName, "^Group_?", "G");
end

behaviorFile = fullfile(phyPath,ferretName + "_" + sideName + "_" + groupForFile + ".mat");

if ~isfile(behaviorFile)
    error("Behavioural data file not found: " + behaviorFile);
end

S = load(behaviorFile, 'onset_times', 'Behavior_');

onset_times = S.onset_times;
Behavior_ = S.Behavior_;


%% Go to phy folder
oldFolder = pwd;
cleanupObj = onCleanup(@() cd(oldFolder));

cd(phyPath);

%% Load spike sorting and session data

% Loading
Cinfo = readtable('cluster_info.tsv','FileType','text','Delimiter','\t');
valid_clusters = Cinfo.cluster_id;

spike_times_all = double(readNPY('spike_times.npy'));     % samples
spike_clusters_all = double(readNPY('spike_clusters.npy'));  % unit IDs

keep_idx = ismember(spike_clusters_all, valid_clusters);
spike_times_all = spike_times_all(keep_idx);
spike_clusters_all = spike_clusters_all(keep_idx);

Sessionss = generateSessionCells(folderPath, bad_block_path);
McStStimOnsetTimes = onset_times(~cellfun('isempty',onset_times));
Behaviors = Behavior_(~cellfun('isempty',Behavior_));

% Select previously identified driven units
all_units = unique(spike_clusters_all(:))';
if isempty(preselected_ids)
    units_to_run = all_units;
else
    units_to_run = intersect(all_units, preselected_ids, 'stable');
end
nU = numel(units_to_run);

% Initialise output variables
Label = strings(nU,1);       % "Head"/"World"/"NotTuned"/"FitError"/"No min trial"
AIC_H = nan(nU,1);
AIC_W = nan(nU,1);
Fit_head = nan(nU,1);
Fit_world = nan(nU,1);
FitWeight = nan(nU,1);
ModelPref = nan(nU,1);
nTrials = zeros(nU,1);
nTrials_l = zeros(nU,1);

% Analyse each driven unit
for k = 1:nU
    cl_id = units_to_run(k);

    trial_head = [];
    trial_world = [];
    trial_count = [];
    trial_count_late = [];
    sess_id_all = [];

    %  Collect trials from all sessions & pool
    for s = 1:numel(Sessionss)

        if isempty(Sessionss{s}), continue; end
        if isempty(Behaviors{s}) || ischar(Behaviors{s}) || isstring(Behaviors{s})
            continue;
        end
        beh = Behaviors{s}; if width(beh) < 15, continue; end  % skip FRAs

        csr = beh.CenterSpoutRotation;   % deg
        sloc = beh.Speaker_Location;      % index into deg_map
        onset = McStStimOnsetTimes{s};

        [t0, t1] = bounds(Sessionss{s});

        % Extract spikes for the current unit and session
        in_sess = (spike_clusters_all == cl_id) & (spike_times_all >= t0) & (spike_times_all <= t1);
        if ~any(in_sess), continue; end
        sp_s = (spike_times_all(in_sess) - t0) / sampling_rate;  % seconds

        th = []; tw = []; yc = []; ycl = [];
        for tr = 1:numel(onset)
            if isnan(sloc(tr)), continue; end

            % Calculate world- and head-centred sound angles
            wa = deg_map(sloc(tr));
            head_dir = mod(csr(tr), 360) - 180;
            ha = mod(head_dir - wa + 180, 360) - 180;

            if abs(ha) == 180, ha = -180; end
            if abs(wa) == 180, wa = -180; end

            % Count spikes within each response window
            s_rel = sp_s - onset(tr);
            cnt = sum(s_rel >= post_win(1) & s_rel < post_win(2));
            cnt_late = sum(s_rel >= late_post_win(1) & s_rel < late_post_win(2));

            th(end+1,1) = ha;
            tw(end+1,1) = wa;
            yc(end+1,1) = cnt;
            ycl(end+1,1) = cnt_late;
        end

        if ~isempty(yc)
            trial_head = [trial_head; th];
            trial_world = [trial_world; tw];
            trial_count = [trial_count; yc];
            trial_count_late = [trial_count_late; ycl];
            sess_id_all = [sess_id_all; s*ones(size(yc))];
        end
    end

    % counts
    nTrials(k) = numel(trial_count);
    nTrials_l(k) = numel(trial_count_late);

    if nTrials(k) < min_trials || nTrials_l(k) < min_trials
        Label(k) = "No min trial";
        continue;
    end

    % Represent sound angles using circular predictors
    Xh = [cosd(trial_head), sind(trial_head)];
    Xw = [cosd(trial_world), sind(trial_world)];
    X = [Xh Xw];

    % Check predictor variability
    predictorRange = max(X,[],1) - min(X,[],1);
    disp("Unit " + cl_id + " | Predictor ranges (h1, h2, w1, w2): " + num2str(predictorRange));

    y = trial_count;
    y_l = trial_count_late;

    try
        % Build tables with session as categorical (random intercept)
        tbl = table(y, Xh(:,1), Xh(:,2), Xw(:,1), Xw(:,2), categorical(sess_id_all),'VariableNames', {'y','h1','h2','w1','w2','sess'});
        tbl_l = table(y_l, Xh(:,1), Xh(:,2), Xw(:,1), Xw(:,2), categorical(sess_id_all),'VariableNames', {'y_1','h1','h2','w1','w2','sess'});

        % GLME fits with random intercept per session
        % Post window
        mC = fitglme(tbl, 'y ~ 1 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');
        mFull = fitglme(tbl, 'y ~ h1+h2+w1+w2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');

        % Late window
        mC_l = fitglme(tbl_l, 'y_1 ~ 1 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');
        mFull_l = fitglme(tbl_l, 'y_1 ~ h1+h2+w1+w2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');

        % Full vs Constant (Simple manual calculation from the log-likelihoods, as there is no deviance function in fitmle)
        LR_F = max(2*(mFull.LogLikelihood - mC.LogLikelihood), 0);
        df_F = max(mFull.NumEstimatedCoefficients - mC.NumEstimatedCoefficients, 0);
        pF = (df_F==0 || LR_F==0) * 1 + (df_F>0 & LR_F>0) * (1 - chi2cdf(LR_F, df_F));

        LR_Fl = max(2*(mFull_l.LogLikelihood - mC_l.LogLikelihood), 0);
        df_Fl = max(mFull_l.NumEstimatedCoefficients - mC_l.NumEstimatedCoefficients, 0);
        pFl = (df_Fl==0 || LR_Fl==0) * 1 + (df_Fl>0 & LR_Fl>0) * (1 - chi2cdf(LR_Fl, df_Fl));

        % Assess spatial tuning in both response windows
        tuned_full = (pF < alpha_gate) && (LR_F > 0);
        tuned_full_l = (pFl < alpha_gate) && (LR_Fl > 0);

        if ~(tuned_full || tuned_full_l)
            Label(k) = "NotTuned";
            continue;
        end

        % Prioritise onset tuning and classify reference frames using AIC
        if tuned_full
            mH = fitglme(tbl, 'y ~ h1+h2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');

            mW = fitglme(tbl, 'y ~ w1+w2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');

            AIC_H(k) = mH.ModelCriterion.AIC;
            AIC_W(k) = mW.ModelCriterion.AIC;

            if AIC_H(k) < AIC_W(k), Label(k) = "Head"; else, Label(k) = "World"; end

            % Model-fit rate using log-likelihoods (we do not have devience in fitglme) (relative to Full)
            LR_H = max(2*(mH.LogLikelihood - mC.LogLikelihood), 0);
            LR_W = max(2*(mW.LogLikelihood - mC.LogLikelihood), 0);
            denom = max(LR_F, eps);

            % Store the full-model likelihood improvement as the fit weight
            FitWeight(k) = LR_F;
            Fit_head(k)  = LR_H / denom;
            Fit_world(k) = LR_W / denom;
            ModelPref(k) = Fit_head(k) - Fit_world(k);

        else % tuned only in late window
            mH_l = fitglme(tbl_l, 'y_1 ~ h1+h2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');
            mW_l = fitglme(tbl_l, 'y_1 ~ w1+w2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');

            AIC_H(k) = mH_l.ModelCriterion.AIC;
            AIC_W(k) = mW_l.ModelCriterion.AIC;

            if AIC_H(k) < AIC_W(k), Label(k) = "Head"; else, Label(k) = "World"; end

            LR_Hl = max(2*(mH_l.LogLikelihood - mC_l.LogLikelihood), 0);
            LR_Wl = max(2*(mW_l.LogLikelihood - mC_l.LogLikelihood), 0);
            denom = max(LR_Fl, eps);
            % Store the full-model likelihood improvement as the fit weight
            FitWeight(k) = LR_Fl;
            Fit_head(k)  = LR_Hl / denom;
            Fit_world(k) = LR_Wl / denom;
            ModelPref(k) = Fit_head(k) - Fit_world(k);
        end

    catch
        disp("Unit " + cl_id + ": " + ME.message)
        Label(k) = "FitError";
    end
end


%% Save

save(saveFilePath, 'Fit_head', 'Fit_world', 'Label', 'ModelPref','preselected_ids', 'units_to_run', ...
    'AIC_H', 'AIC_W', 'nTrials', 'nTrials_l','FitWeight', 'ferretName', 'sideName', 'groupName');


disp("Results saved to: " + saveFilePath);

clear S onset_times Behavior_  McStStimOnsetTimes Behaviors
close all;

end