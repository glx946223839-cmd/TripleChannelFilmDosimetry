function filmTripleChannelGUI()
%==================================================================
% Author: Lixiang Guo, Email: realLixiangGuo@Outlook.com
%==================================================================
% filmTripleChannelGUI
%
% MATLAB graphical user interface for reconstructDoseTripleChannelRegistered.
%
% This GUI is a wrapper. It does NOT replace your reconstruction function.
% Put this file in the same folder as:
%
%   reconstructDoseTripleChannelRegistered.m
%
% Then run:
%
%   filmTripleChannelGUI
%
% Main features:
%   1. Select calibration TXT file.
%   2. Select before/unexposed TIFF file.
%   3. Select after/exposed TIFF file.
%   4. Choose output folder and output prefix.
%   5. Set commonly used options, including EV/WLS/OLS calibration fitting.
%   6. Run the reconstruction function.
%   7. Display run status and key outputs.
%
% Notes:
%   - This GUI assumes reconstructDoseTripleChannelRegistered supports:
%       'CalibrationFitMethod'
%       'DoseUncertaintyPercent'
%       'DoseUncertaintyMin_cGy'
%     If your current reconstruction function does not support these options,
%     either use the updated version or remove those name-value pairs below.
%
% Author: ChatGPT-assisted MATLAB GUI wrapper

%% Check dependency
if exist('reconstructDoseTripleChannelRegistered', 'file') ~= 2
    warning(['reconstructDoseTripleChannelRegistered.m was not found on the MATLAB path. ', ...
             'The GUI can still open, but Run will fail until the function is available.']);
end

%% Main figure
app = struct();

screenSize = get(0, 'ScreenSize');
figW = 980;
figH = 760;
figX = max(50, round((screenSize(3) - figW) / 2));
figY = max(50, round((screenSize(4) - figH) / 2));

app.fig = uifigure( ...
    'Name', 'Triple-Channel Film Dosimetry GUI', ...
    'Position', [figX figY figW figH], ...
    'Color', [0.97 0.97 0.97]);

% Main grid
mainGrid = uigridlayout(app.fig, [3 1]);
mainGrid.RowHeight = {70, '1x', 150};
mainGrid.ColumnWidth = {'1x'};
mainGrid.Padding = [16 14 16 14];
mainGrid.RowSpacing = 12;

%% Header
headerPanel = uipanel(mainGrid, 'BorderType', 'none', 'BackgroundColor', [0.97 0.97 0.97]);
headerGrid = uigridlayout(headerPanel, [2 1]);
headerGrid.RowHeight = {32, 22};
headerGrid.Padding = [0 0 0 0];

titleLabel = uilabel(headerGrid);
titleLabel.Text = 'Triple-Channel Film Dosimetry Reconstruction';
titleLabel.FontSize = 22;
titleLabel.FontWeight = 'bold';

subtitleLabel = uilabel(headerGrid);
subtitleLabel.Text = 'GUI wrapper for reconstructDoseTripleChannelRegistered.m';
subtitleLabel.FontSize = 12;
subtitleLabel.FontColor = [0.35 0.35 0.35];

%% Center panel with tabs
tabGroup = uitabgroup(mainGrid);

tabInput = uitab(tabGroup, 'Title', 'Input Files');
tabOptions = uitab(tabGroup, 'Title', 'Reconstruction Options');
tabAdvanced = uitab(tabGroup, 'Title', 'Advanced / Plot Options');

%% Input tab
inputGrid = uigridlayout(tabInput, [9 4]);
inputGrid.RowHeight = {44, 44, 44, 44, 44, 38, 12, 36, '1x'};
inputGrid.ColumnWidth = {170, '1x', 125, 125};
inputGrid.Padding = [16 16 16 16];
inputGrid.RowSpacing = 10;
inputGrid.ColumnSpacing = 10;

% Calibration file
uilabel(inputGrid, 'Text', 'Calibration TXT:', 'FontWeight', 'bold');
app.calibrationEdit = uieditfield(inputGrid, 'text');
app.calibrationEdit.Layout.Column = 2;
uibutton(inputGrid, 'Text', 'Browse...', ...
    'ButtonPushedFcn', @(~,~) browseFile(app.calibrationEdit, {'*.txt;*.TXT','Calibration TXT (*.txt)'}, 'Select calibration file'));
uibutton(inputGrid, 'Text', 'Open Folder', ...
    'ButtonPushedFcn', @(~,~) openParentFolder(app.calibrationEdit.Value));

