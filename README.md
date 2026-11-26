# Head-centred sound localisation

MATLAB code for analysing spatial reference frames in the ferret auditory cortex.

Nadia Aghili, Bizley Lab, UCL Ear Institute, 2026

## Code and data

The code was run in MATLAB R2024b. The repository also includes [npy-matlab](https://github.com/kwikteam/npy-matlab) for reading the spike-sorting files.

```text
Code_share/
    RunAnalysis.m
    IdentifyDrivenUnits.m
    IdentifySpatiallyTunedUnits.m
    CalculateSRFMetrics.m
    CompareOnsetOffsetTuning.m
    CalculateWorldPreferenceIndex.m
ExampleData/
    Example_Summary_Table.xlsx
    Crumble/
    Sponge/
    Ursula/
Functions/
    generateSessionCells.m
    npy-matlab-master/
```

`Code_share` contains the analysis scripts, `ExampleData` contains the data used by these scripts, and `Functions` contains the supporting functions. Keep these three folders in the same parent directory.

The example datasets are from the recording groups containing the head-, world- and mixed-tuned example units shown in the manuscript.

| Ferret | Hemisphere | Recording group | Example cluster ID | Tuning |
| --- | --- | --- | ---: | --- |
| Crumble (F1901) | Left | Group_3 | 26 | Head |
| Sponge (F1905) | Left | Group3_1 | 23 | World |
| Ursula (F1810) | Left | Group5_2 | 14 | Mixed |

Post-sorting data are provided for the entire recording group, not just the example unit. Raw electrophysiological recordings are not included.

Each group contains `recording_info.csv` and `bad_blocks.csv` (where applicable). Within `data/mountainsort4/phy`, the input files are:

- `spike_times.npy`: spike times in samples (sampling rate: 20 kHz).
- `spike_clusters.npy`: cluster IDs for each spike.
- `cluster_info.tsv`: cluster information.
- A `.mat` file containing stimulus onset times (`onset_times`) and behavioural data (`Behavior_`).

The original behavioural files are:

- `Crumble_Left_Group_3.mat`
- `Sponge_Left_Group3_1.mat`
- `Ursula_Left_G5_2.mat`

Please do not delete or rename these files, as they are inputs rather than analysis outputs.

`Example_Summary_Table.xlsx` contains the driven unit IDs, tuning labels, model fits and model preference values for the three groups. Electrode depths, cortical field assignments and single-/multi-unit classifications are also provided in this table.

## Running the analyses

In MATLAB, go to `Code_share` and run `RunAnalysis.m`. Select one of the three recording groups by entering its number in the Command Window (1 for Crumble, 2 for Sponge or 3 for Ursula).

The following analysis options are available:

| Option | Analysis |
| --- | --- |
| 1 | Identify driven units using onset and offset responses. |
| 2 | Identify spatially tuned units and calculate head- and world-centred model fits, model preference and fit weights. |
| 3 | Calculate spatial receptive fields (SRFs), ERRF width, modulation depth, centroids and preferred sound locations. |
| 4 | Assess onset and offset responsiveness and compare spatial tuning in units responsive in both periods. |
| 5 | Calculate the world preference index (WPI) and its significance using a permutation test. |
| 0 | Exit. |

For option 5, enter 1 for the trained comparison or 2 for the orthogonal comparison. Head, World and Mixed units are analysed separately. If there are no units in a given class, no output file is saved for that class.

After each run, the analysis menu is displayed again. To analyse a different recording group, exit (0) and run `RunAnalysis.m` again.

The analyses do not need to be run in order. Options 1 and 2 are provided to reproduce the unit identification and tuning analysis. The subsequent analyses use the precomputed values in `Example_Summary_Table.xlsx`, which is not updated when the scripts are run.

Analysis outputs are saved in the `phy` folder of the selected recording group, and the corresponding file path is displayed in the Command Window. Re-running an analysis overwrites its previous output. 
