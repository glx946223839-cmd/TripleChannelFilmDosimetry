function out = reconstructDoseTripleChannelRegistered(calibrationTxt, beforeTif, afterTif, varargin)
%==================================================================
% Author: Lixiang Guo, Email: realLixiangGuo@Outlook.com
%==================================================================
% reconstructDoseTripleChannelRegistered
%
% Integrated workflow:
%   1. Read calibration TXT file.
%   2. Fit rational calibration curve for R/G/B:
%          D = (p1 - p2*X) / (X - p3)
%   3. If UsePrescanBeta is true, register exposed film scan to unexposed
%      film scan using film shape + common top-right handwriting/text feature.
%   4. If UsePrescanBeta is true, use the registered unexposed film to
%      calculate beta correction. If false, set beta = 0.
%   5. Reconstruct dose using the triple-channel method.
%   6. Plot and save center profiles after edge removal and median filtering.
%
% INPUTS
%   calibrationTxt : calibration TXT file
%   beforeTif      : unexposed/pre-irradiation film scan. If UsePrescanBeta
%                    is false, this can be the exposed/post-irradiation film
%                    scan and afterTif can be omitted.
%   afterTif       : exposed/post-irradiation film scan
%
% EXAMPLES
%   With prescan beta correction:
%       out = reconstructDoseTripleChannelRegistered(calibrationTxt, beforeTif, afterTif);
%
%   Without prescan beta correction, beta_k = 0:
%       out = reconstructDoseTripleChannelRegistered(calibrationTxt, afterTif, ...
%           'UsePrescanBeta', false);
%
% OPTIONAL NAME-VALUE INPUTS
%   'OutputFolder'        : folder to save all results
%                           default = current MATLAB folder
%   'OutputPrefix'        : output file prefix
%   'ShowFigures'         : true or false
%   'SaveFigures'         : true or false
%   'MaxDose'             : maximum allowed dose in cGy
%   'DPI'                 : scanner/output DPI used to convert pixels to mm
%                           default = 300
%   'ROISize_mm'           : [height width] ROI size in mm for the mean dose
%                           calculation centered on the detected dose region
%                           default = [5 5]
%   'DoseRegionThresholdRatio' : threshold ratio for detecting dose region
%                           default = 0.30
%   'ApplyFilmMask'       : true or false, set outside common film area to NaN
%   'RegisterPreview'     : true or false
%   'TextRegion'          : [xStartFrac xEndFrac yStartFrac yEndFrac]
%                           default = [0.55 1.00 0.00 0.25]
%   'ProfileEdgeTrimFrac' : fraction removed from both profile edges
%                           default = 0.08
%   'ProfileHighPrctile'  : high percentile limit for removing abnormal high values
%                           default = 99
%   'ProfileMedianWindow' : median filter window size for profile
%                           default = 3
%   'UsePrescanBeta'      : true or false. If true, use beforeTif to estimate
%                           beta_k correction maps. If false, skip prescan,
%                           skip registration, and set beta_k = 0.
%                           default = true
%   'BetaDeltaDynamicPrctile' : percentile of |beta, Delta| used to set the
%                           clipped linear display range. default = 99
%   'BetaDeltaDynamicMaxAbs'  : upper cap for clipped display range in pixel
%                           value. default = 3000
%   'BetaDeltaDynamicMinAbs'  : lower bound for clipped display range in pixel
%                           value. default = 100
%   'PlotBorderMarginFrac' : extra symmetric margin kept around the displayed
%                           film/dose area after white border cropping.
%                           default = 0.015
%   'CalibrationFitMethod' : 'EV', 'WLS', or 'OLS'
%                           EV uses effective variance fitting and includes
%                           both pixel-value SD and dose uncertainty.
%                           default = 'EV'
%   'DoseUncertaintyPercent' : relative dose uncertainty used by EV fitting
%                           default = 1, meaning 1%
%   'DoseUncertaintyMin_cGy' : minimum absolute dose uncertainty used by EV fitting
%                           default = 1 cGy

% Allow the after-only syntax:
%   reconstructDoseTripleChannelRegistered(calibrationTxt, afterTif, ...
%       'UsePrescanBeta', false, ...)
% In that call pattern, MATLAB places the first name-value key in afterTif.
knownNameValueKeys = { ...
    'OutputFolder', 'OutputPrefix', 'ShowFigures', 'SaveFigures', ...
    'MaxDose', 'DPI', 'ROISize_mm', 'DoseRegionThresholdRatio', ...
    'ApplyFilmMask', 'RegisterPreview', 'TextRegion', ...
    'ProfileEdgeTrimFrac', 'ProfileHighPrctile', 'ProfileMedianWindow', ...
    'UsePrescanBeta', 'BetaDeltaDynamicPrctile', ...
    'BetaDeltaDynamicMaxAbs', 'BetaDeltaDynamicMinAbs', ...
    'PlotBorderMarginFrac', 'CalibrationFitMethod', ...
    'DoseUncertaintyPercent', 'DoseUncertaintyMin_cGy'};

if nargin < 3 || isempty(afterTif)
    afterTif = beforeTif;
    beforeTif = '';
    if ~any(strcmpi('UsePrescanBeta', varargin(1:2:end)))
        varargin = [{'UsePrescanBeta', false}, varargin];
    end
elseif (ischar(afterTif) || isstring(afterTif)) && any(strcmpi(char(afterTif), knownNameValueKeys))
    varargin = [{afterTif}, varargin];
    afterTif = beforeTif;
    beforeTif = '';
    if ~any(strcmpi('UsePrescanBeta', varargin(1:2:end)))
        varargin = [{'UsePrescanBeta', false}, varargin];
    end
end

