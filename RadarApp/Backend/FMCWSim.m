classdef FMCWSim < handle
    properties
        % Config file
        config
        % Radar and Environment
        radar
        environment
        % Analysis tools
        specanalyzer
        total_received_sig
        %sim results
        dechirpsig
        fftResponse
    end

    methods
        function obj = FMCWSim(config_file)
            if nargin < 1
                config_file = 'radar_config.mat';
            end
            obj.config = obj.loadConfig(config_file);
            obj = obj.initialize();
        end

        function config = loadConfig(obj, config_file)
            % Load configuration from file
            config = load(config_file);
        end

        function obj = initialize(obj)
            % Initialize radar, environment, and spectrum analyzer
            obj = obj.initializeRadar();
            obj = obj.initializeEnvironment();
            obj = obj.initializeSpectrumAnalyzer();
        end

        function obj = initializeRadar(obj)
            % Initialize the primary radar
            obj.radar = Radar(obj.config.primary);
        end

        function obj = initializeEnvironment(obj)
            % Initialize the environment with benign and emission objects
            %FIXME RANGE_RES B/T RADAR AND EMISSION'S MUST EQUAL
            obj.environment = Environment();
            obj.environment = obj.environment.loadEnvironment(obj.config);
        end

        function obj = initializeSpectrumAnalyzer(obj)
            % Initialize Spectrum Analyzer for visualization
            obj.specanalyzer = dsp.SpectrumAnalyzer('SampleRate', obj.radar.fs, 'Method', 'welch', 'AveragingMethod', 'running', ...
                'PlotAsTwoSidedSpectrum', true, 'FrequencyResolutionMethod', 'rbw', 'Title', ...
                'Spectrum for received and dechirped signal', 'ShowLegend', true);
        end

        function clutter = createGround(obj)
            % Define clutter with radar and environment parameters
            height = abs(obj.radar.radar_position(3) + obj.environment.floor);
            clutter = phased.ConstantGammaClutter( ...
                'PropagationSpeed', obj.radar.c, ...
                'OperatingFrequency', obj.radar.fc, ...
                'SampleRate', obj.radar.fs, ...
                'PRF', 1 / obj.radar.t_max, ...           % Pulse Repetition Frequency
                'Gamma', -60, ...                         % Terrain reflectivity (adjust as needed)
                'ClutterMinRange', 0, ...                 % Minimum range for clutter
                'ClutterMaxRange', obj.radar.range_max, ... % Maximum range based on radar range
                'ClutterAzimuthCenter', 0, ...            % Center azimuth of clutter (degrees)
                'ClutterAzimuthSpan', 180, ...            % Azimuth span of clutter (degrees)
                'PlatformHeight', height, ... % Radar height + floor level
                'PlatformSpeed', norm(obj.radar.radar_velocity)); % Radar platform speed
        end


        function xr = simulate(obj, Nsweep)
            if nargin < 2
                Nsweep = 64;
            end
        
            obj.environment.setTargets(obj.radar.fc);
            waveform_samples = round(obj.radar.fs * obj.radar.t_max);
            xr = complex(zeros(waveform_samples, Nsweep));

            if not(isnan(obj.environment.floor))
                clutter = obj.createGround();
            else
                clutter = []; % No clutter if floor is undefined
            end
            
            benign_channel = phased.FreeSpace('PropagationSpeed', obj.radar.c, ...
                'OperatingFrequency', obj.radar.fc, 'SampleRate', obj.radar.fs, ...
                'TwoWayPropagation', true);
            emission_channel = phased.FreeSpace('PropagationSpeed', obj.radar.c, ...
                'OperatingFrequency', obj.radar.fc, 'SampleRate', obj.radar.fs, ...
                'TwoWayPropagation', false);
            
            radar_motion = phased.Platform('InitialPosition', obj.radar.radar_position, 'Velocity', obj.radar.radar_velocity);
            benign_motions = cell(1, length(obj.environment.benign_objects));
            for i = 1:length(obj.environment.benign_objects)
                benign_motions{i} = phased.Platform('InitialPosition', obj.environment.benign_objects(i).position, 'Velocity', obj.environment.benign_objects(i).velocity);
            end
            emission_motions = cell(1, length(obj.environment.emission_objects));
            emission_offsets = zeros(1, length(emission_motions));
            for i = 1:length(obj.environment.emission_objects)
                emission_motions{i} = phased.Platform('InitialPosition', obj.environment.emission_objects(i).position, 'Velocity', obj.environment.emission_objects(i).velocity);
            end
            
            for m = 1:Nsweep
                [radar_pos, radar_vel] = radar_motion(obj.radar.t_max);
                for i = 1:length(benign_motions)
                    [obj.environment.benign_objects(i).position, obj.environment.benign_objects(i).velocity] = benign_motions{i}(obj.radar.t_max);
                end
        
                sig = obj.radar.tx_waveform();
                txsig = obj.radar.transmitter(sig);
                obj.total_received_sig = complex(zeros(size(txsig)));
                
                for i = 1:length(obj.environment.benign_objects)
                    reflected_sig = benign_channel(txsig, radar_pos, obj.environment.benign_objects(i).position, radar_vel, obj.environment.benign_objects(i).velocity);
                    reflected_sig = obj.environment.benign_objects(i).target(reflected_sig);
                    obj.total_received_sig = obj.total_received_sig + reflected_sig;
                end
        
                for i = 1:length(emission_motions)
                    %do the actual simulartion portion of it
                    [emission_pos, emission_vel] = emission_motions{i}(obj.radar.t_max);
                    emission_sig = obj.environment.emission_objects(i).waveform();
                    emission_txsig = obj.environment.emission_objects(i).transmitter(emission_sig);
                    emission_received_sig = emission_channel(emission_txsig, emission_pos, radar_pos, emission_vel, radar_vel);
                    
                    %resize the array and offset it to make it loop
                    %properly
                    current_offset = emission_offsets(i);
                    emission_received_sig = resize(emission_received_sig, size(obj.total_received_sig, 1) + current_offset, Pattern="circular");
                    
                    % Cut down the signal to the required size after resizing
                    emission_received_sig = emission_received_sig(current_offset + 1 : current_offset + size(obj.total_received_sig, 1));

                    % Update offset for the next loop
                    emission_offsets(i) = mod(current_offset + size(txsig, 1), size(emission_sig, 1));

                    obj.total_received_sig = obj.total_received_sig + emission_received_sig;
                end
                                % Create clutter
                if ~isempty(clutter)
                    clutter_returns = sum(clutter(), 2); % Sum across channels if necessary
                    obj.total_received_sig = obj.total_received_sig + clutter_returns;
                end
                obj.total_received_sig = obj.radar.receiver(obj.total_received_sig);
                obj.dechirpsig = dechirp(obj.total_received_sig, sig);
                %obj.specanalyzer([obj.total_received_sig, obj.dechirpsig]);
                xr(:, m) = obj.dechirpsig;
            end
        end



        function plotRangeDoppler(obj, xr, targetGraph)
            % Check if targetGraph is provided; if not, set it to empty
            if nargin < 3 || isempty(targetGraph)
                targetGraph = [];
            end
            numRows= size(xr, 1);
            tWin = taylorwin(numRows,5, -35);
            % Create a phased.RangeDopplerResponse object with given parameters
            rngdopresp = phased.RangeDopplerResponse('PropagationSpeed', obj.radar.c, ...
                'DopplerOutput', 'Speed', 'OperatingFrequency', obj.radar.fc, ...
                'SampleRate', obj.radar.fs, 'RangeMethod', 'FFT', 'SweepSlope', obj.radar.sweep_slope, ...
                'RangeFFTLengthSource', 'Property', 'RangeFFTLength', 2048, ...
                'DopplerFFTLengthSource', 'Property', 'DopplerFFTLength', 256);
            
            % Calculate the response data using the object and signal xr
            xr_window = xr .* tWin;
            [resp, rng_grid, dop_grid] = rngdopresp(xr_window);
            
            obj.fftResponse.resp = resp;
            obj.fftResponse.rng_grid = rng_grid;
            obj.fftResponse.dop_grid = dop_grid;
            % If targetGraph is empty, create a new figure and UIAxes for the plot
            if isempty(targetGraph)
                figureHandle = figure('Name', 'Range-Doppler Response', 'NumberTitle', 'off');
                targetGraph = uiaxes('Parent', figureHandle);
            end
        
            % Plot the response on the provided UIAxis (targetGraph)
            surf(targetGraph, dop_grid, rng_grid, mag2db(abs(resp)), 'EdgeColor', 'none');
            view(targetGraph, 0, 90); % Set the view to a 2D view
            xlabel(targetGraph, 'Doppler (m/s)');
            ylabel(targetGraph, 'Range (m)');
            title(targetGraph, 'Range-Doppler Response');
            axis(targetGraph, [-obj.radar.v_max, obj.radar.v_max, 0, obj.radar.range_max]);
            colorbar(targetGraph);
        end



        function openSpectrumAnalyzer(obj)
            % Open the spectrum analyzer
            obj.specanalyzer([obj.total_received_sig, obj.dechirpsig]);
        end

        function plotRadarWaveform(obj, signal)
            % Plot the radar waveform
            figure;
            t = (0:1/obj.radar.fs:obj.radar.t_max-1/obj.radar.fs);
            plot(t, real(signal));
            title('Radar FMCW Signal Waveform');
            xlabel('Time (s)');
            ylabel('Amplitude (v)');
            axis tight;
        end

