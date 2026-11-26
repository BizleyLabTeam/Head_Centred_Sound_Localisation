%% CompareOnsetOffsetTuning
% Assess onset and offset responsiveness and independently classify
% spatial tuning in both response periods to examine temporal changes
% in reference-frame tuning.
%
% Author: Nadia Aghili (2026)
%
% Inputs:
%   - Summary table containing driven unit IDs (.xlsx)
%   - Stimulus onset times and behavioural data (.mat)
%   - Recording information and optional bad-block information (.csv)
%   - Spike sorting outputs (.npy and .tsv)
%
% Outputs (.mat):
%   - Unit responsiveness classifications (Class)
%   - Onset and offset spatial tuning labels (Label_On, Label_Off)
%   - Head- and world-centred model fit scores for each response period
%   - Model preference values for onset and offset responses

% clc;
% clear;
% close all;

% % % summaryExcel = "Summary_Table.xlsx";
% % % ferretName = "Crumble";
% % % sideName = "Right";
% % % basePath = "D:\Stephen_Nadia_Jenny\Crumble_RESULTS\Left";

sampling_rate = 20000;  % Hz

deg_map = [150 120 90 60 30 0 -30 -60 -90 -120 -150 -180];


%% Analysis parameters
min_sessions = 0.25;
baseline_win = [-0.05, 0];   % for onset gate
early_win = [ 0, 0.05];   % onset (50 ms)
late_pre_win = [0.2, 0.25];  % for offset gate
late_post_win = [0.25, 0.3];  % offset (50 ms)
alpha_glm = 0.05;
onset_win  = [0 0.15];
offset_win = [0.25 0.4];
d_min = 0.2;
min_trials = 20;

%%
% READ EXCEL

Tsum = readtable(summaryExcel);
Tsum.FerretName = string(Tsum.FerretName);
Tsum.Side = string(Tsum.Side);
Tsum.GroupName  = string(Tsum.GroupName);
Tsum = Tsum(Tsum.FerretName == ferretName & Tsum.Side == sideName, :);

if isempty(Tsum)
    error("No matching data found in the summary table.");
end

groupList = unique(Tsum.GroupName, 'stable');

%%
% FIND GROUP FOLDERS
%

allGroupFolders = dir(fullfile(basePath,ferretName + "_*_Group*"));
allGroupFolders = allGroupFolders([allGroupFolders.isdir]);

if isempty(allGroupFolders)
    error("No group folders found in: " + basePath);
end

%%
% RUN GROUP BY GROUP
for g = 1:numel(groupList)

    groupName = groupList(g);
    disp("Running: " + ferretName + " | " + sideName + " | " + groupName);

    %% Driven units for this group from Excel

    preselected_ids = Tsum.DrivenUnit(Tsum.GroupName == groupName).';
    preselected_ids = double(preselected_ids);

    disp("Preselected units: " + num2str(preselected_ids));

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
        warning("No folder containing %s was found. Skipping.", groupName);
        continue
    end

    %% Build paths automatically

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

    %% Run this group

    runOneGroup(phyPath, folderPath, bad_block_path, preselected_ids, ferretName, sideName, groupName, sampling_rate, deg_map, ...
        late_post_win, min_trials, baseline_win, early_win, late_pre_win, onset_win, offset_win, d_min, alpha_glm, min_sessions);

end

fprintf("\nAll groups finished.\n");

%% FUNCTION

function runOneGroup(phyPath, folderPath, bad_block_path, preselected_ids, ferretName, sideName, groupName, sampling_rate, deg_map, ...
    late_post_win, min_trials, baseline_win, early_win, late_pre_win, onset_win, offset_win, d_min, alpha_glm, min_sessions)

close all;

%% Save name for this group
saveFileName = "OnsetOffsetTuning_" + ferretName + "_" + sideName + "_" + groupName + ".mat";
saveFilePath = fullfile(phyPath, saveFileName);

%% Load behavioural data

groupForFile = groupName;

if ferretName == "Ursula"
    groupForFile = regexprep(groupName, "^Group_?", "G");
end

behaviorFile = fullfile(phyPath, ferretName + "_" + sideName + "_" + groupForFile + ".mat");

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

%% Load session information and spike sorting data
Sessionss = generateSessionCells(folderPath, bad_block_path);
McStStimOnsetTimes = onset_times(~cellfun('isempty',onset_times));
Behaviors = Behavior_(~cellfun('isempty',Behavior_));
Cinfo = readtable('cluster_info.tsv','FileType','text','Delimiter','\t');
valid_clusters = Cinfo.cluster_id;
chan_of_clust = Cinfo.ch;
spike_times_all = double(readNPY('spike_times.npy'));
spike_clusters_all = double(readNPY('spike_clusters.npy'));

