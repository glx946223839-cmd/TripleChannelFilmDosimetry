# Triple-Channel Film Dosimetry Reconstruction

This repository provides a MATLAB workflow for triple-channel radiochromic film dose reconstruction using RGB calibration data, optional pre-scan beta correction, image registration, central ROI dose analysis, and standardized figure export.

The workflow can be run either through a graphical user interface (GUI) or directly from a MATLAB script.

## Files

| File | Description |
|---|---|
| `filmTripleChannelGUI.m` | MATLAB GUI wrapper for selecting input files, setting reconstruction options, running the reconstruction, and viewing run status. |
| `reconstructDoseTripleChannelRegistered.m` | Main reconstruction function. It reads calibration data, fits RGB calibration curves, optionally registers pre- and post-irradiation scans, performs triple-channel reconstruction, calculates the center ROI dose, and saves output figures/results. |
| `test_triplechannel.m` | Example batch/script workflow showing how to call the reconstruction function directly from MATLAB. |

## Main Features

- Triple-channel film dose reconstruction from red, green, and blue scanner channels.
- Rational calibration curve fitting for each RGB channel.
- Supported calibration fitting methods:
  - `EV`: effective variance fitting using both pixel-value uncertainty and dose uncertainty.
  - `WLS`: weighted least squares using pixel-value standard deviation.
  - `OLS`: ordinary least squares.
- Optional pre-scan beta correction using the unexposed film scan.
- Rigid image registration between before- and after-irradiation TIFF scans.
- Registration uses both film shape and common handwriting/text features when available.
- Automatic film mask generation and optional masking of non-film regions.
- Single-channel and triple-channel dose map visualization.
- Center dose-region ROI detection and mean dose calculation.
- Center horizontal and vertical dose profile plotting.
- Beta and delta correction map visualization.
- Output `.mat` file containing reconstructed dose, calibration information, registration information, ROI dose information, and solver diagnostics.

## Requirements

### MATLAB

The code is written for MATLAB and uses standard image processing and plotting functions.

Recommended MATLAB toolboxes:

- Image Processing Toolbox
- Optimization Toolbox, recommended but not strictly required

If Optimization Toolbox functions such as `lsqnonlin` or `lsqcurvefit` are unavailable, the calibration fitting code includes a fallback based on `fminsearch`.

## Input Data

### 1. Calibration TXT File

The calibration TXT file should contain dose calibration information for RGB channels, including mean pixel values and standard deviations for each calibration dose level.

The main function expects calibration information including:

- Dose values, in cGy
- Mean red, green, and blue pixel values
- Standard deviation of red, green, and blue pixel values

### 2. Before TIFF File

The before TIFF file is the unexposed or pre-irradiation film scan.

This file is required when `UsePrescanBeta` is set to `true`.

### 3. After TIFF File

The after TIFF file is the exposed or post-irradiation film scan.

This file is always required.

## How to Run Using the GUI

1. Put the following files in the same folder:

   ```matlab
   filmTripleChannelGUI.m
   reconstructDoseTripleChannelRegistered.m
   ```

2. Open MATLAB and set the current folder to the code folder.

3. Run:

   ```matlab
   filmTripleChannelGUI
   ```

4. In the GUI, select:

   - Calibration TXT file
   - Before TIFF file
   - After TIFF file
   - Output folder
   - Output prefix

5. Adjust reconstruction options if needed.

6. Click **Run Reconstruction**.

7. Output files will be saved in the selected output folder.

## How to Run Using a MATLAB Script

A basic script example is shown below:

```matlab
clc;
clear;

ThisFilePath = cd;
addpath(genpath(ThisFilePath));

calibrationTxt = 'EBT4_10Gy_48hours_v2.TXT';
OutputFolder = 'T:\Physics_Research\LABS\LAB_Ken_Wang\GroupMeeting\LixiangGuo\File Transfer - LG\Film dosimetry\Film_dosimetry_algorithm_file\Triple Channel\results_v3';

for i = 8:8
    close all;

    beforeTif = [num2str(i), ' before.tif'];
    afterTif  = [num2str(i), ' after.tif'];
    OutputPrefix = num2str(i);

    out = reconstructDoseTripleChannelRegistered( ...
        calibrationTxt, ...
        beforeTif, ...
        afterTif, ...
        'OutputFolder', OutputFolder, ...
        'OutputPrefix', OutputPrefix, ...
        'DPI', 300, ...
        'ROISize_mm', [5 5], ...
        'ShowFigures', true, ...
        'SaveFigures', true);
end
```

