%% CalculateSRFMetrics
% Calculate head- and world-centred spatial receptive fields (SRFs)
% and their associated SEMs, and quantify ERRF width, centroid,
% preferred sound location and modulation depth.
%
% Author: Nadia Aghili (2026)
%
% Inputs:
%   - Summary table containing unit IDs and spatial tuning labels (.xlsx)
%   - Stimulus onset times and behavioural data (.mat)
%   - Recording information (.csv)
%   - Spike sorting outputs (.npy and .tsv)
%
% Outputs (.mat):
%   - Unit IDs and sound angles
%   - Z-scored SRFs and associated SEMs
%   - SRFs used for metric calculations
%   - ERRF widths, centroids, preferred locations and modulation depths

% clc
% clear
% close all


% % % summaryExcel = "Summary_Table.xlsx";
% % % ferretName = "Crumble";
% % % sideName = "Right";
% % % basePath = "D:\Stephen_Nadia_Jenny\Crumble_RESULTS\Right"

sampling_rate = 20000;
% Define response and baseline windows (s)
time_window = [0 0.25];
pre_win = [-0.1 0];
% Map loudspeaker indices to world-centred angles
deg_map = [150 120 90 60 30 0 -30 -60 -90 -120 -150 -180];


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

    pick_cindx = Tsum.DrivenUnit(Tsum.GroupName == groupName).';
    pick_cindx = double(pick_cindx);

    disp("Preselected driven unit IDs: " + num2str(pick_cindx));

    Label = string(Tsum.DrivenLabel(Tsum.GroupName == groupName)).';
    ModelPref = string(Tsum.ModelPreference(Tsum.GroupName == groupName).');
    ModelPref = str2double(ModelPref);


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

    runOneGroup(phyPath, folderPath, bad_block_path, pick_cindx, Label, ferretName, sideName, groupName, sampling_rate, deg_map, time_window, pre_win);

end

disp("All groups finished.");


%% FUNCTION

function runOneGroup(phyPath, folderPath, bad_block_path, pick_cindx, Label, ferretName, sideName, groupName, sampling_rate, deg_map, time_window, pre_win)

close all;

%% Save name for this group

saveFileName = "SRFMetrics_" + ferretName + "_" + sideName + "_" + groupName + ".mat";
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

%% Original CODE

%%%%%%%%%%%%%%% SRF CODE (ERRF, Centroid, and prefloc and modulation) %%%%%%%%%%%%%%%

keepLabel = Label ~= "NotTuned" & Label ~= "FitError";
pick_cindx = pick_cindx(keepLabel);

if isempty(pick_cindx)
    warning("No spatially tuned units found: " + ferretName + " | " + sideName + " | " + groupName);
    return
end

Label = Label(keepLabel);

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

aa = 0;

nAngles = numel(deg_map);
nUnits = numel(pick_cindx);

SRF_head_z_all = nan(nAngles,nUnits);
SRF_world_z_all = nan(nAngles,nUnits);

SRF_head_metric_all = nan(nAngles,nUnits);
SRF_world_metric_all = nan(nAngles,nUnits);

SRF_head_sem_all = nan(nAngles,nUnits);
SRF_world_sem_all = nan(nAngles,nUnits);

ERRF_width_head = nan(1,nUnits);
ERRF_width_world = nan(1,nUnits);

preferred_location_h = nan(1,nUnits);
preferred_location_w = nan(1,nUnits);

centroid_deg_h = nan(1,nUnits);
centroid_deg_w = nan(1,nUnits);

MD_head = nan(1,nUnits);
MD_world = nan(1,nUnits);


%% main loop
for cl_id = pick_cindx

    aa = aa+1;

    trial_spikes = {};
    trial_head = [];
    trial_world = [];
    trial_session = [];
    trial_rate = [];
    trial_csr = [];

    % Collect trials across sessions

    for s = 1:numel(Sessionss)

        rate_post = [];
        rate_pre = [];

        % if isempty(Behaviors{s}), continue, end
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
        % Extract spikes for the current unit and session
        in_sess = (spike_clusters_all == cl_id) & (spike_times_all >= t0) & (spike_times_all <= t1);
        spikes_s = (spike_times_all(in_sess) - t0) / sampling_rate;  % s

        for tr = 1:numel(onset)
            if isnan(sloc(tr)), continue; end
            % Calculate world- and head-centred sound angles
            wa = deg_map(sloc(tr));
            head_dir = mod(csr(tr), 360) - 180;
            ha = mod(head_dir - wa + 180, 360) - 180;

            if abs(ha) == 180, ha = -180; end
            if abs(wa) == 180, wa = -180; end
            % Extract spikes within response and baseline windows
            sp_post = spikes_s(spikes_s >= onset(tr)+time_window(1) & spikes_s < onset(tr)+time_window(2)) - onset(tr);
            sp_pre = spikes_s(spikes_s >= onset(tr)+pre_win(1) & spikes_s < onset(tr)+pre_win(2)) - onset(tr);
            % Convert spike counts to firing rates (Hz)
            rate_post(end+1) = numel(sp_post)/diff(time_window);
            rate_pre(end+1)  = numel(sp_pre)/diff(pre_win);

            trial_head(end+1) = ha;
            trial_world(end+1) = wa;
            trial_session(end+1) = s;
            trial_csr(end+1) = csr(tr);
        end

        % z-scoring

        baseline_mean = mean(rate_pre,'omitnan');
        baseline_std  = std(rate_pre,'omitnan');

        z_rates = (rate_post - baseline_mean) ./ baseline_std;

        trial_rate = [trial_rate z_rates];

    end

    nAngles = numel(deg_map);

    %% Calculate mean SRFs and SEMs across trials
    SRF_head_mu = nan(nAngles,1);
    SRF_head_sem = nan(nAngles,1);
    SRF_world_mu = nan(nAngles,1);
    SRF_world_sem = nan(nAngles,1);

    for a = 1:nAngles
        % Head-centred SRF (group by head angle)
        idxH = trial_head == deg_map(a);
        rH = trial_rate(idxH);
        nH = sum(~isnan(rH));
        if nH > 0
            SRF_head_mu(a) = mean(rH, 'omitnan');
            if nH > 1
                SRF_head_sem(a) = std(rH, 0, 'omitnan') / sqrt(nH);
            else
                SRF_head_sem(a) = NaN;
            end
        end

        % World-centred SRF (group by world angle)
        idxW = trial_world == deg_map(a);
        rW = trial_rate(idxW);
        nW = sum(~isnan(rW));
        if nW > 0
            SRF_world_mu(a) = mean(rW, 'omitnan');
            if nW > 1
                SRF_world_sem(a) = std(rW, 0, 'omitnan') / sqrt(nW);
            else
                SRF_world_sem(a) = NaN;
            end
        end
    end

    %% PREPARE HEAD AND WORLD SRFs

    SRF_all = {SRF_head_mu(:); SRF_world_mu(:)};
    ERRF_all = nan(2,1);
    Preferred_all = nan(2,1);
    Centroid_all = nan(2,1);
    MD_all = nan(2,1);
    SRF_for_metrics_all = cell(2,1);

    %% CALCULATE METRICS

    for frameIndex = 1:2

        x = SRF_all{frameIndex};

        % All 12 spatial bins must be valid
        if any(~isfinite(x))
            continue
        end

        % Shift only when negative values are present
        xForMetrics = x;

        if any(x < 0)
            xForMetrics = x - min(x);
        end

        SRF_for_metrics_all{frameIndex} = xForMetrics;

        % ERRF width
        ERRF_all(frameIndex) = ERRF_width_deg_new(deg_map,xForMetrics);

        % Preferred location
        [~,preferredIndex] = max(xForMetrics);
        Preferred_all(frameIndex) = deg_map(preferredIndex);

        % Centroid
        Centroid_all(frameIndex) = centroid_angle_deg_new( deg_map, xForMetrics);

        % Modulation depth in z-score units
        MD_all(frameIndex) = modulation_depth_new(xForMetrics);

    end

    % STORE ORIGINAL SRFs AND SEMs

    SRF_head_z_all(:,aa) = SRF_head_mu(:);
    SRF_world_z_all(:,aa) = SRF_world_mu(:);

    SRF_head_sem_all(:,aa) = SRF_head_sem(:);
    SRF_world_sem_all(:,aa) = SRF_world_sem(:);

    % STORE SRFs USED FOR METRICS
    SRF_head_metric_all(:,aa) = nan(numel(deg_map),1);
    SRF_world_metric_all(:,aa) = nan(numel(deg_map),1);

    if ~isempty(SRF_for_metrics_all{1})
        SRF_head_metric_all(:,aa) = SRF_for_metrics_all{1};
    end

    if ~isempty(SRF_for_metrics_all{2})
        SRF_world_metric_all(:,aa) = SRF_for_metrics_all{2};
    end

    % STORE METRICS

    ERRF_width_head(aa) = ERRF_all(1);
    ERRF_width_world(aa) = ERRF_all(2);

    preferred_location_h(aa) = Preferred_all(1);
    preferred_location_w(aa) = Preferred_all(2);

    centroid_deg_h(aa) = Centroid_all(1);
    centroid_deg_w(aa) = Centroid_all(2);

    MD_head(aa) = MD_all(1);
    MD_world(aa) = MD_all(2);
end

%% Save results
save(saveFilePath, 'ERRF_width_head', 'ERRF_width_world', 'preferred_location_h', ...
    'preferred_location_w', 'centroid_deg_h', 'centroid_deg_w', 'MD_head', 'MD_world', ...
    'SRF_head_z_all', 'SRF_world_z_all','SRF_head_metric_all', 'SRF_world_metric_all', 'SRF_head_sem_all', 'SRF_world_sem_all', 'pick_cindx', 'deg_map');

disp("Results saved to: " + saveFilePath);
close all;

end

function width_deg = ERRF_width_deg_new(deg,fr)
% Calculate ERRF width as the circular area under the SRF divided by its peak.

deg = deg(:);
fr  = fr(:);

deg_wrap = deg;
deg_wrap(deg_wrap < 0) = deg_wrap(deg_wrap < 0) + 360;

[deg_wrap,idx] = sort(deg_wrap);
fr = fr(idx);

% Close the circular response curve before integration
deg2 = [deg_wrap; deg_wrap(1)+360];
fr2  = [fr; fr(1)];

area_under = trapz(deg2,fr2);
peak_fr = max(fr);

if peak_fr <= 0
    width_deg = NaN;
else
    width_deg = area_under/peak_fr;
end

end


function centroid_deg = centroid_angle_deg_new(deg,fr)
% Calculate the response-weighted circular mean of sound angles.

deg = deg(:);
fr  = fr(:);

ok = ~isnan(deg) & ~isnan(fr);
deg = deg(ok);
fr  = fr(ok);

ang = deg*pi/180;

x = sum(fr .* cos(ang));
y = sum(fr .* sin(ang));

centroid_deg = rad2deg(atan2(y,x));

if centroid_deg == 180
    centroid_deg = -180;
end

end


function MD = modulation_depth_new(x)
% Calculate modulation depth as the difference between maximum and minimum responses.
x = x(:);
mx = max(x);
mn = min(x);
MD = mx - mn;
end