keep_idx = ismember(spike_clusters_all, valid_clusters);

spike_times_all = spike_times_all(keep_idx);
spike_clusters_all = spike_clusters_all(keep_idx);

len_baseline = diff(baseline_win);
len_early = diff(early_win);
len_lpre = diff(late_pre_win);
len_lpost = diff(late_post_win);
driven_units = preselected_ids(:)';
nU = numel(driven_units);

% Onset/Offset/Both
n_on   = zeros(nU,1);
n_off  = zeros(nU,1);
n_both = zeros(nU,1);
n_any  = zeros(nU,1);
Class  = strings(nU,1);  % "Both"/ "Onset-only"/ "Offset-only"/ "Mixed-across-sessions"/ "None"

%% Assess onset and offset responsiveness for each unit
for ui = 1:nU
    uid = driven_units(ui);
    on_s  = false(numel(Sessionss),1);
    off_s = false(numel(Sessionss),1);
    valid_sess_count = 0;

    for s = 1:numel(Sessionss)
        if isempty(Sessionss{s}), continue; end
        if isempty(Behaviors{s}) || ischar(Behaviors{s}) || isstring(Behaviors{s})
            continue;
        end

        beh = Behaviors{s};
        if width(beh) < 15, continue; end

        onset_s = McStStimOnsetTimes{s};
        [t0,t1] = bounds(Sessionss{s});

        in_sess = (spike_clusters_all==uid) & (spike_times_all>=t0) & (spike_times_all<=t1);

        if ~any(in_sess), continue; end
        valid_sess_count = valid_sess_count + 1;

        sp_s = (spike_times_all(in_sess)-t0)/sampling_rate;

        % per-trial counts
        pre_on=[]; post_on=[]; pre_of=[]; post_of=[];
        for tr = 1:numel(onset_s)

            if isnan(onset_s(tr)), continue; end
            r = sp_s - onset_s(tr);
            pre_on(end+1,1) = sum(r >= baseline_win(1) & r < baseline_win(2));  % -50-0
            post_on(end+1,1) = sum(r >= early_win(1) & r < early_win(2));  % 0-50
            pre_of(end+1,1) = sum(r >= late_pre_win(1) & r < late_pre_win(2)); % 200-250
            post_of(end+1,1) = sum(r >= late_post_win(1) & r < late_post_win(2)); % 250-300
        end

        % onset test
        % onset test
        try
            n_e = min(numel(pre_on), numel(post_on));

            if n_e >= min_trials

                pre  = pre_on(1:n_e);
                post = post_on(1:n_e);

                pre_fr  = pre/len_baseline;
                post_fr = post/len_early;

                dvec = post_fr - pre_fr;
                dz   = mean(dvec)/(std(dvec)+eps);

                y = [pre(:); post(:)];
                epoch = [zeros(n_e,1); ones(n_e,1)];

                T = table(y,epoch,'VariableNames',{'y','epoch'});

                m0 = fitglm(T,'y~1','Distribution','poisson');
                m1 = fitglm(T,'y~1+epoch','Distribution','poisson');

                LR = m0.Deviance - m1.Deviance;
                p  = 1 - chi2cdf(max(LR,0),1);

                % PSTH gate (same as driven-unit code)
                edges = -0.1:0.005:0.4;
                h = zeros(1,numel(edges)-1);

                for tr = 1:numel(onset_s)
                    if isnan(onset_s(tr)), continue; end
                    r = sp_s - onset_s(tr);
                    h = h + histcounts(r,edges);
                end

                psth = h/(numel(onset_s)*0.005);
                t = edges(1:end-1);

                idx  = t>=early_win(1) & t<early_win(2);
                base = t>=baseline_win(1) & t<baseline_win(2);

                resp_mean = mean(psth(idx));
                base_mean = mean(psth(base));

                peak  = max(psth(idx));
                sharp = peak/(mean(psth(idx))+eps);

                is_sharp_exc = sharp > 1.5;
                is_real_exc  = resp_mean > base_mean*1.2;

                is_real_sup = resp_mean < base_mean*0.8;

                resp_min = mean(mink(psth(idx),3));
                sup_depth = base_mean - resp_min;

                is_strong_sup = sup_depth > 0.2*base_mean;

                pass_exc = is_real_exc && is_sharp_exc;
                pass_sup = is_real_sup && is_strong_sup;

                is_real = pass_exc || pass_sup;

                sig_flag = (p<=alpha_glm) && (abs(dz)>=d_min) && is_real;

                on_s(s) = sig_flag;

            end
        catch
        end

        % offset test
        try
            n_l = min(numel(pre_of), numel(post_of));

            if n_l >= min_trials

                pre  = pre_of(1:n_l);
                post = post_of(1:n_l);

                pre_fr  = pre/len_lpre;
                post_fr = post/len_lpost;

                dvec = post_fr - pre_fr;
                dz   = mean(dvec)/(std(dvec)+eps);

                y = [pre(:); post(:)];
                epoch = [zeros(n_l,1); ones(n_l,1)];

                T = table(y,epoch,'VariableNames',{'y','epoch'});

                m0 = fitglm(T,'y~1','Distribution','poisson');
                m1 = fitglm(T,'y~1+epoch','Distribution','poisson');

                LR = m0.Deviance - m1.Deviance;
                p  = 1 - chi2cdf(max(LR,0),1);

                % PSTH gate (same as driven-unit code)
                edges = -0.1:0.005:0.4;
                h = zeros(1,numel(edges)-1);

                for tr = 1:numel(onset_s)
                    if isnan(onset_s(tr)), continue; end
                    r = sp_s - onset_s(tr);
                    h = h + histcounts(r,edges);
                end

                psth = h/(numel(onset_s)*0.005);
                t = edges(1:end-1);

                idx  = t>=late_post_win(1) & t<late_post_win(2);
                base = t>=late_pre_win(1) & t<late_pre_win(2);

                resp_mean = mean(psth(idx));
                base_mean = mean(psth(base));

                peak  = max(psth(idx));
                sharp = peak/(mean(psth(idx))+eps);

                is_sharp_exc = sharp > 1.5;
                is_real_exc  = resp_mean > base_mean*1.2;

                is_real_sup = resp_mean < base_mean*0.8;

                resp_min = mean(mink(psth(idx),3));
                sup_depth = base_mean - resp_min;

                is_strong_sup = sup_depth > 0.2*base_mean;

                pass_exc = is_real_exc && is_sharp_exc;
                pass_sup = is_real_sup && is_strong_sup;

                is_real = pass_exc || pass_sup;

                sig_flag = (p<=alpha_glm) && (abs(dz)>=d_min) && is_real;

                off_s(s) = sig_flag;

            end
        catch
        end
    end


    both_s = on_s & off_s;
    any_s = on_s | off_s;

    n_on(ui) = sum(on_s);
    n_off(ui) = sum(off_s);
    n_both(ui) = sum(both_s);
    n_any(ui) = sum(any_s);

    prop_both = n_both(ui) / valid_sess_count;
    prop_on = n_on(ui)  / valid_sess_count;
    prop_off = n_off(ui) / valid_sess_count;
    prop_any = n_any(ui) / valid_sess_count;

    if prop_both >= min_sessions
        Class(ui) = "Both";
    elseif prop_on >= min_sessions
        Class(ui) = "Onset-only";
    elseif prop_off >= min_sessions
        Class(ui) = "Offset-only";
    elseif prop_any >= min_sessions
        Class(ui) = "Mixed_across_session";
    else
        Class(ui) = "None";
    end