%% Optional inputs
ip = inputParser;
ip.addParameter('OutputFolder', pwd, @(x) ischar(x) || isstring(x));
ip.addParameter('OutputPrefix', 'triple_channel_registered', @(x) ischar(x) || isstring(x));
ip.addParameter('ShowFigures', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('SaveFigures', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('MaxDose', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('DPI', 300, @(x) isnumeric(x) && isscalar(x) && x > 0);
ip.addParameter('ROISize_mm', [5 5], @(x) isnumeric(x) && (isscalar(x) || numel(x) == 2) && all(x(:) > 0));
ip.addParameter('DoseRegionThresholdRatio', 0.30, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
ip.addParameter('ApplyFilmMask', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('RegisterPreview', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('TextRegion', [0.55 1.00 0.00 0.25], @(x) isnumeric(x) && numel(x) == 4);
ip.addParameter('ProfileEdgeTrimFrac', 0.08, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 0.45);
ip.addParameter('ProfileHighPrctile', 99, @(x) isnumeric(x) && isscalar(x) && x > 50 && x <= 100);
ip.addParameter('ProfileMedianWindow', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter('UsePrescanBeta', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('BetaDeltaDynamicPrctile', 99, @(x) isnumeric(x) && isscalar(x) && x > 50 && x <= 100);
ip.addParameter('BetaDeltaDynamicMaxAbs', 3000, @(x) isnumeric(x) && isscalar(x) && x > 0);
ip.addParameter('BetaDeltaDynamicMinAbs', 100, @(x) isnumeric(x) && isscalar(x) && x >= 0);
ip.addParameter('PlotBorderMarginFrac', 0.015, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 0.5);
ip.addParameter('CalibrationFitMethod', 'EV', @(x) ischar(x) || isstring(x));
ip.addParameter('DoseUncertaintyPercent', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
ip.addParameter('DoseUncertaintyMin_cGy', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
ip.parse(varargin{:});

outputFolder         = char(ip.Results.OutputFolder);
outputPrefix         = char(ip.Results.OutputPrefix);
showFigures          = logical(ip.Results.ShowFigures);
saveFigures          = logical(ip.Results.SaveFigures);
applyFilmMask        = logical(ip.Results.ApplyFilmMask);
registerPreview      = logical(ip.Results.RegisterPreview);
usePrescanBeta       = logical(ip.Results.UsePrescanBeta);
betaDeltaDynamicPrctile = double(ip.Results.BetaDeltaDynamicPrctile);
betaDeltaDynamicMaxAbs  = double(ip.Results.BetaDeltaDynamicMaxAbs);
betaDeltaDynamicMinAbs  = double(ip.Results.BetaDeltaDynamicMinAbs);
plotBorderMarginFrac    = double(ip.Results.PlotBorderMarginFrac);
calibrationFitMethod     = upper(strtrim(char(ip.Results.CalibrationFitMethod)));
if ~ismember(calibrationFitMethod, {'EV','WLS','OLS'})
    error('CalibrationFitMethod must be ''EV'', ''WLS'', or ''OLS''.');
end
doseUncertaintyPercent  = double(ip.Results.DoseUncertaintyPercent);
doseUncertaintyMin_cGy  = double(ip.Results.DoseUncertaintyMin_cGy);
textRegion           = ip.Results.TextRegion;
maxDoseUser          = ip.Results.MaxDose;
dpi                  = double(ip.Results.DPI);
pixelSizeMm          = 25.4 / dpi;
plotFontName         = 'Arial';
plotFontSize         = 12;
plotTitleFontSize    = 12;
roiSizeMm            = double(ip.Results.ROISize_mm);
if isscalar(roiSizeMm)
    roiSizeMm = [roiSizeMm roiSizeMm];
else
    roiSizeMm = roiSizeMm(:).';
end
doseRegionThresholdRatio = ip.Results.DoseRegionThresholdRatio;
profileEdgeTrimFrac  = ip.Results.ProfileEdgeTrimFrac;
profileHighPrctile   = ip.Results.ProfileHighPrctile;
profileMedianWindow  = round(ip.Results.ProfileMedianWindow);

if isempty(beforeTif)
    usePrescanBeta = false;
end

if mod(profileMedianWindow, 2) == 0
    profileMedianWindow = profileMedianWindow + 1;
end

% Create output folder if it does not exist
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% Read and fit calibration
calib = readFilmCalibrationTxt(calibrationTxt);

doseCal = calib.DOSE(:);
rgbCal  = [calib.MEAN_R(:), calib.MEAN_G(:), calib.MEAN_B(:)];
sdCal   = [calib.SD_R(:),   calib.SD_G(:),   calib.SD_B(:)];

pFit = zeros(3,3);
calibrationR2 = zeros(3,1);

% Dose uncertainty for effective variance fitting.
% The calibration file provides pixel-value SD. It usually does not provide
% dose uncertainty, so use a configurable relative value with a small floor.
sigmaDoseCal = max(doseUncertaintyMin_cGy, abs(doseCal) .* doseUncertaintyPercent ./ 100);

for k = 1:3
    pFit(k,:) = fitRationalCalibration(doseCal, rgbCal(:,k), sdCal(:,k), ...
        calibrationFitMethod, sigmaDoseCal);

    % Calculate R^2 for the calibration curve in the plotted direction:
    % dose is the independent variable and pixel value is the response.
    xPred = inverseRationalPixelModel(pFit(k,:), doseCal);
    calibrationR2(k) = calculateRSquared(rgbCal(:,k), xPred);
end

if isempty(maxDoseUser)
    maxDose = max(doseCal) * 1.25;
else
    maxDose = maxDoseUser;
end

%% Read scans, register if prescan beta correction is used
if usePrescanBeta
    [beforeAlignedRGB, afterAlignedRGB, regInfo] = registerBeforeAfterRawRGB( ...
        beforeTif, afterTif, ...
        'RegisterPreview', registerPreview, ...
        'TextRegion', textRegion, ...
        'DPI', dpi);
else
    [beforeAlignedRGB, afterAlignedRGB, regInfo] = readAfterOnlyRawRGB(afterTif);
end

commonMask = regInfo.commonMask;

%% Convert RGB pixel values to single-channel scanned dose
if usePrescanBeta
    doseUnexposedRGB = pixelToDoseRGB(beforeAlignedRGB, pFit);
else
    doseUnexposedRGB = [];
end

doseExposedRGB = pixelToDoseRGB(afterAlignedRGB, pFit);

doseSingleR = doseExposedRGB(:,:,1);
doseSingleG = doseExposedRGB(:,:,2);
doseSingleB = doseExposedRGB(:,:,3);

%% Estimate beta correction from registered unexposed scan, or use beta = 0
if usePrescanBeta
    beta = estimateBetaFromUnexposed(doseUnexposedRGB, pFit, maxDose, commonMask);
    betaMode = 'prescan_beta';
else
    beta = zeros(size(doseExposedRGB));
    betaMode = 'zero_beta_no_prescan';
end

%% Triple-channel dose reconstruction
[doseTriple, delta, solverInfo] = solveTripleChannelDose(doseExposedRGB, beta, pFit, maxDose, commonMask);

%% Apply film mask
if applyFilmMask
    doseTriple(~commonMask) = NaN;
    delta(~commonMask) = NaN;

    doseSingleR(~commonMask) = NaN;
    doseSingleG(~commonMask) = NaN;
    doseSingleB(~commonMask) = NaN;

    for k = 1:3
        tmp = beta(:,:,k);
        tmp(~commonMask) = NaN;
        beta(:,:,k) = tmp;
    end
end

%% Mean dose in the detected central dose region
roiFigureName = fullfile(outputFolder, [outputPrefix, '_triple_channel_center_roi.png']);

try
    [meanDoseROI, roiDose, roiCenterPx, doseRegionMask, roiInfo] = meanDoseCenterDoseRegionMm( ...
        doseTriple, roiFigureName, ...
        'DPI', dpi, ...
        'ROISize_mm', roiSizeMm, ...
        'ThresholdRatio', doseRegionThresholdRatio, ...
        'ShowFigure', showFigures, ...
        'SaveFigure', saveFigures, ...
        'FilmMask', commonMask);
catch ME
    warning('Central dose-region ROI calculation failed: %s', ME.message);
    meanDoseROI = NaN;
    roiDose = [];
    roiCenterPx = [NaN NaN];
    doseRegionMask = false(size(doseTriple));
    roiInfo = struct();
end

%% Define one coordinate system for all image-based plots
% Default: use the film center as (0,0).
% If the detected dose distribution is a regular rectangle, square, or circle,
% use the detected dose-region center as (0,0) instead.
if isfield(roiInfo, 'coordinateOriginPixel') && numel(roiInfo.coordinateOriginPixel) == 2 && all(isfinite(roiInfo.coordinateOriginPixel))
    coordinateOriginPixel = double(roiInfo.coordinateOriginPixel);
    coordinateOriginMode = roiInfo.coordinateOriginMode;
    doseRegionShapeInfo = roiInfo.doseRegionShape;
else
    [originRowFallback, originColFallback] = centerOfMask(commonMask);
    coordinateOriginPixel = [originRowFallback, originColFallback];
    coordinateOriginMode = 'film_center_fallback';
    doseRegionShapeInfo = struct('shape', 'unknown', 'isRegular', false);
end

[yAxisMm, xAxisMm] = imageAxesInMm(size(afterAlignedRGB,1), size(afterAlignedRGB,2), dpi, coordinateOriginPixel);

% Crop surrounding white scanner border in all image-based plots.
% Limits are symmetric around the selected coordinate origin and keep a small margin.
[plotXLim, plotYLim] = getSymmetricDisplayLimits(commonMask, xAxisMm, yAxisMm, plotBorderMarginFrac);

%% Output structure
out = struct();
out.calibTable       = calib;
out.p                = pFit;
out.calibrationR2    = array2table(calibrationR2(:).', ...
    'VariableNames', {'Red','Green','Blue'});
out.calibrationFitMethod = calibrationFitMethod;
out.doseUncertaintyPercent = doseUncertaintyPercent;
out.doseUncertaintyMin_cGy = doseUncertaintyMin_cGy;
out.sigmaDoseCal_cGy = sigmaDoseCal;
out.centerDoseROI    = struct( ...
    'meanDose_cGy', meanDoseROI, ...
    'roiDose', roiDose, ...
    'roiCenter_pixel', roiCenterPx, ...
    'doseRegionMask', doseRegionMask, ...
    'info', roiInfo);
out.beforeAlignedRGB = beforeAlignedRGB;
out.afterAlignedRGB  = afterAlignedRGB;
out.doseSingleR      = doseSingleR;
out.doseSingleG      = doseSingleG;
out.doseSingleB      = doseSingleB;
out.doseTriple       = doseTriple;
out.delta            = delta;
out.beta             = beta;
out.betaMode         = betaMode;
out.usePrescanBeta   = usePrescanBeta;
out.solverInfo       = solverInfo;
out.commonMask       = commonMask;
out.registration     = regInfo;
out.outputFolder     = outputFolder;
out.outputPrefix     = outputPrefix;
out.dpi              = dpi;
out.pixelSizeMm      = pixelSizeMm;
out.roiSizeMm        = roiSizeMm;
out.doseRegionThresholdRatio = doseRegionThresholdRatio;
out.coordinateSystem = struct( ...
    'originPixel_RowCol', coordinateOriginPixel, ...
    'originMode', coordinateOriginMode, ...
    'doseRegionShape', doseRegionShapeInfo, ...
    'xAxisMm', xAxisMm, ...
    'yAxisMm', yAxisMm, ...
    'plotXLimMm', plotXLim, ...
    'plotYLimMm', plotYLim, ...
    'plotBorderMarginFrac', plotBorderMarginFrac);

resultsMatName = fullfile(outputFolder, [outputPrefix, '_results.mat']);
save(resultsMatName, 'out');

%% Plot calibration curves
fig1 = figure('Name','Calibration curves','Color','w');

% Stack R/G/B calibration curves vertically.
fig1.Units = 'pixels';
fig1.Position = [100, 100, 520, 760];

channelNames = {'Red','Green','Blue'};
channelColors = [1.00 0.55 0.55; 0.45 0.85 0.45; 0.45 0.65 1.00];

for k = 1:3
    subplot(3,1,k);

    D = doseCal(:);
    X = rgbCal(:,k);

    % IMPORTANT: Dose is the x-axis, RGB/pixel value is the y-axis.
    scatter(D, X, 38, channelColors(k,:), 'filled');
    hold on;

    dFine = linspace(min(D), max(D), 400);

    % The fitted function used internally is:
    %   D(X) = (p1 - p2*X) / (X - p3)
    % For plotting with dose on x-axis, use the inverse form:
    %   X(D) = (q1 + q2*D) / (q3 + D)
    % Based on p = [q1, q3, q2]:
    q1 = pFit(k,1);
    q3 = pFit(k,2);
    q2 = pFit(k,3);

    xFine = inverseRationalPixelModel(pFit(k,:), dFine);

    plot(dFine, xFine, 'k-', 'LineWidth', 1.5);

    grid off;
    xlabel('Dose (cGy)');
    ylabel([channelNames{k}, ' pixel value']);

    eqText = sprintf('X(D) = (%.4g + %.4g D) / (%.4g + D), D in cGy', q1, q2, q3);
    r2Text = sprintf('R^2 = %.5f', calibrationR2(k));
    title({[channelNames{k}, ' calibration curve'], eqText, ['Fit method: ', calibrationFitMethod]});

    text(0.03, 0.08, r2Text, ...
        'Units', 'normalized', ...
        'FontWeight', 'bold');

    legend([channelNames{k}, ' calibration data'], 'Fitted curve', 'Location', 'best');
    formatAxes(gca, plotFontName, plotFontSize, plotTitleFontSize);
end

formatFigure(fig1, plotFontName, plotFontSize, plotTitleFontSize);

if saveFigures
    exportgraphics(fig1, fullfile(outputFolder, [outputPrefix, '_calibration_curves.png']), 'Resolution', dpi);
end

% Image axes were already defined above using the selected coordinate origin.
% Use the triple-channel dose range as the common display range for all
% single-channel and triple-channel dose maps. This prevents the Red/Green/Blue
% colorbars from being dominated by single-channel artifacts.
doseMapCLim = getDoseDisplayLimitsFromTriple(doseTriple);

%% Plot dose maps
fig3 = figure('Name','Dose maps','Color','w');
fig3.Units = 'pixels';
fig3.Position = [100, 100, 950, 760];

subplot(2,2,1);
showMaskedImageMm(xAxisMm, yAxisMm, doseSingleR, commonMask);
axis image;
applyImagePlotLimits(gca, plotXLim, plotYLim);
setDoseColorLimits(gca, doseMapCLim);
xlabel('X (mm)');
ylabel('Y (mm)');
cb = colorbar;
cb.Label.String = 'Dose (cGy)';
title('Red-channel dose');

subplot(2,2,2);
showMaskedImageMm(xAxisMm, yAxisMm, doseSingleG, commonMask);
axis image;
applyImagePlotLimits(gca, plotXLim, plotYLim);
setDoseColorLimits(gca, doseMapCLim);
xlabel('X (mm)');
ylabel('Y (mm)');
cb = colorbar;
cb.Label.String = 'Dose (cGy)';
title('Green-channel dose');

subplot(2,2,3);
showMaskedImageMm(xAxisMm, yAxisMm, doseSingleB, commonMask);
axis image;
applyImagePlotLimits(gca, plotXLim, plotYLim);
setDoseColorLimits(gca, doseMapCLim);
xlabel('X (mm)');
ylabel('Y (mm)');
cb = colorbar;
cb.Label.String = 'Dose (cGy)';
title('Blue-channel dose');

subplot(2,2,4);
showMaskedImageMm(xAxisMm, yAxisMm, doseTriple, commonMask);
axis image;
applyImagePlotLimits(gca, plotXLim, plotYLim);
setDoseColorLimits(gca, doseMapCLim);
xlabel('X (mm)');
ylabel('Y (mm)');
cb = colorbar;
cb.Label.String = 'Dose (cGy)';
title('Triple-channel dose');

formatFigure(fig3, plotFontName, plotFontSize, plotTitleFontSize);

if saveFigures
    exportgraphics(fig3, fullfile(outputFolder, [outputPrefix, '_dose_maps.png']), 'Resolution', dpi);
end

%% Plot registered images or after-only image
fig2 = figure('Name','Registered before and after','Color','w');
fig2.Units = 'pixels';

if usePrescanBeta
    fig2.Position = [100, 100, 1200, 360];

    subplot(1,3,1);
    imshow(normalizeForDisplay(beforeAlignedRGB), 'XData', [xAxisMm(1) xAxisMm(end)], 'YData', [yAxisMm(1) yAxisMm(end)]);
    axis on image;
    applyImagePlotLimits(gca, plotXLim, plotYLim);
    xlabel('X (mm)');
    ylabel('Y (mm)');
    title('Before irradiation, fixed');

    subplot(1,3,2);
    imshow(normalizeForDisplay(afterAlignedRGB), 'XData', [xAxisMm(1) xAxisMm(end)], 'YData', [yAxisMm(1) yAxisMm(end)]);
    axis on image;
    applyImagePlotLimits(gca, plotXLim, plotYLim);
    xlabel('X (mm)');
    ylabel('Y (mm)');
    title('After irradiation, registered');

    subplot(1,3,3);
    showRegistrationOverlayMm(beforeAlignedRGB, afterAlignedRGB, xAxisMm, yAxisMm);
    axis on image;
    applyImagePlotLimits(gca, plotXLim, plotYLim);
    xlabel('X (mm)');
    ylabel('Y (mm)');
    title({'Registration overlay', 'Magenta = before | Green = after | Gray = matched'});
else
    fig2.Position = [100, 100, 520, 520];

    imshow(normalizeForDisplay(afterAlignedRGB), 'XData', [xAxisMm(1) xAxisMm(end)], 'YData', [yAxisMm(1) yAxisMm(end)]);
    axis on image;
    applyImagePlotLimits(gca, plotXLim, plotYLim);
    xlabel('X (mm)');
    ylabel('Y (mm)');
    title({'After irradiation only', 'No prescan: beta_k = 0'});
end
formatFigure(fig2, plotFontName, plotFontSize, plotTitleFontSize);

if saveFigures
    exportgraphics(fig2, fullfile(outputFolder, [outputPrefix, '_registration.png']), 'Resolution', dpi);
end

% Plot center profiles with edge removal and median filtering
fig4 = figure('Name','Center profiles','Color','w');

% Set profile figure aspect ratio to 16:8
fig4.Units = 'pixels';
fig4.Position = [100, 100, 1200, 430];

% Profiles are extracted through the same origin used for the image axes.
cy = round(coordinateOriginPixel(1));
cx = round(coordinateOriginPixel(2));
cy = max(1, min(size(commonMask,1), cy));
cx = max(1, min(size(commonMask,2), cx));

% Light RGB colors
lightRed   = [1.00, 0.55, 0.55];
lightGreen = [0.45, 0.85, 0.45];
lightBlue  = [0.45, 0.65, 1.00];
blackColor = [0.00, 0.00, 0.00];

axProfileH = subplot(1,2,1);

[xH, profRH, profGH, profBH, profTH] = extractCleanProfileHorizontal( ...
    doseSingleR, doseSingleG, doseSingleB, doseTriple, commonMask, cy, ...
    profileEdgeTrimFrac, profileHighPrctile);

profRH = medianFilterProfile(profRH, profileMedianWindow);
profGH = medianFilterProfile(profGH, profileMedianWindow);
profBH = medianFilterProfile(profBH, profileMedianWindow);
profTH = medianFilterProfile(profTH, profileMedianWindow);

xHMm = pixelIndexToMm(xH, dpi, coordinateOriginPixel(2));

plot(xHMm, profRH, 'Color', lightRed,   'LineWidth', 1.2); hold on;
plot(xHMm, profGH, 'Color', lightGreen, 'LineWidth', 1.2);
plot(xHMm, profBH, 'Color', lightBlue,  'LineWidth', 1.2);
plot(xHMm, profTH, 'Color', blackColor, 'LineWidth', 1.0);

grid off;
xlabel('Position (mm)');
ylabel('Dose (cGy)');
title({'Horizontal center profile', ...
       ['Edges removed, ', num2str(profileMedianWindow), '-pixel median filtered']});
legend('Red channel','Green channel','Blue channel','Triple channel','Location','south');

axProfileV = subplot(1,2,2);

[yV, profRV, profGV, profBV, profTV] = extractCleanProfileVertical( ...
    doseSingleR, doseSingleG, doseSingleB, doseTriple, commonMask, cx, ...
    profileEdgeTrimFrac, profileHighPrctile);

profRV = medianFilterProfile(profRV, profileMedianWindow);
profGV = medianFilterProfile(profGV, profileMedianWindow);
profBV = medianFilterProfile(profBV, profileMedianWindow);
profTV = medianFilterProfile(profTV, profileMedianWindow);

yVMm = pixelIndexToMm(yV, dpi, coordinateOriginPixel(1));

plot(yVMm, profRV, 'Color', lightRed,   'LineWidth', 1.2); hold on;
plot(yVMm, profGV, 'Color', lightGreen, 'LineWidth', 1.2);
plot(yVMm, profBV, 'Color', lightBlue,  'LineWidth', 1.2);
plot(yVMm, profTV, 'Color', blackColor, 'LineWidth', 1.0);

grid off;
xlabel('Position (mm)');
ylabel('Dose (cGy)');
title({'Vertical center profile', ...
       ['Edges removed, ', num2str(profileMedianWindow), '-pixel median filtered']});
legend('Red channel','Green channel','Blue channel','Triple channel','Location','south');

profileAllVals = [profRH(:); profGH(:); profBH(:); profTH(:); profRV(:); profGV(:); profBV(:); profTV(:)];
profileAllVals = profileAllVals(isfinite(profileAllVals));
if ~isempty(profileAllVals)
    yMinProfile = min(profileAllVals);
    yMaxProfile = max(profileAllVals);
    if yMaxProfile > yMinProfile
        padProfile = 0.05 * (yMaxProfile - yMinProfile);
        yLimProfile = [yMinProfile - padProfile, yMaxProfile + padProfile];
    else
        yLimProfile = [yMinProfile - 1, yMaxProfile + 1];
    end
    ylim(axProfileH, yLimProfile);
    ylim(axProfileV, yLimProfile);
end
formatFigure(fig4, plotFontName, plotFontSize, plotTitleFontSize);

if saveFigures
    profilePngName = fullfile(outputFolder, [outputPrefix, '_center_profiles.png']);
    exportgraphics(fig4, profilePngName, 'Resolution', dpi);
end

%% Plot beta and delta: full linear scale
fig5 = figure('Name','Beta and delta corrections, full scale','Color','w');
fig5.Units = 'pixels';
fig5.Position = [100, 100, 950, 760];

plotBetaDeltaLinearMaps(beta, delta, commonMask, xAxisMm, yAxisMm, plotXLim, plotYLim, [], ...
    'Beta and Delta, full linear scale');

formatFigure(fig5, plotFontName, plotFontSize, plotTitleFontSize);

if saveFigures
    exportgraphics(fig5, fullfile(outputFolder, [outputPrefix, '_beta_delta_full_scale.png']), 'Resolution', dpi);
end

%% Plot beta and delta: dynamically clipped linear scale
betaDeltaDynamicCLim = getBetaDeltaDynamicCLim( ...
    beta, delta, commonMask, ...
    betaDeltaDynamicPrctile, ...
    betaDeltaDynamicMinAbs, ...
    betaDeltaDynamicMaxAbs);

fig6 = figure('Name','Beta and delta corrections, dynamic clipped scale','Color','w');
fig6.Units = 'pixels';
fig6.Position = [130, 130, 950, 760];

plotBetaDeltaLinearMaps(beta, delta, commonMask, xAxisMm, yAxisMm, plotXLim, plotYLim, betaDeltaDynamicCLim, ...
    sprintf('Beta and Delta, clipped linear scale [%g, %g]', ...
    betaDeltaDynamicCLim(1), betaDeltaDynamicCLim(2)));

formatFigure(fig6, plotFontName, plotFontSize, plotTitleFontSize);

if saveFigures
    exportgraphics(fig6, fullfile(outputFolder, [outputPrefix, '_beta_delta_dynamic_scale.png']), 'Resolution', dpi);
end

if ~showFigures
    close(fig1);
    close(fig2);
    close(fig3);
    close(fig4);
    close(fig5);
    close(fig6);
end

fprintf('\nDone.\n');
fprintf('Output folder: %s\n', outputFolder);
fprintf('Results saved to: %s\n', resultsMatName);
fprintf('Profile figure saved to: %s\n', fullfile(outputFolder, [outputPrefix, '_center_profiles.png']));
fprintf('Central dose-region ROI figure saved to: %s\n', roiFigureName);
fprintf('Triple-channel center ROI mean dose: %.4f cGy\n', meanDoseROI);
fprintf('Figure export/scanner DPI: %.1f\n', dpi);
fprintf('Pixel size used for plot axes: %.6f mm/pixel\n', pixelSizeMm);
fprintf('Dose unit shown as cGy in calibration, dose-map, and profile figures.\n');
fprintf('Calibration fit method: %s; dose uncertainty = %.4g%% with minimum %.4g cGy.\n', ...
    calibrationFitMethod, doseUncertaintyPercent, doseUncertaintyMin_cGy);
fprintf('Triple-channel solver iterations: %d; converged: %d; reason: %s\n', ...
    solverInfo.numIterations, solverInfo.converged, solverInfo.reason);
fprintf('Final solver diagnostics: max step D = %.4g cGy, max step Delta = %.4g pixel value, max |gD| = %.4g, max |gDelta| = %.4g\n', ...
    solverInfo.finalMaxStepD_cGy, solverInfo.finalMaxStepDelta_pixelValue, ...
    solverInfo.finalMaxGradD, solverInfo.finalMaxGradDelta);
fprintf('Beta mode: %s\n', betaMode);
fprintf('Coordinate origin mode: %s; origin pixel [row, col] = [%.3f, %.3f].\n', ...
    coordinateOriginMode, coordinateOriginPixel(1), coordinateOriginPixel(2));
fprintf('Beta and Delta correction maps are shown in two linear-scale figures: full scale and dynamic clipped scale [%.4g, %.4g] pixel value.\n', ...
    betaDeltaDynamicCLim(1), betaDeltaDynamicCLim(2));

end

%% ========================================================================
function [plotXLim, plotYLim] = getSymmetricDisplayLimits(maskForDisplay, xAxisMm, yAxisMm, marginFrac)
% Return square, symmetric x/y display limits around 0.
%
% The limits are based on the non-white film mask extent, then expanded by a
% small margin. The final X and Y limits use the same numerical range:
%
%   XLim = [-L, L], YLim = [-L, L]
%
% This makes every 2D image plot use the same physical scale in X and Y, so
% one millimeter has the same visual length horizontally and vertically.

if nargin < 4 || isempty(marginFrac)
    marginFrac = 0.04;
end

maskForDisplay = logical(maskForDisplay);

if isempty(maskForDisplay) || ~any(maskForDisplay(:))
    halfRange = min([max(abs(xAxisMm(:)), [], 'omitnan'), ...
                     max(abs(yAxisMm(:)), [], 'omitnan')]);
    if ~isfinite(halfRange) || halfRange <= 0
        halfRange = 1;
    end
    plotXLim = [-halfRange, halfRange];
    plotYLim = [-halfRange, halfRange];
    return;
end

[rowIdx, colIdx] = find(maskForDisplay);
if isempty(rowIdx) || isempty(colIdx)
    halfRange = min([max(abs(xAxisMm(:)), [], 'omitnan'), ...
                     max(abs(yAxisMm(:)), [], 'omitnan')]);
    if ~isfinite(halfRange) || halfRange <= 0
        halfRange = 1;
    end
    plotXLim = [-halfRange, halfRange];
    plotYLim = [-halfRange, halfRange];
    return;
end

xVals = xAxisMm(colIdx);
yVals = yAxisMm(rowIdx);

maxAbsFromMask = max([abs(xVals(:)); abs(yVals(:))], [], 'omitnan');
if ~isfinite(maxAbsFromMask) || maxAbsFromMask <= 0
    maxAbsFromMask = 1;
end

% Add a small symmetric margin around the detected film/dose extent.
halfRange = maxAbsFromMask * (1 + marginFrac);

% Avoid asking MATLAB to show coordinates outside the available image area.
% This prevents new white background from being introduced by xlim/ylim.
availableHalfX = min(abs([min(xAxisMm(:)), max(xAxisMm(:))]));
availableHalfY = min(abs([min(yAxisMm(:)), max(yAxisMm(:))]));
availableHalf = min(availableHalfX, availableHalfY);

if isfinite(availableHalf) && availableHalf > 0
    halfRange = min(halfRange, availableHalf);
end

if ~isfinite(halfRange) || halfRange <= 0
    halfRange = 1;
end

plotXLim = [-halfRange, halfRange];
plotYLim = [-halfRange, halfRange];

end

%% ========================================================================
function applyImagePlotLimits(axHandle, plotXLim, plotYLim)
% Apply cropped, symmetric image display limits.

if nargin < 1 || isempty(axHandle) || ~isvalid(axHandle)
    return;
end

if nargin >= 2 && numel(plotXLim) == 2 && all(isfinite(plotXLim)) && plotXLim(2) > plotXLim(1)
    xlim(axHandle, plotXLim);
end

if nargin >= 3 && numel(plotYLim) == 2 && all(isfinite(plotYLim)) && plotYLim(2) > plotYLim(1)
    ylim(axHandle, plotYLim);
end

daspect(axHandle, [1 1 1]);
pbaspect(axHandle, [1 1 1]);

% Re-apply limits after setting aspect ratios. This avoids MATLAB expanding
% one direction and making the X/Y physical scale appear different.
if nargin >= 2 && numel(plotXLim) == 2 && all(isfinite(plotXLim)) && plotXLim(2) > plotXLim(1)
    xlim(axHandle, plotXLim);
end

if nargin >= 3 && numel(plotYLim) == 2 && all(isfinite(plotYLim)) && plotYLim(2) > plotYLim(1)
    ylim(axHandle, plotYLim);
end

setEqualXYTickSpacing(axHandle);

end

%% ========================================================================
function setEqualXYTickSpacing(axHandle)
% Use the same tick interval on X and Y for image-based plots.

if nargin < 1 || isempty(axHandle) || ~isvalid(axHandle)
    return;
end

xl = xlim(axHandle);
yl = ylim(axHandle);

if numel(xl) ~= 2 || numel(yl) ~= 2 || any(~isfinite([xl yl]))
    return;
end

rangeX = abs(diff(xl));
rangeY = abs(diff(yl));
maxRange = max(rangeX, rangeY);

if ~isfinite(maxRange) || maxRange <= 0
    return;
end

% Aim for about 5 major intervals using a clean 1, 2, 5, 10 sequence.
tickStep = niceTickStep(maxRange / 5);

if ~isfinite(tickStep) || tickStep <= 0
    return;
end

xTicks = ceil(min(xl) / tickStep) * tickStep : tickStep : floor(max(xl) / tickStep) * tickStep;
yTicks = ceil(min(yl) / tickStep) * tickStep : tickStep : floor(max(yl) / tickStep) * tickStep;

if numel(xTicks) >= 2
    xticks(axHandle, xTicks);
end
if numel(yTicks) >= 2
    yticks(axHandle, yTicks);
end

end

%% ========================================================================
function step = niceTickStep(rawStep)
% Return a clean tick interval close to rawStep.

if ~isfinite(rawStep) || rawStep <= 0
    step = NaN;
    return;
end

pow10 = 10 ^ floor(log10(rawStep));
candidates = [1 2 5 10] .* pow10;
idx = find(candidates >= rawStep, 1, 'first');

if isempty(idx)
    step = candidates(end);
else
    step = candidates(idx);
end

end

%% ========================================================================
function [beforeAlignedRGB, afterAlignedRGB, regInfo] = registerBeforeAfterRawRGB(beforeFile, afterFile, varargin)
% Register exposed scan to unexposed scan.

ip = inputParser;
ip.addParameter('RegisterPreview', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('TextRegion', [0.55 1.00 0.00 0.25], @(x) isnumeric(x) && numel(x) == 4);
ip.addParameter('DPI', 300, @(x) isnumeric(x) && isscalar(x) && x > 0);
ip.parse(varargin{:});

registerPreview = logical(ip.Results.RegisterPreview);
textRegion = ip.Results.TextRegion;
dpi = double(ip.Results.DPI);

beforeFile = addTifExtensionIfNeeded(beforeFile);
afterFile  = addTifExtensionIfNeeded(afterFile);

beforeRaw = imread(beforeFile);
afterRaw  = imread(afterFile);

beforeRaw = beforeRaw(:,:,1:3);
afterRaw  = afterRaw(:,:,1:3);

beforeAlignedRGB = double(beforeRaw);

beforeNorm = normalizeForRegistration(beforeRaw);
afterNorm  = normalizeForRegistration(afterRaw);

beforeMask = detectFilmMask(beforeNorm);
afterMask  = detectFilmMask(afterNorm);

[optimizer, metric] = imregconfig('monomodal');

optimizer.MaximumIterations = 800;
optimizer.MinimumStepLength = 1e-6;
optimizer.MaximumStepLength = 0.05;

Rfixed = imref2d(size(beforeNorm(:,:,1)));

% Step 1: rough rigid registration using film shape
tformRough = imregtform(double(afterMask), double(beforeMask), ...
    'rigid', optimizer, metric);

afterRoughNorm = imwarp(afterNorm, tformRough, ...
    'OutputView', Rfixed, ...
    'FillValues', 1);

afterRoughMask = imwarp(double(afterMask), tformRough, ...
    'OutputView', Rfixed, ...
    'FillValues', 0) > 0.5;

% Step 2: fine translation registration using common handwriting/text
beforeTextFeature = extractCommonTextFeature(beforeNorm, beforeMask, textRegion);
afterTextFeature  = extractCommonTextFeature(afterRoughNorm, afterRoughMask, textRegion);

optimizer.MaximumIterations = 500;
optimizer.MinimumStepLength = 1e-6;
optimizer.MaximumStepLength = 0.02;

tformFine = imregtform(double(afterTextFeature), double(beforeTextFeature), ...
    'translation', optimizer, metric);

% MATLAB affine2d uses row-vector convention.
% Apply rough first, then fine.
tformTotal = affine2d(tformRough.T * tformFine.T);

fillValueRaw = estimateScannerBackgroundValue(afterRaw);

afterAlignedRGB = imwarp(double(afterRaw), tformTotal, ...
    'OutputView', Rfixed, ...
    'FillValues', fillValueRaw);

afterRegMask = imwarp(double(afterMask), tformTotal, ...
    'OutputView', Rfixed, ...
    'FillValues', 0) > 0.5;

commonMask = beforeMask & afterRegMask;
commonMask = imerode(commonMask, strel('disk', 5));

regInfo = struct();
regInfo.tformRough = tformRough;
regInfo.tformFine  = tformFine;
regInfo.tformTotal = tformTotal;
regInfo.beforeMask = beforeMask;
regInfo.afterMaskOriginal = afterMask;
regInfo.afterMaskRegistered = afterRegMask;
regInfo.commonMask = commonMask;

if registerPreview
    figPreview = figure('Name','Registration preview','Color','w');
    figPreview.Units = 'pixels';
    figPreview.Position = [120, 120, 700, 520];
    [previewCy, previewCx] = centerOfMask(commonMask);
    [yAxisMm, xAxisMm] = imageAxesInMm(size(beforeNorm,1), size(beforeNorm,2), dpi, [previewCy, previewCx]);
    [previewXLim, previewYLim] = getSymmetricDisplayLimits(commonMask, xAxisMm, yAxisMm, 0.04);
    showRegistrationOverlayMm(beforeNorm, afterAlignedRGB, xAxisMm, yAxisMm);
    axis on image;
    applyImagePlotLimits(gca, previewXLim, previewYLim);
    xlabel('X (mm)');
    ylabel('Y (mm)');
    title({ ...
        'Registered result: before vs after, cropped', ...
        'Magenta = before-dominant | Green = after-dominant | Gray/white = matched' ...
        });
    formatFigure(figPreview, 'Arial', 12, 14);
end

end

%% ========================================================================
function [beforeAlignedRGB, afterAlignedRGB, regInfo] = readAfterOnlyRawRGB(afterFile)
% Read exposed/post-irradiation scan only.
% This mode is used when no prescan film is available. No registration is
% performed, and beta_k will be set to zero in the main workflow.

if isempty(afterFile)
    error('afterTif must be provided when UsePrescanBeta is false.');
end

afterFile = addTifExtensionIfNeeded(afterFile);
afterRaw = imread(afterFile);
afterRaw = afterRaw(:,:,1:3);

afterAlignedRGB = double(afterRaw);
beforeAlignedRGB = [];

afterNorm = normalizeForRegistration(afterRaw);
afterMask = detectFilmMask(afterNorm);
commonMask = imerode(afterMask, strel('disk', 5));

regInfo = struct();
regInfo.mode = 'no_prescan_after_only';
regInfo.tformRough = [];
regInfo.tformFine = [];
regInfo.tformTotal = [];
regInfo.beforeMask = [];
regInfo.afterMaskOriginal = afterMask;
regInfo.afterMaskRegistered = afterMask;
regInfo.commonMask = commonMask;

end


%% ========================================================================
function [yAxisMm, xAxisMm] = imageAxesInMm(numRows, numCols, dpi, originPixel)
% Create image axes in mm from pixel indices using scanner DPI.
%
% originPixel = [originRow, originCol]. The selected origin is displayed as
% x = 0 mm and y = 0 mm, so the axes go from negative to positive values.

if nargin < 4 || isempty(originPixel) || numel(originPixel) ~= 2 || any(~isfinite(originPixel))
    originPixel = [(numRows + 1) / 2, (numCols + 1) / 2];
end

originRow = double(originPixel(1));
originCol = double(originPixel(2));

xAxisMm = pixelIndexToMm(1:numCols, dpi, originCol);
yAxisMm = pixelIndexToMm(1:numRows, dpi, originRow);

end

%% ========================================================================
function posMm = pixelIndexToMm(pixelIndex, dpi, originIndex)
% Convert 1-based MATLAB pixel indices to physical position in mm.
% If originIndex is provided, that pixel is set to 0 mm.

if nargin < 3 || isempty(originIndex) || ~isfinite(originIndex)
    originIndex = 1;
end

posMm = (double(pixelIndex) - double(originIndex)) .* 25.4 ./ double(dpi);

end

%% ========================================================================
function showRegistrationOverlayMm(beforeRGB, afterRGB, xAxisMm, yAxisMm)
% Show a false-color registration overlay with physical axes in mm.

beforeDisp = normalizeForDisplay(beforeRGB);
afterDisp  = normalizeForDisplay(afterRGB);

beforeGray = rgb2gray(beforeDisp);
afterGray  = rgb2gray(afterDisp);

overlay = zeros([size(beforeGray), 3]);
overlay(:,:,1) = beforeGray;                    % magenta red component
overlay(:,:,2) = afterGray;                     % green component
overlay(:,:,3) = beforeGray;                    % magenta blue component

overlay = max(min(overlay, 1), 0);

image(xAxisMm, yAxisMm, overlay);

end

%% ========================================================================
function plotBetaDeltaLinearMaps(beta, delta, commonMask, xAxisMm, yAxisMm, plotXLim, plotYLim, cLim, mainTitle)
% Plot beta_R, beta_G, beta_B, and Delta using linear pixel-value scale.

mapData = {beta(:,:,1), beta(:,:,2), beta(:,:,3), delta};
mapTitles = {'\beta_R', '\beta_G', '\beta_B', '\Delta'};

for iMap = 1:4
    subplot(2,2,iMap);
    showMaskedImageMm(xAxisMm, yAxisMm, mapData{iMap}, commonMask);
    axis image;
    applyImagePlotLimits(gca, plotXLim, plotYLim);
    xlabel('X (mm)');
    ylabel('Y (mm)');
    cb = colorbar;
    cb.Label.String = 'Pixel value';

    if ~isempty(cLim) && numel(cLim) == 2 && all(isfinite(cLim)) && cLim(2) > cLim(1)
        caxis(cLim);
        title(mapTitles{iMap});
    else
        title(mapTitles{iMap});
    end
end

if nargin >= 7 && ~isempty(mainTitle)
    sgtitle(mainTitle);
end

end

%% ========================================================================
function cLim = getBetaDeltaDynamicCLim(beta, delta, commonMask, prctileValue, minAbsLimit, maxAbsLimit)
% Return a symmetric linear color range for beta/Delta visualization.
% The range is data driven but capped to avoid extreme outliers dominating
% the display. For example, with maxAbsLimit = 3000, very large artifacts such
% as +/- several ten-thousand pixel values will not control the color scale.

vals = [];
for k = 1:3
    tmp = beta(:,:,k);
    vals = [vals; tmp(commonMask)]; %#ok<AGROW>
end
vals = [vals; delta(commonMask)];
vals = double(vals(:));
vals = vals(isfinite(vals));

if isempty(vals)
    cLim = [-1 1];
    return;
end

absVals = abs(vals);
absVals = absVals(isfinite(absVals));

if isempty(absVals) || max(absVals) == 0
    cLim = [-1 1];
    return;
end

clipAbs = prctile(absVals, prctileValue);
clipAbs = max(clipAbs, minAbsLimit);
clipAbs = min(clipAbs, maxAbsLimit);

if ~isfinite(clipAbs) || clipAbs <= 0
    clipAbs = min(max(absVals), maxAbsLimit);
end

if ~isfinite(clipAbs) || clipAbs <= 0
    clipAbs = 1;
end

cLim = [-clipAbs, clipAbs];

end

%% ========================================================================
function hImg = showMaskedImageMm(xAxisMm, yAxisMm, img, filmMask)
% Display an image in physical coordinates and make non-film pixels white.

img = double(img);
if nargin < 4 || isempty(filmMask)
    filmMask = true(size(img));
end
filmMask = logical(filmMask);
if ~isequal(size(filmMask), size(img))
    filmMask = true(size(img));
end

hImg = imagesc(xAxisMm, yAxisMm, img);
set(gca, 'Color', 'w');
set(hImg, 'AlphaData', filmMask & isfinite(img));
axis image;

end

%% ========================================================================
function formatFigure(figHandle, fontName, fontSize, titleFontSize)
% Apply consistent font style and remove grid from all axes in a figure.

if nargin < 2 || isempty(fontName)
    fontName = 'Arial';
end
if nargin < 3 || isempty(fontSize)
    fontSize = 12;
end
if nargin < 4 || isempty(titleFontSize)
    titleFontSize = 12;
end

axList = findall(figHandle, 'Type', 'axes');
for iAx = 1:numel(axList)
    formatAxes(axList(iAx), fontName, fontSize, titleFontSize);
end

cbList = findall(figHandle, 'Type', 'ColorBar');
if isempty(cbList)
    cbList = findall(figHandle, 'Type', 'colorbar');
end
for iCb = 1:numel(cbList)
    cbList(iCb).FontName = fontName;
    cbList(iCb).FontSize = fontSize;
    if ~isempty(cbList(iCb).Label)
        cbList(iCb).Label.FontName = fontName;
        cbList(iCb).Label.FontSize = fontSize;
    end
end

lgdList = findall(figHandle, 'Type', 'Legend');
if isempty(lgdList)
    lgdList = findall(figHandle, 'Type', 'legend');
end
for iLgd = 1:numel(lgdList)
    lgdList(iLgd).FontName = fontName;
    lgdList(iLgd).FontSize = fontSize - 1;
    lgdList(iLgd).Box = 'off';
end

end

%% ========================================================================
function formatAxes(axHandle, fontName, fontSize, titleFontSize)
% Apply consistent font style to one axes and remove grid.

if isempty(axHandle) || ~isvalid(axHandle)
    return;
end

set(axHandle, 'FontName', fontName, 'FontSize', fontSize);
grid(axHandle, 'off');
box(axHandle, 'on');

if ~isempty(axHandle.XLabel)
    axHandle.XLabel.FontName = fontName;
    axHandle.XLabel.FontSize = fontSize;
end
if ~isempty(axHandle.YLabel)
    axHandle.YLabel.FontName = fontName;
    axHandle.YLabel.FontSize = fontSize;
end
if ~isempty(axHandle.Title)
    axHandle.Title.FontName = fontName;
    axHandle.Title.FontSize = titleFontSize;
    axHandle.Title.FontWeight = 'bold';
end


end


%% ========================================================================
function doseMapCLim = getDoseDisplayLimitsFromTriple(doseTriple)
% Return a common dose display range based on the triple-channel dose map.
% The same range is used for Red/Green/Blue/Triple dose maps.

vals = double(doseTriple(:));
vals = vals(isfinite(vals));

if isempty(vals)
    doseMapCLim = [];
    return;
end

maxVal = max(vals);

if ~isfinite(maxVal) || maxVal <= 0
    doseMapCLim = [];
else
    doseMapCLim = [0, maxVal];
end

end

%% ========================================================================
function setDoseColorLimits(axHandle, doseMapCLim)
% Apply common color limits if a valid range is available.

if isempty(doseMapCLim) || numel(doseMapCLim) ~= 2
    return;
end

if all(isfinite(doseMapCLim)) && doseMapCLim(2) > doseMapCLim(1)
    set(axHandle, 'CLim', doseMapCLim);
end

end

%% ========================================================================
function fileName = addTifExtensionIfNeeded(fileName)

fileName = char(fileName);
[~, ~, ext] = fileparts(fileName);

if isempty(ext)
    fileName = [fileName, '.tif'];
end

end

%% ========================================================================
function imgNorm = normalizeForRegistration(imgRaw)
% Convert RGB image to 0-1 for registration only.

imgRaw = double(imgRaw);

imgNorm = zeros(size(imgRaw));

for k = 1:3
    channel = imgRaw(:,:,k);
    lowVal  = prctile(channel(:), 0.5);
    highVal = prctile(channel(:), 99.5);

    if highVal <= lowVal
        imgNorm(:,:,k) = mat2gray(channel);
    else
        imgNorm(:,:,k) = (channel - lowVal) ./ (highVal - lowVal);
        imgNorm(:,:,k) = max(min(imgNorm(:,:,k), 1), 0);
    end
end

end

%% ========================================================================
function imgDisplay = normalizeForDisplay(imgRaw)
% Normalize RGB image for display.

imgRaw = double(imgRaw);
imgDisplay = zeros(size(imgRaw));

for k = 1:3
    channel = imgRaw(:,:,k);
    lowVal  = prctile(channel(:), 0.5);
    highVal = prctile(channel(:), 99.5);

    if highVal <= lowVal
        imgDisplay(:,:,k) = mat2gray(channel);
    else
        imgDisplay(:,:,k) = (channel - lowVal) ./ (highVal - lowVal);
        imgDisplay(:,:,k) = max(min(imgDisplay(:,:,k), 1), 0);
    end
end

end

%% ========================================================================
function bg = estimateScannerBackgroundValue(imgRaw)
% Estimate white scanner background value from image border.

imgRaw = double(imgRaw);

borderWidth = max(10, round(min(size(imgRaw,1), size(imgRaw,2)) * 0.02));

top    = imgRaw(1:borderWidth,:,:);
bottom = imgRaw(end-borderWidth+1:end,:,:);
left   = imgRaw(:,1:borderWidth,:);
right  = imgRaw(:,end-borderWidth+1:end,:);

borderPixels = [top(:); bottom(:); left(:); right(:)];

bg = median(borderPixels, 'omitnan');

if ~isfinite(bg)
    bg = max(imgRaw(:));
end

end

%% ========================================================================
function mask = detectFilmMask(rgbImage)
% Detect the largest film region from normalized RGB scanned image.

grayImage = rgb2gray(rgbImage);
graySmooth = imgaussfilt(grayImage, 3);

level = graythresh(graySmooth);

% Film is usually darker than scanner background.
mask = graySmooth < level * 1.15;

mask = imfill(mask, 'holes');
mask = bwareaopen(mask, 5000);

cc = bwconncomp(mask);

if cc.NumObjects == 0
    error('No film region detected.');
end

numPixels = cellfun(@numel, cc.PixelIdxList);
[~, idx] = max(numPixels);

mask = false(size(grayImage));
mask(cc.PixelIdxList{idx}) = true;

mask = imclose(mask, strel('disk', 10));
mask = imfill(mask, 'holes');

end

%% ========================================================================
function featureImg = extractCommonTextFeature(rgbImage, filmMask, textRegion)
% Extract handwriting/text feature from a fractional region of the film.
%
% textRegion = [xStartFrac xEndFrac yStartFrac yEndFrac]

grayImage = rgb2gray(rgbImage);

stats = regionprops(filmMask, 'BoundingBox');

if isempty(stats)
    error('No film mask found for text feature extraction.');
end

bbox = stats(1).BoundingBox;

x = round(bbox(1));
y = round(bbox(2));
w = round(bbox(3));
h = round(bbox(4));

xStartFrac = textRegion(1);
xEndFrac   = textRegion(2);
yStartFrac = textRegion(3);
yEndFrac   = textRegion(4);

x1 = max(1, x + round(xStartFrac * w));
x2 = min(size(grayImage,2), x + round(xEndFrac * w));

y1 = max(1, y + round(yStartFrac * h));
y2 = min(size(grayImage,1), y + round(yEndFrac * h));

roiMask = false(size(filmMask));
roiMask(y1:y2, x1:x2) = true;
roiMask = roiMask & filmMask;

if nnz(roiMask) < 100
    error('Text ROI is too small. Adjust TextRegion.');
end

grayForText = grayImage;
grayForText(~roiMask) = 1;

background = imgaussfilt(grayForText, 15);
textFeature = background - grayForText;

textFeature(textFeature < 0) = 0;
textFeature(~roiMask) = 0;

featureImg = mat2gray(textFeature);
featureImg = imadjust(featureImg);
featureImg = imgaussfilt(featureImg, 1);

end

%% ========================================================================
function calib = readFilmCalibrationTxt(filename)
% Read calibration TXT file between $BEGIN_DATA and $END_DATA.

txt = fileread(filename);
lines = regexp(txt, '\r\n|\n|\r', 'split');

inData = false;
header = {};
rows = {};

for i = 1:numel(lines)
    line = strtrim(lines{i});

    if strcmp(line, '$BEGIN_DATA')
        inData = true;
        continue;
    elseif strcmp(line, '$END_DATA')
        inData = false;
        break;
    end

    if inData && ~isempty(line)
        parts = regexp(line, '\t|\s+', 'split');
        parts = parts(~cellfun(@isempty, parts));

        if isempty(header)
            header = parts;
        else
            rows(end+1, :) = parts; %#ok<AGROW>
        end
    end
end

if isempty(header) || isempty(rows)
    error('No calibration data found in TXT file.');
end

dose  = zeros(size(rows,1),1);
meanR = zeros(size(rows,1),1);
meanG = zeros(size(rows,1),1);
meanB = zeros(size(rows,1),1);
sdR   = zeros(size(rows,1),1);
sdG   = zeros(size(rows,1),1);
sdB   = zeros(size(rows,1),1);

for i = 1:size(rows,1)
    dose(i)  = str2double(rows{i,2});
    meanR(i) = str2double(rows{i,3});
    meanG(i) = str2double(rows{i,4});
    meanB(i) = str2double(rows{i,5});
    sdR(i)   = str2double(rows{i,6});
    sdG(i)   = str2double(rows{i,7});
    sdB(i)   = str2double(rows{i,8});
end

calib = table(dose, meanR, meanG, meanB, sdR, sdG, sdB, ...
    'VariableNames', {'DOSE','MEAN_R','MEAN_G','MEAN_B','SD_R','SD_G','SD_B'});

end

%% ========================================================================
function p = fitRationalCalibration(D, X, SD, fitMethod, sigmaDose)
% Fit rational calibration curve:
%
%   D = (p1 - p2*X) / (X - p3)
%
% For numerical stability, fit inverse form:
%
%   X(D) = (q1 + q2*D) / (q3 + D)
%
% Conversion to the dose-from-pixel form used later:
%   p1 = q1
%   p2 = q3
%   p3 = q2
%
% Available fitting methods:
%   OLS : ordinary least squares in X(D)
%   WLS : weighted least squares using pixel-value SD only
%   EV  : effective variance fitting using both pixel-value SD and dose SD
%
% For EV fitting:
%   sigma_eff^2 = sigma_X^2 + (dX/dD)^2 * sigma_D^2
%
% where:
%   dX/dD = (q2*q3 - q1) / (q3 + D)^2

if nargin < 4 || isempty(fitMethod)
    fitMethod = 'EV';
end
fitMethod = upper(strtrim(char(fitMethod)));

D = D(:);
X = X(:);
SD = SD(:);

if nargin < 5 || isempty(sigmaDose)
    sigmaDose = zeros(size(D));
else
    sigmaDose = sigmaDose(:);
end

if numel(sigmaDose) == 1
    sigmaDose = repmat(sigmaDose, size(D));
end

valid = isfinite(D) & isfinite(X) & isfinite(SD) & SD > 0 & ...
        isfinite(sigmaDose) & sigmaDose >= 0;
D = D(valid);
X = X(valid);
SD = SD(valid);
sigmaDose = sigmaDose(valid);

if numel(D) < 4
    error('At least 4 valid calibration points are recommended for rational calibration fitting.');
end

[~, zeroIdx] = min(D);
X0 = X(zeroIdx);

q3_0 = max(D) / 2;
if ~isfinite(q3_0) || q3_0 <= 0
    q3_0 = 1;
end
q2_0 = max(0, min(X) * 0.8);
q1_0 = max(0, X0 * q3_0);

q0 = [q1_0, q2_0, q3_0];

modelX = @(q, d) (q(1) + q(2).*d) ./ (q(3) + d);
dXdD  = @(q, d) (q(2).*q(3) - q(1)) ./ (q(3) + d).^2;

switch fitMethod
    case 'OLS'
        weightFun = @(q) ones(size(D));
    case 'WLS'
        weightFun = @(q) SD;
    case 'EV'
        weightFun = @(q) sqrt(SD.^2 + (dXdD(q,D).^2) .* sigmaDose.^2);
    otherwise
        error('Unknown CalibrationFitMethod. Use EV, WLS, or OLS.');
end

% Residuals are normalized by the selected uncertainty model.
residualFun = @(q) (modelX(q,D) - X) ./ max(weightFun(q), eps);

if exist('lsqnonlin', 'file') == 2
    lb = [0, 0, 1e-6];
    ub = [Inf, Inf, Inf];

    opts = optimoptions('lsqnonlin', ...
        'Display','off', ...
        'MaxIterations', 3000, ...
        'FunctionTolerance', 1e-12, ...
        'StepTolerance', 1e-12, ...
        'OptimalityTolerance', 1e-12);

    q = lsqnonlin(residualFun, q0, lb, ub, opts);

elseif exist('lsqcurvefit', 'file') == 2 && ~strcmp(fitMethod, 'EV')
    % For OLS/WLS, the weights do not depend on q, so lsqcurvefit is simple.
    lb = [0, 0, 1e-6];
    ub = [Inf, Inf, Inf];
    w = max(weightFun(q0), eps);

    opts = optimoptions('lsqcurvefit', ...
        'Display','off', ...
        'MaxIterations', 3000, ...
        'FunctionTolerance', 1e-12, ...
        'StepTolerance', 1e-12);

    q = lsqcurvefit(@(q,d) modelX(q,d)./w, q0, D, X./w, lb, ub, opts);

else
    % Toolbox-free fallback. This also supports EV because the effective
    % variance is recalculated inside the objective at each q.
    obj = @(q) sum(residualFun(q).^2) + penaltyQ(q);
    opts = optimset('Display','off', 'MaxIter', 10000, 'MaxFunEvals', 50000, ...
        'TolX', 1e-12, 'TolFun', 1e-12);
    q = fminsearch(obj, q0, opts);

    % Project extremely small negative values caused by unconstrained
    % fminsearch back to valid bounds.
    q(1) = max(q(1), 0);
    q(2) = max(q(2), 0);
    q(3) = max(q(3), 1e-6);
end

p = [q(1), q(3), q(2)];

end

%% ========================================================================
function X = inverseRationalPixelModel(p, D)
% Convert dose to pixel value using the inverse calibration form.
% p stores [q1, q3, q2], where:
%   X(D) = (q1 + q2*D) / (q3 + D)

q1 = p(1);
q3 = p(2);
q2 = p(3);

X = (q1 + q2.*D) ./ (q3 + D);

end

%% ========================================================================
function R2 = calculateRSquared(yMeasured, yPredicted)
% Calculate ordinary coefficient of determination R^2.

yMeasured = yMeasured(:);
yPredicted = yPredicted(:);

valid = isfinite(yMeasured) & isfinite(yPredicted);
yMeasured = yMeasured(valid);
yPredicted = yPredicted(valid);

if numel(yMeasured) < 2
    R2 = NaN;
    return;
end

ssRes = sum((yMeasured - yPredicted).^2);
ssTot = sum((yMeasured - mean(yMeasured)).^2);

if ssTot <= eps
    R2 = NaN;
else
    R2 = 1 - ssRes ./ ssTot;
end

end

%% ========================================================================
function penalty = penaltyQ(q)

penalty = 0;

if any(~isfinite(q))
    penalty = 1e30;
    return;
end

if q(1) < 0
    penalty = penalty + 1e20 * (abs(q(1)) + 1);
end

if q(2) < 0
    penalty = penalty + 1e20 * (abs(q(2)) + 1);
end

if q(3) <= 0
    penalty = penalty + 1e20 * (abs(q(3)) + 1);
end

end

%% ========================================================================
function D = rationalDoseModel(p, X)
% D = (p1 - p2*X)/(X - p3)

D = (p(1) - p(2).*X) ./ (X - p(3));

end

%% ========================================================================
function doseRGB = pixelToDoseRGB(rgb, p)
% Convert RGB pixel values to scanned dose for each channel.

rgb = double(rgb);
doseRGB = zeros(size(rgb));

for k = 1:3
    doseRGB(:,:,k) = rationalDoseModel(p(k,:), rgb(:,:,k));
end

doseRGB(~isfinite(doseRGB)) = NaN;

end

%% ========================================================================
function [alpha, alphaP] = alphaFromDose(D, p)
% Calculate alpha and derivative of alpha with respect to D.

alpha  = zeros([size(D), 3]);
alphaP = zeros([size(D), 3]);

for k = 1:3
    p1 = p(k,1);
    p2 = p(k,2);
    p3 = p(k,3);

    denom = p2*p3 - p1;

    alpha(:,:,k)  = (p2 + D).^2 ./ denom;
    alphaP(:,:,k) = 2*(p2 + D) ./ denom;
end

end

%% ========================================================================
function beta = estimateBetaFromUnexposed(doseUnexposedRGB, p, maxDose, mask)
% Estimate beta correction maps from registered unexposed image.

[H,W,~] = size(doseUnexposedRGB);

Dzero = zeros(H,W);
[alpha0, ~] = alphaFromDose(Dzero, p);

beta = zeros(H,W,3);

for k = 1:3
    beta(:,:,k) = -doseUnexposedRGB(:,:,k) ./ alpha0(:,:,k);
end

beta(~isfinite(beta)) = 0;

nIter = 8;

for it = 1:nIter
    [~, delta0] = solveTripleChannelDose(doseUnexposedRGB, beta, p, maxDose, mask);

    betaNew = zeros(H,W,3);

    for k = 1:3
        betaNew(:,:,k) = -doseUnexposedRGB(:,:,k) ./ alpha0(:,:,k) + delta0;
    end

    betaNew(~isfinite(betaNew)) = 0;

    mask3 = repmat(mask, [1 1 3]);
    diffMap = abs(betaNew - beta);
    diffMap = diffMap(mask3);

    meanChange = mean(diffMap(:), 'omitnan');

    beta = betaNew;

    if meanChange < 1e-6
        break;
    end
end

end

%% ========================================================================
function [D, Delta, solverInfo] = solveTripleChannelDose(Dscan, beta, p, maxDose, mask)
% Solve triple-channel dose using damped Gauss-Newton.
%
% This minimizes Eq. 6 directly by using the residual:
%   r_k = Dscan_k + alpha_k*beta_k - alpha_k*Delta - D
%
% The first-order optimality conditions are:
%   gD     = sum_k (dr_k/dD)     * r_k = 0   equivalent to Eq. 7
%   gDelta = sum_k (dr_k/dDelta) * r_k = 0   equivalent to Eq. 8
%
% Here:
%   dr_k/dD     = alphaP_k*(beta_k - Delta) - 1
%   dr_k/dDelta = -alpha_k
%
% The update uses a damped Gauss-Newton approximation, H = J'*J.
% Convergence is now checked using both D and Delta step sizes, and the
% final gradient magnitudes are stored for diagnostic confirmation that the
% Eq. 7 and Eq. 8 optimality conditions have been approximately satisfied.

[H,W,~] = size(Dscan);

Dinit = meanFiniteAcrossChannels(Dscan);
Dinit(~isfinite(Dinit)) = 0;
Dinit(Dinit < 0) = 0;
Dinit(Dinit > maxDose) = maxDose;

D = Dinit;
Delta = zeros(H,W);

lambda = 1e-8;
maxIter = 50;
tolD = 1e-5;          % cGy
tolDelta = 1e-5;     % pixel value

history = struct();
history.maxStepD_cGy = nan(maxIter,1);
history.maxStepDelta_pixelValue = nan(maxIter,1);
history.maxGradD = nan(maxIter,1);
history.maxGradDelta = nan(maxIter,1);
history.meanSquaredResidual = nan(maxIter,1);

converged = false;
reason = 'maximum iterations reached';
lastMaxStepD = NaN;
lastMaxStepDelta = NaN;
lastMaxGradD = NaN;
lastMaxGradDelta = NaN;
lastMeanSquaredResidual = NaN;

for it = 1:maxIter
    [alpha, alphaP] = alphaFromDose(D, p);

    r  = zeros(H,W,3);
    JD = zeros(H,W,3);
    JT = zeros(H,W,3);

    for k = 1:3
        r(:,:,k) = Dscan(:,:,k) + alpha(:,:,k).*beta(:,:,k) ...
                   - alpha(:,:,k).*Delta - D;

        JD(:,:,k) = alphaP(:,:,k).*(beta(:,:,k) - Delta) - 1;
        JT(:,:,k) = -alpha(:,:,k);
    end

    bad = ~isfinite(r) | ~isfinite(JD) | ~isfinite(JT);

    r(bad)  = 0;
    JD(bad) = 0;
    JT(bad) = 0;

    gD = sum(JD .* r, 3);
    gT = sum(JT .* r, 3);

    H11 = sum(JD .* JD, 3) + lambda;
    H22 = sum(JT .* JT, 3) + lambda;
    H12 = sum(JD .* JT, 3);

    detH = H11 .* H22 - H12.^2;
    detH(abs(detH) < eps) = eps;

    stepD = (-gD .* H22 + H12 .* gT) ./ detH;
    stepT = ( H12 .* gD  - H11 .* gT) ./ detH;

    stepD(~mask) = 0;
    stepT(~mask) = 0;

    stepD = max(min(stepD, maxDose/2), -maxDose/2);
    stepT = max(min(stepT, 1e5), -1e5);

    Dnew = D + stepD;
    Tnew = Delta + stepT;

    Dnew(Dnew < 0) = 0;
    Dnew(Dnew > maxDose) = maxDose;

    activeStepD = abs(stepD(mask));
    activeStepT = abs(stepT(mask));
    activeGradD = abs(gD(mask));
    activeGradT = abs(gT(mask));
    activeResidual = r(repmat(mask, [1 1 3]));

    lastMaxStepD = max(activeStepD(:), [], 'omitnan');
    lastMaxStepDelta = max(activeStepT(:), [], 'omitnan');
    lastMaxGradD = max(activeGradD(:), [], 'omitnan');
    lastMaxGradDelta = max(activeGradT(:), [], 'omitnan');
    lastMeanSquaredResidual = mean(activeResidual(:).^2, 'omitnan');

    history.maxStepD_cGy(it) = lastMaxStepD;
    history.maxStepDelta_pixelValue(it) = lastMaxStepDelta;
    history.maxGradD(it) = lastMaxGradD;
    history.maxGradDelta(it) = lastMaxGradDelta;
    history.meanSquaredResidual(it) = lastMeanSquaredResidual;

    D = Dnew;
    Delta = Tnew;

    if lastMaxStepD < tolD && lastMaxStepDelta < tolDelta
        converged = true;
        reason = 'D and Delta step tolerances satisfied';
        break;
    end
end

D(~isfinite(D)) = NaN;
Delta(~isfinite(Delta)) = NaN;

history.maxStepD_cGy = history.maxStepD_cGy(1:it);
history.maxStepDelta_pixelValue = history.maxStepDelta_pixelValue(1:it);
history.maxGradD = history.maxGradD(1:it);
history.maxGradDelta = history.maxGradDelta(1:it);
history.meanSquaredResidual = history.meanSquaredResidual(1:it);

solverInfo = struct();
solverInfo.method = 'damped Gauss-Newton minimization of Eq. 6';
solverInfo.converged = converged;
solverInfo.reason = reason;
solverInfo.numIterations = it;
solverInfo.maxIterations = maxIter;
solverInfo.lambda = lambda;
solverInfo.tolD_cGy = tolD;
solverInfo.tolDelta_pixelValue = tolDelta;
solverInfo.finalMaxStepD_cGy = lastMaxStepD;
solverInfo.finalMaxStepDelta_pixelValue = lastMaxStepDelta;
solverInfo.finalMaxGradD = lastMaxGradD;
solverInfo.finalMaxGradDelta = lastMaxGradDelta;
solverInfo.finalMeanSquaredResidual = lastMeanSquaredResidual;
solverInfo.history = history;

end

%% ========================================================================
function M = meanFiniteAcrossChannels(A)
% Mean across third dimension while ignoring NaN/Inf.

valid = isfinite(A);
A2 = A;
A2(~valid) = 0;

sumA = sum(A2, 3);
countA = sum(valid, 3);

M = sumA ./ countA;
M(countA == 0) = NaN;

end

%% ========================================================================
function [cy, cx] = centerOfMask(mask)

stats = regionprops(mask, 'Centroid');

if isempty(stats)
    cy = round(size(mask,1)/2);
    cx = round(size(mask,2)/2);
else
    c = stats(1).Centroid;
    cx = round(c(1));
    cy = round(c(2));

    cx = max(1, min(size(mask,2), cx));
    cy = max(1, min(size(mask,1), cy));
end

end

%% ========================================================================
function [x, pR, pG, pB, pT] = extractCleanProfileHorizontal( ...
    doseR, doseG, doseB, doseT, mask, cy, edgeTrimFrac, highPrctile)

rowMask = mask(cy,:);

idx = find(rowMask);

if isempty(idx)
    x = 1:size(mask,2);
else
    x1 = min(idx);
    x2 = max(idx);

    width = x2 - x1 + 1;
    trimPix = round(edgeTrimFrac * width);

    x1 = x1 + trimPix;
    x2 = x2 - trimPix;

    x1 = max(1, x1);
    x2 = min(size(mask,2), x2);

    x = x1:x2;
end

pR = doseR(cy,x);
pG = doseG(cy,x);
pB = doseB(cy,x);
pT = doseT(cy,x);

[pR, pG, pB, pT] = removeAbnormalHighProfileValues(pR, pG, pB, pT, highPrctile);

end

%% ========================================================================
function [y, pR, pG, pB, pT] = extractCleanProfileVertical( ...
    doseR, doseG, doseB, doseT, mask, cx, edgeTrimFrac, highPrctile)

colMask = mask(:,cx);

idx = find(colMask);

if isempty(idx)
    y = 1:size(mask,1);
else
    y1 = min(idx);
    y2 = max(idx);

    height = y2 - y1 + 1;
    trimPix = round(edgeTrimFrac * height);

    y1 = y1 + trimPix;
    y2 = y2 - trimPix;

    y1 = max(1, y1);
    y2 = min(size(mask,1), y2);

    y = y1:y2;
end

pR = doseR(y,cx);
pG = doseG(y,cx);
pB = doseB(y,cx);
pT = doseT(y,cx);

[pR, pG, pB, pT] = removeAbnormalHighProfileValues(pR, pG, pB, pT, highPrctile);

end

%% ========================================================================
function [pR, pG, pB, pT] = removeAbnormalHighProfileValues(pR, pG, pB, pT, highPrctile)
% Remove abnormal high values from profile by replacing them with NaN.

allVals = [pR(:); pG(:); pB(:); pT(:)];
allVals = allVals(isfinite(allVals));

if isempty(allVals)
    return;
end

highLimit = prctile(allVals, highPrctile);

pR(pR > highLimit) = NaN;
pG(pG > highLimit) = NaN;
pB(pB > highLimit) = NaN;
pT(pT > highLimit) = NaN;

end

%% ========================================================================
function y = medianFilterProfile(x, windowSize)
% Apply median filtering to 1D profile while preserving NaN values.

x = double(x);
y = x;

valid = isfinite(x);

if nnz(valid) < windowSize
    return;
end

xFill = x;

if any(~valid)
    validIdx = find(valid);
    allIdx = 1:numel(x);

    xFill(~valid) = interp1(validIdx, x(valid), allIdx(~valid), ...
        'linear', 'extrap');
end

if exist('medfilt1', 'file') == 2
    try
        yFiltered = medfilt1(xFill, windowSize, 'omitnan', 'truncate');
    catch
        yFiltered = medfilt1(xFill, windowSize);
    end
else
    halfWin = floor(windowSize / 2);
    yFiltered = xFill;

    for i = 1:numel(xFill)
        i1 = max(1, i - halfWin);
        i2 = min(numel(xFill), i + halfWin);
        yFiltered(i) = median(xFill(i1:i2), 'omitnan');
    end
end

y = yFiltered;
y(~valid) = NaN;

end

%% ========================================================================
function shapeInfo = classifyDoseRegionShape(stats)
% Classify the detected irradiated dose region based on its binary mask geometry.
% This is used only for selecting the plotting coordinate origin.
%
% Regular dose regions accepted for origin centering:
%   - square
%   - rectangle
%   - circle
%
% The thresholds are intentionally tolerant because the detected dose region
% may include penumbra, smoothing, and small boundary irregularities.

areaVal = double(stats.Area);
perimeterVal = double(stats.Perimeter);
bbox = double(stats.BoundingBox);
width = max(bbox(3), eps);
height = max(bbox(4), eps);
aspectRatio = max(width, height) / max(min(width, height), eps);
extentVal = double(stats.Extent);
majorAxis = double(stats.MajorAxisLength);
minorAxis = double(stats.MinorAxisLength);
axisRatio = majorAxis / max(minorAxis, eps);

if isfinite(perimeterVal) && perimeterVal > 0
    circularity = 4 * pi * areaVal / (perimeterVal^2);
else
    circularity = 0;
end

isCircle = circularity >= 0.65 && axisRatio <= 1.30;
isRectangleLike = extentVal >= 0.70 && aspectRatio <= 6.0;
isSquare = isRectangleLike && aspectRatio <= 1.25;
isRectangle = isRectangleLike && ~isSquare;

if isCircle
    shapeName = 'circle';
    isRegular = true;
elseif isSquare
    shapeName = 'square';
    isRegular = true;
elseif isRectangle
    shapeName = 'rectangle';
    isRegular = true;
else
    shapeName = 'irregular';
    isRegular = false;
end

shapeInfo = struct();
shapeInfo.shape = shapeName;
shapeInfo.isRegular = isRegular;
shapeInfo.areaPixel = areaVal;
shapeInfo.boundingBox = bbox;
shapeInfo.aspectRatio = aspectRatio;
shapeInfo.extent = extentVal;
shapeInfo.circularity = circularity;
shapeInfo.axisRatio = axisRatio;
shapeInfo.majorAxisLength = majorAxis;
shapeInfo.minorAxisLength = minorAxis;

end

%% ========================================================================
function [meanDose, roi, roiCenter, doseMask, roiInfo] = meanDoseCenterDoseRegionMm(doseMatrix, figureSaveName, varargin)
% meanDoseCenterDoseRegionMm
%
% Find the center of the actual irradiated dose region, then calculate
% the mean dose inside an ROI specified in mm. Pixel-to-mm conversion uses
% the scanner DPI.
%
% Default ROI size is 5 mm x 5 mm.
%
% Outputs:
%   meanDose  - mean dose inside ROI, in cGy if doseMatrix is in cGy
%   roi       - extracted ROI matrix
%   roiCenter - [row, col] center of detected dose region in pixels
%   doseMask  - binary mask of detected dose region
%   roiInfo   - struct containing ROI size and position in pixels and mm

ip = inputParser;
ip.addRequired('doseMatrix', @(x) isnumeric(x) && ismatrix(x));
ip.addRequired('figureSaveName', @(x) ischar(x) || isstring(x));
ip.addParameter('DPI', 300, @(x) isnumeric(x) && isscalar(x) && x > 0);
ip.addParameter('ROISize_mm', [5 5], @(x) isnumeric(x) && (isscalar(x) || numel(x) == 2) && all(x(:) > 0));
ip.addParameter('ThresholdRatio', 0.30, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
ip.addParameter('ShowFigure', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('SaveFigure', true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('FilmMask', [], @(x) isempty(x) || islogical(x) || isnumeric(x));
ip.parse(doseMatrix, figureSaveName, varargin{:});

dpi = double(ip.Results.DPI);
pixelSizeMm = 25.4 / dpi;
roiSizeMm = double(ip.Results.ROISize_mm);
if isscalar(roiSizeMm)
    roiSizeMm = [roiSizeMm roiSizeMm];
else
    roiSizeMm = roiSizeMm(:).';
end
thresholdRatio = ip.Results.ThresholdRatio;
showFigure = logical(ip.Results.ShowFigure);
saveFigure = logical(ip.Results.SaveFigure);
filmMaskForDisplay = ip.Results.FilmMask;
figureSaveName = char(figureSaveName);

doseMatrix = double(doseMatrix);
[numRows, numCols] = size(doseMatrix);
if isempty(filmMaskForDisplay)
    filmMaskForDisplay = isfinite(doseMatrix);
else
    filmMaskForDisplay = logical(filmMaskForDisplay);
    if ~isequal(size(filmMaskForDisplay), size(doseMatrix))
        filmMaskForDisplay = isfinite(doseMatrix);
    end
end

roiHeightPix = max(1, round(roiSizeMm(1) / pixelSizeMm));
roiWidthPix  = max(1, round(roiSizeMm(2) / pixelSizeMm));

if numRows < roiHeightPix || numCols < roiWidthPix
    error('doseMatrix must be larger than the requested ROI size. Requested ROI = %.3f x %.3f mm, equivalent to %d x %d pixels at %.1f DPI.', ...
        roiSizeMm(1), roiSizeMm(2), roiHeightPix, roiWidthPix, dpi);
end

%% Remove NaN and Inf for processing
doseForMask = doseMatrix;
doseForMask(~isfinite(doseForMask)) = NaN;

validDose = doseForMask(isfinite(doseForMask));

if isempty(validDose)
    error('doseMatrix does not contain valid dose values.');
end

%% Smooth dose image for robust dose-region detection
% This smoothing is only used for detecting the dose region.
% The mean dose is still calculated from the original doseMatrix.
sigmaMm = 0.5;
sigmaPix = max(1, sigmaMm / pixelSizeMm);
doseFill = doseForMask;
fillValue = prctile(validDose, 1);
doseFill(~isfinite(doseFill)) = fillValue;
doseSmooth = imgaussfilt(doseFill, sigmaPix);

%% Determine threshold based on dose range
doseMin = prctile(validDose, 1);
doseMax = prctile(validDose, 99);

thresholdValue = doseMin + thresholdRatio * (doseMax - doseMin);

initialMask = doseSmooth > thresholdValue;
initialMask(~isfinite(doseForMask)) = false;
initialMask(~filmMaskForDisplay) = false;

%% Clean binary mask
initialMask = imfill(initialMask, 'holes');
minAreaMm2 = 1.0;
minAreaPix = max(10, round(minAreaMm2 / (pixelSizeMm^2)));
initialMask = bwareaopen(initialMask, minAreaPix);

%% Keep the largest connected component
cc = bwconncomp(initialMask);

if cc.NumObjects == 0
    error('No dose region was detected. Try lowering DoseRegionThresholdRatio, for example 0.15 or 0.20.');
end

componentAreas = cellfun(@numel, cc.PixelIdxList);
[~, largestIdx] = max(componentAreas);

doseMask = false(size(initialMask));
doseMask(cc.PixelIdxList{largestIdx}) = true;

%% Smooth mask boundary
closeRadiusMm = 0.8;
closeRadiusPix = max(1, round(closeRadiusMm / pixelSizeMm));
se = strel('disk', closeRadiusPix);
doseMask = imclose(doseMask, se);
doseMask = imfill(doseMask, 'holes');

%% Find center of the detected dose region
stats = regionprops(doseMask, 'Centroid', 'BoundingBox', 'Area', 'Perimeter', 'MajorAxisLength', 'MinorAxisLength', 'Extent', 'Eccentricity');

if isempty(stats)
    error('Dose region detection failed.');
end

centroid = stats(1).Centroid;

centerCol = round(centroid(1));
centerRow = round(centroid(2));

roiCenter = [centerRow, centerCol];

% Decide the coordinate origin for this case.
% If the irradiated dose region itself is a regular rectangle, square, or circle,
% use the dose-region center as the coordinate origin. Otherwise, use the film center.
doseRegionShape = classifyDoseRegionShape(stats(1));
[filmCenterRow, filmCenterCol] = centerOfMask(filmMaskForDisplay);

if doseRegionShape.isRegular
    coordinateOriginPixel = [centerRow, centerCol];
    coordinateOriginMode = ['dose_region_center_', doseRegionShape.shape];
else
    coordinateOriginPixel = [filmCenterRow, filmCenterCol];
    coordinateOriginMode = 'film_center';
end

originRow = coordinateOriginPixel(1);
originCol = coordinateOriginPixel(2);
roiCenterMm = [pixelIndexToMm(centerRow, dpi, originRow), pixelIndexToMm(centerCol, dpi, originCol)];

%% Define ROI around detected dose-region center
rowStart = round(centerRow - (roiHeightPix - 1) / 2);
rowEnd   = rowStart + roiHeightPix - 1;

colStart = round(centerCol - (roiWidthPix - 1) / 2);
colEnd   = colStart + roiWidthPix - 1;

%% Make sure ROI is inside image boundary
if rowStart < 1
    rowStart = 1;
    rowEnd = roiHeightPix;
end

if colStart < 1
    colStart = 1;
    colEnd = roiWidthPix;
end

if rowEnd > numRows
    rowEnd = numRows;
    rowStart = numRows - roiHeightPix + 1;
end

if colEnd > numCols
    colEnd = numCols;
    colStart = numCols - roiWidthPix + 1;
end

%% Extract ROI and calculate mean dose
roi = doseMatrix(rowStart:rowEnd, colStart:colEnd);
meanDose = mean(roi(:), 'omitnan');

actualRoiSizeMm = [roiHeightPix, roiWidthPix] .* pixelSizeMm;
roiInfo = struct();
roiInfo.requestedSizeMm = roiSizeMm;
roiInfo.actualSizeMm = actualRoiSizeMm;
roiInfo.sizePixel = [roiHeightPix, roiWidthPix];
roiInfo.centerPixel = roiCenter;
roiInfo.centerMm_RowCol = roiCenterMm;
roiInfo.rowRangePixel = [rowStart, rowEnd];
roiInfo.colRangePixel = [colStart, colEnd];
roiInfo.rowRangeMm = pixelIndexToMm([rowStart, rowEnd], dpi, originRow);
roiInfo.colRangeMm = pixelIndexToMm([colStart, colEnd], dpi, originCol);
roiInfo.coordinateOriginPixel = coordinateOriginPixel;
roiInfo.coordinateOriginMode = coordinateOriginMode;
roiInfo.doseRegionShape = doseRegionShape;
roiInfo.filmCenterPixel = [filmCenterRow, filmCenterCol];
roiInfo.thresholdRatio = thresholdRatio;
roiInfo.thresholdValue_cGy = thresholdValue;
roiInfo.dpi = dpi;
roiInfo.pixelSizeMm = pixelSizeMm;

%% Visualization and save figure
fig = figure('Name','Central dose-region ROI','Color','w', ...
    'Visible', matlab.lang.OnOffSwitchState(showFigure));
fig.Units = 'pixels';
fig.Position = [140, 140, 560, 480];

[yAxisMm, xAxisMm] = imageAxesInMm(numRows, numCols, dpi, coordinateOriginPixel);
[roiPlotXLim, roiPlotYLim] = getSymmetricDisplayLimits(filmMaskForDisplay, xAxisMm, yAxisMm, 0.04);
showMaskedImageMm(xAxisMm, yAxisMm, doseMatrix, filmMaskForDisplay);
axis image;
applyImagePlotLimits(gca, roiPlotXLim, roiPlotYLim);
xlabel('X (mm)');
ylabel('Y (mm)');
cb = colorbar;
cb.Label.String = 'Dose (cGy)';
hold on;

title(sprintf('Dose distribution with %.2f x %.2f mm^2 ROI', actualRoiSizeMm(2), actualRoiSizeMm(1)));

% Show detected dose region boundary in mm.
boundaries = bwboundaries(doseMask);
for k = 1:length(boundaries)
    boundary = boundaries{k};
    plot(pixelIndexToMm(boundary(:,2), dpi, originCol), ...
         pixelIndexToMm(boundary(:,1), dpi, originRow), ...
         'w-', 'LineWidth', 1.5);
end

% Show ROI in mm. Rectangle position = [x, y, width, height].
rectangle('Position', ...
    [pixelIndexToMm(colStart, dpi, originCol), ...
     pixelIndexToMm(rowStart, dpi, originRow), ...
     roiWidthPix * pixelSizeMm, ...
     roiHeightPix * pixelSizeMm], ...
    'EdgeColor', 'r', ...
    'LineWidth', 2);

% Show detected center in mm.
plot(pixelIndexToMm(centerCol, dpi, originCol), ...
     pixelIndexToMm(centerRow, dpi, originRow), ...
     'rx', 'MarkerSize', 12, 'LineWidth', 2);

text(pixelIndexToMm(centerCol, dpi, originCol) + 1.0, ...
     pixelIndexToMm(centerRow, dpi, originRow), ...
    sprintf('Mean = %.3f cGy', meanDose), ...
    'Color', 'w', ...
    'FontSize', 12, ...
    'FontWeight', 'bold');

hold off;
formatFigure(fig, 'Arial', 12, 12);

%% Create output folder if needed
[saveFolder, ~, ~] = fileparts(figureSaveName);

if ~isempty(saveFolder) && ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end

%% Save figure
if saveFigure
    [~, ~, ext] = fileparts(figureSaveName);

    if isempty(ext)
        figureSaveName = [figureSaveName, '.png'];
        ext = '.png';
    end

    if strcmpi(ext, '.png')
        exportgraphics(fig, figureSaveName, 'Resolution', dpi);
    else
        saveas(fig, figureSaveName);
    end
end

if ~showFigure
    close(fig);
end

end