% Before file
uilabel(inputGrid, 'Text', 'Before TIFF:', 'FontWeight', 'bold');
app.beforeEdit = uieditfield(inputGrid, 'text');
app.beforeEdit.Layout.Column = 2;
uibutton(inputGrid, 'Text', 'Browse...', ...
    'ButtonPushedFcn', @(~,~) browseFile(app.beforeEdit, {'*.tif;*.tiff;*.TIF;*.TIFF','TIFF files (*.tif, *.tiff)'}, 'Select before/unexposed TIFF'));
uibutton(inputGrid, 'Text', 'Open Folder', ...
    'ButtonPushedFcn', @(~,~) openParentFolder(app.beforeEdit.Value));

% After file
uilabel(inputGrid, 'Text', 'After TIFF:', 'FontWeight', 'bold');
app.afterEdit = uieditfield(inputGrid, 'text');
app.afterEdit.Layout.Column = 2;
uibutton(inputGrid, 'Text', 'Browse...', ...
    'ButtonPushedFcn', @(~,~) browseFile(app.afterEdit, {'*.tif;*.tiff;*.TIF;*.TIFF','TIFF files (*.tif, *.tiff)'}, 'Select after/exposed TIFF'));
uibutton(inputGrid, 'Text', 'Open Folder', ...
    'ButtonPushedFcn', @(~,~) openParentFolder(app.afterEdit.Value));

% Output folder
uilabel(inputGrid, 'Text', 'Output Folder:', 'FontWeight', 'bold');
app.outputFolderEdit = uieditfield(inputGrid, 'text', 'Value', pwd);
app.outputFolderEdit.Layout.Column = 2;
uibutton(inputGrid, 'Text', 'Browse...', ...
    'ButtonPushedFcn', @(~,~) browseFolder(app.outputFolderEdit, 'Select output folder'));
uibutton(inputGrid, 'Text', 'Open Folder', ...
    'ButtonPushedFcn', @(~,~) openFolder(app.outputFolderEdit.Value));

% Output prefix
prefixLabel = uilabel(inputGrid, 'Text', 'Output Prefix:', 'FontWeight', 'bold');
prefixLabel.Layout.Row = 5;
prefixLabel.Layout.Column = 1;

app.outputPrefixEdit = uieditfield(inputGrid, 'text', 'Value', 'triple_channel_registered');
app.outputPrefixEdit.Layout.Row = 5;
app.outputPrefixEdit.Layout.Column = [2 4];

% Prescan checkbox
app.usePrescanCheck = uicheckbox(inputGrid, ...
    'Text', 'Use before scan for prescan beta correction', ...
    'Value', true, ...
    'ValueChangedFcn', @(~,~) updatePrescanState());
app.usePrescanCheck.Layout.Row = 6;
app.usePrescanCheck.Layout.Column = [2 4];

% Quick instructions
infoText = uitextarea(inputGrid, 'Editable', 'off');
infoText.Layout.Row = [8 9];
infoText.Layout.Column = [1 4];
infoText.Value = { ...
    'Instructions:', ...
    '1. Select the calibration TXT file and the before/after TIFF scans.', ...
    '2. Choose an output folder and prefix.', ...
    '3. Go to Options if you want to change EV/WLS/OLS fitting or ROI settings.', ...
    '4. Click Run Reconstruction.'};
infoText.FontSize = 12;

%% Options tab
optGrid = uigridlayout(tabOptions, [10 4]);
optGrid.RowHeight = repmat({36}, 1, 10);
optGrid.ColumnWidth = {190, 150, 190, '1x'};
optGrid.Padding = [16 16 16 16];
optGrid.RowSpacing = 10;
optGrid.ColumnSpacing = 10;

% Calibration fit method
uilabel(optGrid, 'Text', 'Calibration Fit Method:', 'FontWeight', 'bold');
app.fitMethodDrop = uidropdown(optGrid, ...
    'Items', {'EV','WLS','OLS'}, ...
    'Value', 'EV');
app.fitMethodDrop.Tooltip = 'EV is recommended because it includes dose and pixel-value uncertainty.';

uilabel(optGrid, 'Text', 'Dose Uncertainty (%):', 'FontWeight', 'bold');
app.doseUncPercentEdit = uieditfield(optGrid, 'numeric', ...
    'Value', 1, ...
    'Limits', [0 Inf], ...
    'LowerLimitInclusive', 'on');
app.doseUncPercentEdit.Tooltip = 'Usually 1% is a reasonable starting point.';