end


Both_IDs = driven_units(Class=="Both").';
OnsetOnly_IDs = driven_units(Class=="Onset-only").';
OffsetOnly_IDs = driven_units(Class=="Offset-only").';
Mixed_across_session_IDs = driven_units(Class=="Mixed_across_session").';
NoneIDss = driven_units(Class=="None").';
Driven_Pass_IDs = driven_units(Class ~= "None");


%%  Tuning for "BOTH" units (Head / World / Mixed)

min_trials_phase = 40;
mix_thr = 0.2;

both_ids = Both_IDs(:)';
nb = numel(both_ids);

Label_On = strings(nb,1); Label_Off = strings(nb,1);
FitHead_On = nan(nb,1); FitWorld_On = nan(nb,1); ModelPref_On = nan(nb,1);
FitHead_Off= nan(nb,1); FitWorld_Off= nan(nb,1); ModelPref_Off= nan(nb,1);

for k = 1:nb
    uid = both_ids(k);
    th_on=[]; tw_on=[]; y_on=[]; sess_on=[];
    th_off=[];tw_off=[]; y_off=[]; sess_off=[];

    for s = 1:numel(Sessionss)
        if isempty(Sessionss{s}), continue; end
        if isempty(Behaviors{s}) || ischar(Behaviors{s}) || isstring(Behaviors{s})
            continue;
        end

        beh = Behaviors{s};
        if width(beh)<15, continue; end
        onset_s = McStStimOnsetTimes{s};
        csr  = beh.CenterSpoutRotation;
        sloc = beh.Speaker_Location;

        [t0,t1] = bounds(Sessionss{s});
        in_sess = (spike_clusters_all==uid) & (spike_times_all>=t0) & (spike_times_all<=t1);
        if ~any(in_sess), continue; end
        sp_s = (spike_times_all(in_sess)-t0)/sampling_rate;

        for tr = 1:numel(onset_s)
            if isnan(sloc(tr)), continue; end

            wa = deg_map(sloc(tr));
            head_dir = mod(csr(tr), 360) - 180;
            ha = mod(head_dir - wa + 180, 360) - 180;

            if abs(ha)==180, ha=-180; end
            if abs(wa)==180, wa=-180; end

            r = sp_s - onset_s(tr);

            y_on(end+1,1) = sum(r>=onset_win(1)  & r<onset_win(2));
            th_on(end+1,1) = ha;
            tw_on(end+1,1) = wa;
            sess_on(end+1,1) = s;

            y_off(end+1,1) = sum(r>=offset_win(1) & r<offset_win(2));
            th_off(end+1,1) = ha;
            tw_off(end+1,1) = wa;
            sess_off(end+1,1) = s;
        end
    end

    [Label_On(k), FitHead_On(k), FitWorld_On(k), ModelPref_On(k)]  = label_phase(y_on,  th_on,  tw_on,  sess_on,  mix_thr, min_trials_phase);
    [Label_Off(k), FitHead_Off(k), FitWorld_Off(k), ModelPref_Off(k)] = label_phase(y_off, th_off, tw_off, sess_off, mix_thr, min_trials_phase);
