%% IdentifyDrivenUnits
% Identify stimulus-driven units based on onset and offset responses
% using Poisson GLMs, effect size, and PSTH-based response criteria.
% Sparse-firing units are excluded.
%
% Author: Nadia Aghili (2026)
%
% Inputs:
%   - Stimulus onset times and behavioural data (.mat)
%   - Recording information (.csv)
%   - Spike sorting outputs (.npy and .tsv)
%
% Output:
%   - driven_units: IDs of identified driven units.
%
% Note: This script is provided for reproducibility. Precomputed driven unit IDs are available in the summary table for subsequent analyses.

% clc;
% clear;
% close all;
warnState = warning;
warning('off', 'all');

sampling_rate = 20000;

baseline_win = [-0.05, 0];
early_win = [ 0, 0.05];
late_pre_win = [0.2, 0.25];
late_post_win = [0.25, 0.3];


alpha_glm = 0.05;
min_pairs = 20;
d_min = 0.2;

% Load spike sorting data
Cinfo = readtable(fullfile(phyPath, 'cluster_info.tsv'), 'FileType', 'text', 'Delimiter', '\t');

valid_clusters = Cinfo.cluster_id;

spike_times_all = double(readNPY(fullfile(phyPath, 'spike_times.npy')));
spike_clusters_all = double(readNPY(fullfile(phyPath, 'spike_clusters.npy')));

keep_idx = ismember(spike_clusters_all, valid_clusters);
spike_times_all = spike_times_all(keep_idx);
spike_clusters_all = spike_clusters_all(keep_idx);

Sessionss = generateSessionCells(folderPath, bad_block_path);
McStStimOnsetTimes = onset_times(~cellfun('isempty',onset_times));
Behaviors = Behavior_(~cellfun('isempty',Behavior_));

len_baseline = diff(baseline_win);
len_early = diff(early_win);
len_lpre = diff(late_pre_win);
len_lpost = diff(late_post_win);

all_units = unique(spike_clusters_all(:))';
nU = numel(all_units);

isDriven_glm = false(nU,1);

all_mean_fr = [];