## Function Syntax

### With Pre-Scan Beta Correction

```matlab
out = reconstructDoseTripleChannelRegistered(calibrationTxt, beforeTif, afterTif);
```

### Without Pre-Scan Beta Correction

```matlab
out = reconstructDoseTripleChannelRegistered( ...
    calibrationTxt, ...
    afterTif, ...
    'UsePrescanBeta', false);
```

In this mode, registration is skipped and beta correction is set to zero.

## Common Name-Value Options

| Option | Default | Description |
|---|---:|---|
| `OutputFolder` | `pwd` | Folder used to save results and figures. |
| `OutputPrefix` | `triple_channel_registered` | Prefix added to output file names. |
| `ShowFigures` | `true` | Whether to display figures during reconstruction. |
| `SaveFigures` | `true` | Whether to save figures to the output folder. |
| `MaxDose` | `[]` | Maximum allowed reconstructed dose in cGy. If empty, the function uses 1.25 times the maximum calibration dose. |
| `DPI` | `300` | Scanner DPI used to convert pixels to millimeters. |
| `ROISize_mm` | `[5 5]` | Height and width of the central ROI in mm. |
| `DoseRegionThresholdRatio` | `0.30` | Threshold ratio used to detect the dose region. |
| `ApplyFilmMask` | `true` | If true, non-film regions are set to `NaN`. |
| `RegisterPreview` | `true` | Whether to display/save the registration preview. |
| `TextRegion` | `[0.55 1.00 0.00 0.25]` | Fractional film region used for handwriting/text-based registration. Format: `[xStart xEnd yStart yEnd]`. |
| `ProfileEdgeTrimFrac` | `0.08` | Fraction removed from both profile edges to avoid abnormal edge artifacts. |
| `ProfileHighPrctile` | `99` | High percentile threshold for removing abnormal high profile values. |
| `ProfileMedianWindow` | `3` | Median filter window size for profile smoothing. |
| `UsePrescanBeta` | `true` | Whether to use the before scan for beta correction. |
| `CalibrationFitMethod` | `EV` | Calibration fitting method: `EV`, `WLS`, or `OLS`. |
| `DoseUncertaintyPercent` | `1` | Relative dose uncertainty used for EV fitting, in percent. |
| `DoseUncertaintyMin_cGy` | `1` | Minimum absolute dose uncertainty used for EV fitting, in cGy. |
| `BetaDeltaDynamicPrctile` | `99` | Percentile used to define dynamic display range for beta and delta maps. |
| `BetaDeltaDynamicMaxAbs` | `3000` | Upper cap for dynamic beta/delta display range in pixel value. |
| `BetaDeltaDynamicMinAbs` | `100` | Lower bound for dynamic beta/delta display range in pixel value. |
| `PlotBorderMarginFrac` | `0.015` | Symmetric margin retained around the displayed film/dose area after border cropping. |

## Output Files

The exact output file names use the selected `OutputPrefix`. Typical outputs include:

| Output | Description |
|---|---|
| `<OutputPrefix>_results.mat` | Main MATLAB output structure containing reconstructed dose and metadata. |
| `<OutputPrefix>_calibration_curves.png` | RGB calibration curves. |
| `<OutputPrefix>_registration.png` | Registered before/after images or after-only image. |
| `<OutputPrefix>_dose_maps.png` | Red, green, blue, and triple-channel dose maps. |
| `<OutputPrefix>_center_profiles.png` | Horizontal and vertical center dose profiles. |
| `<OutputPrefix>_triple_channel_center_roi.png` | Detected center dose-region ROI and mean dose. |
| `<OutputPrefix>_beta_delta_full_scale.png` | Full-scale beta and delta correction maps. |
| `<OutputPrefix>_beta_delta_dynamic_scale.png` | Dynamically clipped beta and delta correction maps. |