uilabel(optGrid, 'Text', 'Min Dose Unc. (cGy):', 'FontWeight', 'bold');
app.doseUncMinEdit = uieditfield(optGrid, 'numeric', ...
    'Value', 1, ...
    'Limits', [0 Inf], ...
    'LowerLimitInclusive', 'on');

uilabel(optGrid, 'Text', 'DPI:', 'FontWeight', 'bold');
app.dpiEdit = uieditfield(optGrid, 'numeric', ...
    'Value', 300, ...
    'Limits', [1 Inf], ...
    'LowerLimitInclusive', 'on');

uilabel(optGrid, 'Text', 'ROI Height (mm):', 'FontWeight', 'bold');
app.roiHeightEdit = uieditfield(optGrid, 'numeric', ...
    'Value', 5, ...
    'Limits', [0 Inf], ...
    'LowerLimitInclusive', 'off');

uilabel(optGrid, 'Text', 'ROI Width (mm):', 'FontWeight', 'bold');
app.roiWidthEdit = uieditfield(optGrid, 'numeric', ...
    'Value', 5, ...
    'Limits', [0 Inf], ...
    'LowerLimitInclusive', 'off');

uilabel(optGrid, 'Text', 'Dose Region Threshold:', 'FontWeight', 'bold');
app.thresholdEdit = uieditfield(optGrid, 'numeric', ...
    'Value', 0.30, ...
    'Limits', [0.001 0.999]);

uilabel(optGrid, 'Text', 'Max Dose (cGy):', 'FontWeight', 'bold');
app.maxDoseEdit = uieditfield(optGrid, 'numeric', ...
    'Value', 0, ...
    'Limits', [0 Inf], ...
    'LowerLimitInclusive', 'on');
app.maxDoseEdit.Tooltip = 'Use 0 for automatic max dose, which uses 1.25 times the maximum calibration dose.';

app.applyFilmMaskCheck = uicheckbox(optGrid, ...
    'Text', 'Apply film mask outside common film area', ...
    'Value', true);
app.applyFilmMaskCheck.Layout.Column = [1 2];

app.showFiguresCheck = uicheckbox(optGrid, ...
    'Text', 'Show figures during reconstruction', ...
    'Value', true);
app.showFiguresCheck.Layout.Column = [3 4];

app.saveFiguresCheck = uicheckbox(optGrid, ...
    'Text', 'Save figures', ...
    'Value', true);
app.saveFiguresCheck.Layout.Column = [1 2];

app.registerPreviewCheck = uicheckbox(optGrid, ...
    'Text', 'Show/save registration preview', ...
    'Value', true);
app.registerPreviewCheck.Layout.Column = [3 4];

%% Advanced tab
advGrid = uigridlayout(tabAdvanced, [10 4]);
advGrid.RowHeight = repmat({36}, 1, 10);
advGrid.ColumnWidth = {220, 140, 220, '1x'};
advGrid.Padding = [16 16 16 16];
advGrid.RowSpacing = 10;
advGrid.ColumnSpacing = 10;

uilabel(advGrid, 'Text', 'Profile Edge Trim Fraction:', 'FontWeight', 'bold');
app.profileEdgeTrimEdit = uieditfield(advGrid, 'numeric', ...
    'Value', 0.08, ...
    'Limits', [0 0.45]);

uilabel(advGrid, 'Text', 'Profile High Percentile:', 'FontWeight', 'bold');
app.profileHighPrctileEdit = uieditfield(advGrid, 'numeric', ...
    'Value', 99, ...
    'Limits', [50 100]);

uilabel(advGrid, 'Text', 'Profile Median Window:', 'FontWeight', 'bold');
app.profileMedianWindowEdit = uieditfield(advGrid, 'numeric', ...
    'Value', 3, ...
    'Limits', [1 Inf], ...
    'RoundFractionalValues', 'on');

uilabel(advGrid, 'Text', 'Beta/Delta Clip Percentile:', 'FontWeight', 'bold');
app.betaDeltaPrctileEdit = uieditfield(advGrid, 'numeric', ...
    'Value', 99, ...
    'Limits', [50 100]);

uilabel(advGrid, 'Text', 'Beta/Delta Max Abs:', 'FontWeight', 'bold');
app.betaDeltaMaxAbsEdit = uieditfield(advGrid, 'numeric', ...
    'Value', 3000, ...
    'Limits', [0 Inf], ...
    'LowerLimitInclusive', 'off');