for ii = 1:nU
    uid = all_units(ii);
    sess_flags = false(numel(Sessionss),1);
    valid_sess_count = 0;

    for s = 1:numel(Sessionss)

        if isempty(Sessionss{s}), continue; end
        if isempty(Behaviors{s}) || ischar(Behaviors{s}) || isstring(Behaviors{s}), continue; end
        if width(Behaviors{s}) < 15, continue; end   % To exclude Frequency Response Area (FRA) data from the analysis

        valid_sess_count = valid_sess_count + 1;
        onset = McStStimOnsetTimes{s};
        [t0, t1] = bounds(Sessionss{s});

        in_sess = (spike_clusters_all==uid) & (spike_times_all>=t0) & (spike_times_all<=t1);

        if ~any(in_sess), continue; end

        % Compute trial-wise spike counts for onset and offset response analyses

        sp_s = (spike_times_all(in_sess)-t0)/sampling_rate;

        pre_e=[]; post_e=[]; pre_l=[]; post_l=[];

        for tr = 1:numel(onset)
            r = sp_s - onset(tr);

            pre_e(end+1)  = sum(r>=baseline_win(1) & r<baseline_win(2));
            post_e(end+1) = sum(r>=early_win(1) & r<early_win(2));

            pre_l(end+1)  = sum(r>=late_pre_win(1) & r<late_pre_win(2));
            post_l(end+1) = sum(r>=late_post_win(1)& r<late_post_win(2));
        end

        sig_flag = false;

        %%  Onset response assessment

        if numel(pre_e) >= min_pairs
            n_e = min(numel(pre_e), numel(post_e));

            % Convert spike counts to firing rates (Hz)
            pre = pre_e(1:n_e);
            post = post_e(1:n_e);
            pre = pre(:);
            post = post(:);
            pre_fr = pre/len_baseline;
            post_fr = post/len_early;

            % Calculate the standardised change in firing rate (Cohen's dz)
            dvec = post_fr - pre_fr;
            dz = mean(dvec)/(std(dvec)+eps);

            % Fit null and full Poisson GLMs
            y = [pre; post];
            epoch = [zeros(numel(pre),1); ones(numel(post),1)];
            T=table(y,epoch,'VariableNames',{'y','epoch'});

            m0 = fitglm(T,'y~1','Distribution','poisson');
            m1 = fitglm(T,'y~1+epoch','Distribution','poisson');

            LR = m0.Deviance - m1.Deviance;
            p = 1 - chi2cdf(max(LR,0),1);

            % Compute stimulus-aligned PSTH using 5-ms bins
            edges = -0.1:0.005:0.4;
            h = zeros(1,numel(edges)-1);

            for tr = 1:numel(onset)
                r = sp_s - onset(tr);
                h = h + histcounts(r,edges);
            end

            psth = h/(numel(onset)*0.005);
            t = edges(1:end-1);

            idx = t>=early_win(1) & t<early_win(2);
            base = t>=baseline_win(1) & t<baseline_win(2);

            resp_mean = mean(psth(idx));
            base_mean = mean(psth(base));
            peak = max(psth(idx));
            sharp = peak / mean(psth(idx));

            % Evaluate excitatory response criteria
            is_sharp_exc = sharp > 1.5;
            is_real_exc = resp_mean > base_mean*1.2;

            % Evaluate suppressive response criteria
            is_real_sup = resp_mean < base_mean*0.8;
            resp_min = mean(mink(psth(idx),3));
            sup_depth = base_mean - resp_min;
            is_strong_sup = sup_depth > 0.2 * base_mean;

            pass_exc = is_real_exc && is_sharp_exc;
            pass_sup = is_real_sup && is_strong_sup;

            is_real = pass_exc || pass_sup;
            mean_fr = mean(psth);
            all_mean_fr(end+1) = mean_fr;

            sig_flag = sig_flag | ((p<=alpha_glm) && (abs(dz)>=d_min) && is_real);
        end

        %%  Offset response assessment

        if numel(pre_l) >= min_pairs

            % Convert spike counts to firing rates (Hz)
            pre = pre_l;
            post = post_l;
            pre_fr = pre/len_lpre;
            post_fr = post/len_lpost;

            % Calculate the standardised change in firing rate (Cohen's dz)
            dvec = post_fr - pre_fr;
            dz = mean(dvec)/(std(dvec)+eps);

            % Fit null and full Poisson GLMs
            pre = pre(:);
            post = post(:);
            y = [pre; post];
            epoch = [zeros(numel(pre),1); ones(numel(post),1)];
            T = table(y,epoch);

            m0 = fitglm(T,'y~1','Distribution','poisson');
            m1 = fitglm(T,'y~1+epoch','Distribution','poisson');

            LR = m0.Deviance - m1.Deviance;
            p = 1 - chi2cdf(max(LR,0),1);

            % Compute stimulus-aligned PSTH using 5-ms bins
            edges = -0.1:0.005:0.4;
            h = zeros(1,numel(edges)-1);

            for tr = 1:numel(onset)
                r = sp_s - onset(tr);
                h = h + histcounts(r,edges);
            end

            psth = h/(numel(onset)*0.005);
            t = edges(1:end-1);

            idx = t>=late_post_win(1) & t<late_post_win(2);
            base = t>=late_pre_win(1) & t<late_pre_win(2);

            resp_mean = mean(psth(idx));
            base_mean = mean(psth(base));
            peak = max(psth(idx));
            sharp = peak / mean(psth(idx));

            % Evaluate excitatory response criteria
            is_sharp_exc = sharp > 1.5;
            is_real_exc = resp_mean > base_mean*1.2;

            % Evaluate suppressive response criteria
            is_real_sup = resp_mean < base_mean*0.8;
            resp_min = mean(mink(psth(idx),3));
            sup_depth = base_mean - resp_min;
            is_strong_sup = sup_depth > 0.2 * base_mean;

            pass_exc = is_real_exc && is_sharp_exc;
            pass_sup = is_real_sup && is_strong_sup;

            is_real = pass_exc || pass_sup;

            mean_fr = mean(psth);
            all_mean_fr(end+1) = mean_fr;

            sig_flag = sig_flag | ((p<=alpha_glm) && (abs(dz)>=d_min) && is_real );

        end

        sess_flags(s) = sig_flag;
    end
    prop = sum(sess_flags) / valid_sess_count;
    isDriven_glm(ii) = prop >= 0.25;
    % isDriven_glm(ii) = sum(sess_flags) >= min_sessions;
end

%% spars unit removal

% Define the firing rate threshold as 20% of the median PSTH firing rate
thr_sparse = 0.2 * median(all_mean_fr,'omitnan');
driven_units = all_units(isDriven_glm);

keep_units = false(size(driven_units));

for k = 1:numel(driven_units)

    uid = driven_units(k);

    in_unit = spike_clusters_all == uid;
    % Calculate the overall firing rate of each driven unit
    fr_unit = numel(spike_times_all(in_unit)) / ((max(spike_times_all(in_unit)) - min(spike_times_all(in_unit))) / sampling_rate);

    keep_units(k) = fr_unit > thr_sparse;
end

% Retain driven units above the firing rate threshold
driven_units = driven_units(keep_units);

disp(['Number of driven units: ', num2str(numel(driven_units))]);
disp(['Driven unit IDs: ', num2str(driven_units)]);

% Save driven unit IDs
saveFileName = "DrivenUnits_" + ferretName + "_" + sideName + "_" + groupName + ".mat";
saveFilePath = fullfile(phyPath, saveFileName);
save(saveFilePath, 'driven_units');
disp("Results saved to: " + saveFilePath);

warning(warnState);