## Output Structure

The returned variable `out` contains key results such as:

| Field | Description |
|---|---|
| `out.calibTable` | Calibration table read from the TXT file. |
| `out.p` | Fitted calibration parameters for RGB channels. |
| `out.calibrationR2` | R² values for RGB calibration curves. |
| `out.calibrationFitMethod` | Calibration fitting method actually used. |
| `out.beforeAlignedRGB` | Registered before-scan RGB image. Empty when no prescan is used. |
| `out.afterAlignedRGB` | Registered or loaded after-scan RGB image. |
| `out.doseSingleR` | Red-channel single-channel dose map. |
| `out.doseSingleG` | Green-channel single-channel dose map. |
| `out.doseSingleB` | Blue-channel single-channel dose map. |
| `out.doseTriple` | Final triple-channel reconstructed dose map. |
| `out.beta` | Beta correction maps. |
| `out.delta` | Delta correction map. |
| `out.centerDoseROI` | Central ROI mean dose, ROI dose matrix, ROI center, and mask information. |
| `out.commonMask` | Common valid film mask. |
| `out.registration` | Registration information and transformation objects. |
| `out.solverInfo` | Triple-channel solver convergence and diagnostic information. |
| `out.coordinateSystem` | Coordinate origin, mm axes, and plot display limits. |

## Recommended Workflow

1. Scan films using a consistent orientation and scanner setting.
2. Prepare the calibration TXT file using the same scanner and film type.
3. Keep before and after TIFF files in the same folder as the script, or provide full file paths.
4. Start with default parameters:

   ```matlab
   'DPI', 300
   'ROISize_mm', [5 5]
   'CalibrationFitMethod', 'EV'
   'DoseUncertaintyPercent', 1
   'DoseUncertaintyMin_cGy', 1
   ```

5. Check the registration figure before interpreting dose results.
6. Check the calibration curves and R² values.
7. Check the center ROI figure to confirm that the detected dose region is correct.
8. Use `out.doseTriple` for downstream quantitative analysis.

## Troubleshooting

### The GUI opens, but reconstruction fails

Make sure `reconstructDoseTripleChannelRegistered.m` is in the same folder as `filmTripleChannelGUI.m` or is already on the MATLAB path.

### No film region is detected

Possible causes:

- The TIFF image has unusual background or contrast.
- The film is too close to the image border.
- The scan contains multiple objects or artifacts.
- The scanner background is not bright relative to the film.

Try cropping the scan manually or checking the image quality.

### Registration is inaccurate

Possible causes:

- Before and after scans were acquired with different orientations.
- The handwriting/text region is not shared between both scans.
- The default `TextRegion` does not cover the common handwriting or text.

Try changing:

```matlab
'TextRegion', [0.55 1.00 0.00 0.25]
```

The format is:

```matlab
[xStartFrac xEndFrac yStartFrac yEndFrac]
```

For example, if the common handwriting is near the upper-left region, try:

```matlab
'TextRegion', [0.00 0.45 0.00 0.25]
```

### Center ROI is not detected correctly

Try adjusting:

```matlab
'DoseRegionThresholdRatio', 0.30
'ROISize_mm', [5 5]
```

A lower threshold may include more of the dose region, while a higher threshold may focus on the high-dose core.

### Calibration fitting is unstable

Check that the calibration file has enough valid calibration points. At least four valid dose points are recommended for rational calibration fitting.

You can also compare fitting methods:

```matlab
'CalibrationFitMethod', 'EV'
'CalibrationFitMethod', 'WLS'
'CalibrationFitMethod', 'OLS'
```

## Notes

- Dose values are shown in cGy.
- Pixel-to-distance conversion is based on the input `DPI` value.
- Non-film regions can be masked as `NaN` when `ApplyFilmMask` is enabled.
- The registration overlay uses false colors: magenta indicates before-dominant regions, green indicates after-dominant regions, and gray/white indicates matched regions.
- The beta and delta maps are plotted using both full linear scale and dynamically clipped linear scale for visualization.

## Author

Lixiang Guo  
Email: realLixiangGuo@Outlook.com