function plotRangeVsPower(obj, targetAxis)
    % Calculate the range-power data
    % Integrate power over all Doppler bins
    power_vs_range = sum(abs(obj.fftResponse.resp), 2); % Sum over the Doppler dimension
    
    % Convert power to decibels (optional)
    power_vs_range_db = 10 * log10(power_vs_range);

    % Plot in the provided UIAxes if available, otherwise create a new figure
    if nargin > 1 && ~isempty(targetAxis)
        % Plot in the specified UIAxes
        plot(targetAxis, obj.fftResponse.rng_grid, power_vs_range_db);
        xlabel(targetAxis, 'Range (m)');
        ylabel(targetAxis, 'Power (dB)');
        title(targetAxis, 'Range vs Power');
        grid(targetAxis, 'on');
    else
        % Plot in a new figure window
        figure;
        plot(obj.fftResponse.rng_grid, power_vs_range_db);
        xlabel('Range (m)');
        ylabel('Power (dB)');
        title('Range vs. Power');
        grid on;
    end
end

function plotVelocityVsPower(obj, targetAxis)
    power_vs_doppler = sum(abs(obj.fftResponse.resp), 1);%sum over range dimension

    % Convert power to decibels 
    power_vs_doppler_db = 10 * log10(power_vs_doppler);
    % Plot in the provided UIAxes if available, otherwise create a new figure
    if nargin > 1 && ~isempty(targetAxis)
        % Plot in the specified UIAxes
        plot(targetAxis, obj.fftResponse.dop_grid, power_vs_doppler_db);
        xlabel(targetAxis, 'Velocity (m/s)');
        ylabel(targetAxis, 'Power (dB)');
        title(targetAxis, 'Velocity vs Power');
        grid(targetAxis, 'on');
    else
        % Plot in a new figure window
        figure;
        plot(obj.fftResponse.dop_grid, power_vs_doppler_db);
        xlabel('Velocity (m/s)');
        ylabel('Power (dB)');
        title('Velocity vs Power');
        grid on;
    end
end


    function createRangeVsPowerrVideo(obj, xr)
        [numFrames, numPoints] = size(xr);
        
        % Create a figure window
        figure;
        
        % Loop through each frame
        for k = 1:numFrames
            % Plot the current waveform
            plot(xr(k, :));
            title(['Frame ' num2str(k)]);
            xlabel('Sample Points');
            ylabel('Amplitude');
            ylim([-1 1]); % Adjust based on your data range
        
            % Pause to control the frame rate
            pause(0.1); % Pause for 0.1 seconds (adjust as needed)
        
            % Optionally, capture the frame for creating a video or GIF
             frame = getframe(gcf);
             writeVideo(videoObject, frame); % If using VideoWriter
        end
            end
            function saveInfo(obj, filename)
                    % Save radar and environment info to a file
                    info.radar = obj.radar.saveRadar();
                    info.environment = obj.environment.saveEnvironment();
                    save(filename, '-struct', 'info');
                end
        
                function saveRangeVsPower(obj, filename, data)
                    % Save Range vs Power data to a file
                    save(filename, 'data');
                end
        
                function saveVelocityVsPower(obj, filename, data)
                    % Save Velocity vs Power data to a file
                    save(filename, 'data');
                end
            end
end