end

%% Save results
save(saveFilePath, 'Class', 'driven_units', 'Both_IDs', 'OnsetOnly_IDs', 'OffsetOnly_IDs', 'Mixed_across_session_IDs', ...
    'NoneIDss', 'Label_On', 'Label_Off','FitHead_On', 'FitWorld_On', 'FitHead_Off', 'FitWorld_Off', ...
    'ModelPref_On', 'ModelPref_Off', 'Driven_Pass_IDs', 'preselected_ids');

disp("Results saved to: " + saveFilePath);


close all;

end


function [lab,fh,fw,mp] = label_phase(y,th,tw,sess, mix_thr, min_trials_phase)

alpha_gate = 0.05;

if numel(y) < min_trials_phase
    lab = "InsufficientTrials";
    fh = NaN;
    fw = NaN;
    mp = NaN;
    return;
end

Xh = [cosd(th), sind(th)];
Xw = [cosd(tw), sind(tw)];

% Exclude the head-centred cosine predictor if it is constant
use_h1 = numel(unique(Xh(:,1))) > 1;

tbl = table(y, Xh(:,1), Xh(:,2), Xw(:,1), Xw(:,2), categorical(sess),'VariableNames', {'y','h1','h2','w1','w2','sess'});

try
    mC = fitglme(tbl,'y ~ 1 + (1|sess)','Distribution','Poisson','Link','log','FitMethod','Laplace');

    if use_h1
        mF = fitglme(tbl,'y ~ h1+h2+w1+w2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');

        mH = fitglme(tbl,'y ~ h1+h2 + (1|sess)','Distribution','Poisson','Link','log','FitMethod','Laplace');
    else
        mF = fitglme(tbl,'y ~ h2+w1+w2 + (1|sess)','Distribution','Poisson','Link','log','FitMethod','Laplace');

        mH = fitglme(tbl,'y ~ h2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');
    end

    mW = fitglme(tbl,'y ~ w1+w2 + (1|sess)', 'Distribution','Poisson','Link','log','FitMethod','Laplace');

    LR_F = 2*(mF.LogLikelihood - mC.LogLikelihood);
    df_F = max(mF.NumEstimatedCoefficients - mC.NumEstimatedCoefficients, 0);

    if LR_F <= 0 || df_F == 0
        pF = 1;
    else
        pF = 1 - chi2cdf(LR_F, df_F);
    end

    if ~(isfinite(pF) && pF < alpha_gate)
        lab = "NotTuned";
        fh = NaN;
        fw = NaN;
        mp = NaN;
        return;
    end

    base_label = "World";
    if mH.ModelCriterion.AIC < mW.ModelCriterion.AIC
        base_label = "Head";
    end

    % Calculate relative model fit scores and model preference
    Dc = -2*mC.LogLikelihood;
    Df = -2*mF.LogLikelihood;
    Dh = -2*mH.LogLikelihood;
    Dw = -2*mW.LogLikelihood;

    denom = max(Dc - Df, eps);

    fh = max(Dc - Dh, 0) / denom;
    fw = max(Dc - Dw, 0) / denom;
    mp = fh - fw;

    lab = base_label;

    if abs(mp) <= mix_thr
        lab = "Mixed";
    end

catch
    disp('Head up: Error')
    lab = "FitError";
    fh = NaN;
    fw = NaN;
    mp = NaN;
end

end