uilabel(advGrid, 'Text', 'Beta/Delta Min Abs:', 'FontWeight', 'bold');
app.betaDeltaMinAbsEdit = uieditfield(advGrid, 'numeric', ...
    'Value', 100, ...
    'Limits', [0 Inf]);

uilabel(advGrid, 'Text', 'Plot Border Margin Fraction:', 'FontWeight', 'bold');
app.plotBorderMarginEdit = uieditfield(advGrid, 'numeric', ...
    'Value', 0.015, ...
    'Limits', [0 0.5], ...
    'UpperLimitInclusive', 'off');

uilabel(advGrid, 'Text', 'Text Region [x1 x2 y1 y2]:', 'FontWeight', 'bold');
app.textRegionEdit = uieditfield(advGrid, 'text', ...
    'Value', '0.55 1.00 0.00 0.25');
app.textRegionEdit.Tooltip = 'Fractional region used for top/right handwriting or text registration.';

helpBox = uitextarea(advGrid, 'Editable', 'off');
helpBox.Layout.Row = [5 10];
helpBox.Layout.Column = [1 4];
helpBox.Value = { ...
    'Advanced notes:', ...
    '- Profile edge trim removes abnormal high edge regions from the center profiles.', ...
    '- Beta/Delta display clipping only affects visualization, not dose reconstruction.', ...
    '- TextRegion is [xStartFrac xEndFrac yStartFrac yEndFrac]. Default focuses on top-right handwriting/text.', ...
    '- PlotBorderMarginFrac controls how much symmetric margin is kept after white-border cropping.'};

%% Bottom status and controls
bottomPanel = uipanel(mainGrid, 'Title', 'Run Status');
bottomGrid = uigridlayout(bottomPanel, [2 4]);
bottomGrid.RowHeight = {42, '1x'};
bottomGrid.ColumnWidth = {150, 150, 150, '1x'};
bottomGrid.Padding = [12 10 12 10];
bottomGrid.RowSpacing = 8;

app.runButton = uibutton(bottomGrid, ...
    'Text', 'Run Reconstruction', ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @(~,~) runReconstruction());
app.runButton.Layout.Row = 1;
app.runButton.Layout.Column = 1;

app.openOutputButton = uibutton(bottomGrid, ...
    'Text', 'Open Output Folder', ...
    'ButtonPushedFcn', @(~,~) openFolder(app.outputFolderEdit.Value));
app.openOutputButton.Layout.Row = 1;
app.openOutputButton.Layout.Column = 2;

app.clearLogButton = uibutton(bottomGrid, ...
    'Text', 'Clear Log', ...
    'ButtonPushedFcn', @(~,~) clearLog());
app.clearLogButton.Layout.Row = 1;
app.clearLogButton.Layout.Column = 3;

app.statusLamp = uilamp(bottomGrid, 'Color', [0.5 0.5 0.5]);
app.statusLamp.Layout.Row = 1;
app.statusLamp.Layout.Column = 4;

app.logArea = uitextarea(bottomGrid, ...
    'Editable', 'off', ...
    'FontName', 'Consolas', ...
    'FontSize', 12);
app.logArea.Layout.Row = 2;
app.logArea.Layout.Column = [1 4];
app.logArea.Value = {'Ready.'};

% Store app in figure
app.fig.UserData = app;

updatePrescanState();

