%% RunAnalysis
% Run the analyses using the three example recording groups provided.
%
% Author: Nadia Aghili (2026)
%
% Inputs:
%   - Example_Summary_Table.xlsx
%   - Post-sorting and behavioural data (ExampleData folder)
%   - Supporting MATLAB functions (Functions folder)
%
% Outputs (.mat):
%   - Driven unit identification results
%   - Spatial tuning labels and model fit scores
%   - Spatial receptive fields and associated metrics
%   - Onset and offset responsiveness and spatial tuning
%   - WPI values and permutation test results
%
% Results are saved in the corresponding recording group's phy folder.
%
% Example_Summary_Table.xlsx contains precomputed driven unit IDs, spatial
% tuning labels, model fits, model preference values, electrode
% depths and cortical field assignments.
%
% Driven unit identification and spatial tuning classification
% are provided for reproducibility. Subsequent analyses use the
% precomputed results from the summary table.
%
% Example units shown in the manuscript:
%   Head  - Crumble (F1901), Left, Group_3,  cluster ID 26
%   World - Sponge  (F1905), Left, Group3_1, cluster ID 23
%   Mixed - Ursula  (F1810), Left, Group5_2, cluster ID 14
%
% Each example dataset contains the post-sorting data for the
% entire recording group, not just the example unit.

clc;
clear;
close all;

%% Common inputs

codePath = fileparts(mfilename('fullpath'));
rootPath = fileparts(codePath);

addpath(codePath);
addpath(genpath(fullfile(rootPath, "Functions")));

summaryExcel = fullfile(rootPath, "ExampleData", "Example_Summary_Table.xlsx");

%% Select dataset

disp("1. Crumble (F1901) - Left - Group_3");
disp("2. Sponge  (F1905) - Left - Group3_1");
disp("3. Ursula  (F1810) - Left - Group5_2");
disp("0. Exit");

choice = input('Select dataset: ', 's');

switch choice
    case '1'
        ferretName = "Crumble";
        groupName = "Group_3";

    case '2'
        ferretName = "Sponge";
        groupName = "Group3_1";
    case '3'
        ferretName = "Ursula";
        groupName = "Group5_2";
    case '0'
        return;
    otherwise
        error("Invalid selection.");
end

sideName = "Left";
basePath = fullfile(rootPath, "ExampleData", ferretName, sideName);

assert(isfile(summaryExcel), "Summary table not found.");
assert(isfolder(basePath), "Data folder not found.");


%% Select analysis

while true

    disp("1. Identify driven units");
    disp("2. Identify spatially tuned units");
    disp("3. Calculate SRF metrics");
    disp("4. Compare onset and offset tuning");
    disp("5. Calculate WPI");
    disp("0. Exit");

    choice = input('Select analysis: ', 's');

    switch choice

        case '1'
            % Provided for reproducibility
            % Additional inputs for driven unit identification Only
            folders = dir(fullfile(basePath, ferretName + "_*" + groupName));
            groupPath = fullfile(folders.folder, folders.name);

            folderPath = fullfile(groupPath, "recording_info.csv");
            bad_block_path = fullfile(groupPath, "bad_blocks.csv");
            phyPath = fullfile(groupPath, "data", "mountainsort4", "phy");
            % Load behavioural data and stimulus onset times
            groupForFile = groupName;
            if ferretName == "Ursula"
                groupForFile = regexprep(groupName, "^Group_?", "G");
            end
            behaviorFile = fullfile(phyPath, ferretName + "_" + sideName + "_" + groupForFile + ".mat");
            load(behaviorFile, 'onset_times', 'Behavior_');

            if ~isfile(bad_block_path)
                bad_block_path = [];
            end

            run("IdentifyDrivenUnits.m");

        case '2'
            % Provided for reproducibility
            run("IdentifySpatiallyTunedUnits.m");

        case '3'
            run("CalculateSRFMetrics.m");

        case '4'
            run("CompareOnsetOffsetTuning.m");

        case '5'
            disp("1. Trained");
            disp("2. Orthogonal");
            disp("0. Exit");

            wpiChoice = input('Select comparison: ', 's');

            switch wpiChoice
                case '1'
                    condition = "Trained";
                case '2'
                    condition = "Orthogonal";
                case '0'
                    return;
                otherwise
                    disp("Invalid selection.");
                    continue;
            end

            run("CalculateWorldPreferenceIndex.m");

        case '0'
            return;

        otherwise
            disp("Invalid selection.");
    end
end