%% Nested callback functions

    function browseFile(editHandle, filterSpec, dialogTitle)
        [fileName, pathName] = uigetfile(filterSpec, dialogTitle);
        if isequal(fileName, 0)
            return;
        end
        editHandle.Value = fullfile(pathName, fileName);
    end

    function browseFolder(editHandle, dialogTitle)
        folderName = uigetdir(editHandle.Value, dialogTitle);
        if isequal(folderName, 0)
            return;
        end
        editHandle.Value = folderName;
    end

    function openFolder(folderName)
        if isempty(folderName) || ~isfolder(folderName)
            uialert(app.fig, 'Folder does not exist.', 'Open Folder Error');
            return;
        end
        if ispc
            winopen(folderName);
        elseif ismac
            system(sprintf('open "%s"', folderName));
        else
            system(sprintf('xdg-open "%s"', folderName));
        end
    end

    function openParentFolder(fileName)
        if isempty(fileName)
            uialert(app.fig, 'No file selected.', 'Open Folder Error');
            return;
        end
        folderName = fileparts(fileName);
        openFolder(folderName);
    end

    function updatePrescanState()
        if app.usePrescanCheck.Value
            app.beforeEdit.Enable = 'on';
        else
            app.beforeEdit.Enable = 'off';
        end
    end

    function clearLog()
        app.logArea.Value = {'Ready.'};
        app.statusLamp.Color = [0.5 0.5 0.5];
    end

    function appendLog(msg)
        oldValue = app.logArea.Value;
        if ischar(oldValue)
            oldValue = {oldValue};
        end
        timeStamp = datestr(now, 'HH:MM:SS');
        newLine = sprintf('[%s] %s', timeStamp, msg);
        app.logArea.Value = [oldValue; {newLine}];
        drawnow;
    end

    function tf = validateInputs()
        tf = false;

        if isempty(app.calibrationEdit.Value) || ~isfile(app.calibrationEdit.Value)
            uialert(app.fig, 'Please select a valid calibration TXT file.', 'Missing Input');
            return;
        end

        if app.usePrescanCheck.Value
            if isempty(app.beforeEdit.Value) || ~isfile(app.beforeEdit.Value)
                uialert(app.fig, 'Please select a valid before/unexposed TIFF file.', 'Missing Input');
                return;
            end
        end

        if isempty(app.afterEdit.Value) || ~isfile(app.afterEdit.Value)
            uialert(app.fig, 'Please select a valid after/exposed TIFF file.', 'Missing Input');
            return;
        end

        if isempty(app.outputFolderEdit.Value)
            uialert(app.fig, 'Please select an output folder.', 'Missing Input');
            return;
        end

        if ~isfolder(app.outputFolderEdit.Value)
            mkdir(app.outputFolderEdit.Value);
        end

        if isempty(strtrim(app.outputPrefixEdit.Value))
            uialert(app.fig, 'Please enter a valid output prefix.', 'Missing Input');
            return;
        end

        try
            parseTextRegion(app.textRegionEdit.Value);
        catch ME
            uialert(app.fig, ME.message, 'Invalid Text Region');
            return;
        end

        tf = true;
    end

    function textRegion = parseTextRegion(txt)
        textRegion = str2num(txt); %#ok<ST2NM>
        if isempty(textRegion) || numel(textRegion) ~= 4 || any(~isfinite(textRegion))
            error('TextRegion must contain four finite numbers, for example: 0.55 1.00 0.00 0.25');
        end
        textRegion = double(textRegion(:).');
        if any(textRegion < 0) || any(textRegion > 1)
            error('TextRegion values must be between 0 and 1.');
        end
        if textRegion(2) <= textRegion(1) || textRegion(4) <= textRegion(3)
            error('TextRegion must satisfy x2 > x1 and y2 > y1.');
        end
    end

    function runReconstruction()
        if ~validateInputs()
            return;
        end

        app.runButton.Enable = 'off';
        app.statusLamp.Color = [1.0 0.75 0.1];
        appendLog('Starting reconstruction...');

        try
            calibrationTxt = app.calibrationEdit.Value;
            beforeTif = app.beforeEdit.Value;
            afterTif = app.afterEdit.Value;
            outputFolder = app.outputFolderEdit.Value;
            outputPrefix = app.outputPrefixEdit.Value;

            maxDoseValue = app.maxDoseEdit.Value;
            if isempty(maxDoseValue) || ~isfinite(maxDoseValue) || maxDoseValue <= 0
                maxDoseArg = [];
            else
                maxDoseArg = maxDoseValue;
            end

            roiSizeMm = [app.roiHeightEdit.Value, app.roiWidthEdit.Value];
            textRegion = parseTextRegion(app.textRegionEdit.Value);

            appendLog(sprintf('Calibration file: %s', calibrationTxt));
            appendLog(sprintf('After file: %s', afterTif));
            appendLog(sprintf('Output folder: %s', outputFolder));
            appendLog(sprintf('Calibration fit method: %s', app.fitMethodDrop.Value));

            if app.usePrescanCheck.Value
                appendLog(sprintf('Before file: %s', beforeTif));

                out = reconstructDoseTripleChannelRegistered( ...
                    calibrationTxt, ...
                    beforeTif, ...
                    afterTif, ...
                    'OutputFolder', outputFolder, ...
                    'OutputPrefix', outputPrefix, ...
                    'ShowFigures', app.showFiguresCheck.Value, ...
                    'SaveFigures', app.saveFiguresCheck.Value, ...
                    'MaxDose', maxDoseArg, ...
                    'DPI', app.dpiEdit.Value, ...
                    'ROISize_mm', roiSizeMm, ...
                    'DoseRegionThresholdRatio', app.thresholdEdit.Value, ...
                    'ApplyFilmMask', app.applyFilmMaskCheck.Value, ...
                    'RegisterPreview', app.registerPreviewCheck.Value, ...
                    'TextRegion', textRegion, ...
                    'ProfileEdgeTrimFrac', app.profileEdgeTrimEdit.Value, ...
                    'ProfileHighPrctile', app.profileHighPrctileEdit.Value, ...
                    'ProfileMedianWindow', app.profileMedianWindowEdit.Value, ...
                    'UsePrescanBeta', true, ...
                    'CalibrationFitMethod', app.fitMethodDrop.Value, ...
                    'DoseUncertaintyPercent', app.doseUncPercentEdit.Value, ...
                    'DoseUncertaintyMin_cGy', app.doseUncMinEdit.Value, ...
                    'BetaDeltaDynamicPrctile', app.betaDeltaPrctileEdit.Value, ...
                    'BetaDeltaDynamicMaxAbs', app.betaDeltaMaxAbsEdit.Value, ...
                    'BetaDeltaDynamicMinAbs', app.betaDeltaMinAbsEdit.Value, ...
                    'PlotBorderMarginFrac', app.plotBorderMarginEdit.Value);
            else
                appendLog('Prescan beta correction disabled. beforeTif will not be used.');

                out = reconstructDoseTripleChannelRegistered( ...
                    calibrationTxt, ...
                    afterTif, ...
                    'OutputFolder', outputFolder, ...
                    'OutputPrefix', outputPrefix, ...
                    'ShowFigures', app.showFiguresCheck.Value, ...
                    'SaveFigures', app.saveFiguresCheck.Value, ...
                    'MaxDose', maxDoseArg, ...
                    'DPI', app.dpiEdit.Value, ...
                    'ROISize_mm', roiSizeMm, ...
                    'DoseRegionThresholdRatio', app.thresholdEdit.Value, ...
                    'ApplyFilmMask', app.applyFilmMaskCheck.Value, ...
                    'RegisterPreview', app.registerPreviewCheck.Value, ...
                    'TextRegion', textRegion, ...
                    'ProfileEdgeTrimFrac', app.profileEdgeTrimEdit.Value, ...
                    'ProfileHighPrctile', app.profileHighPrctileEdit.Value, ...
                    'ProfileMedianWindow', app.profileMedianWindowEdit.Value, ...
                    'UsePrescanBeta', false, ...
                    'CalibrationFitMethod', app.fitMethodDrop.Value, ...
                    'DoseUncertaintyPercent', app.doseUncPercentEdit.Value, ...
                    'DoseUncertaintyMin_cGy', app.doseUncMinEdit.Value, ...
                    'BetaDeltaDynamicPrctile', app.betaDeltaPrctileEdit.Value, ...
                    'BetaDeltaDynamicMaxAbs', app.betaDeltaMaxAbsEdit.Value, ...
                    'BetaDeltaDynamicMinAbs', app.betaDeltaMinAbsEdit.Value, ...
                    'PlotBorderMarginFrac', app.plotBorderMarginEdit.Value);
            end

            app.fig.UserData.lastOutput = out;

            appendLog('Reconstruction finished successfully.');

            if isfield(out, 'centerDoseROI') && isfield(out.centerDoseROI, 'meanDose_cGy')
                appendLog(sprintf('Center ROI mean dose: %.4f cGy', out.centerDoseROI.meanDose_cGy));
            end

            if isfield(out, 'solverInfo')
                appendLog(sprintf('Solver converged: %d', out.solverInfo.converged));
                if isfield(out.solverInfo, 'numIterations')
                    appendLog(sprintf('Solver iterations: %d', out.solverInfo.numIterations));
                end
            end

            if isfield(out, 'calibrationFitMethod')
                appendLog(sprintf('Actual calibration fit method: %s', out.calibrationFitMethod));
            end

            appendLog('Saved outputs are available in the output folder.');
            app.statusLamp.Color = [0.2 0.8 0.2];

        catch ME
            app.statusLamp.Color = [0.9 0.1 0.1];
            appendLog('ERROR: reconstruction failed.');
            appendLog(ME.message);

            if ~isempty(ME.stack)
                appendLog(sprintf('Error location: %s, line %d', ME.stack(1).name, ME.stack(1).line));
            end

            uialert(app.fig, ME.message, 'Reconstruction Error');
        end

        app.runButton.Enable = 'on';
    end

end
