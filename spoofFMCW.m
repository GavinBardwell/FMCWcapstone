%uses theories and practices discussed in this paper https://dl.acm.org/doi/pdf/10.1145/3474376.3487283
%CURRENTLY DOES NOT MANIPULATE VELOCITY JUST DISTANCE

function slope = calculate_slope(fmcw_waveform, sampling_frequency)
    % Find the frequency range of the FMCW waveform
    f_start = min(fmcw_waveform);
    f_end = max(fmcw_waveform);
    
    % Calculate slope (rate of change of frequency)
    duration = length(fmcw_waveform) / sampling_frequency; % Duration of the waveform in seconds
    slope = (f_end - f_start) / duration; % Slope in Hz/s
end

function beat_frequency = calculate_beat_frequency(received_signal, sampling_frequency)
    % Perform FFT to get frequency domain representation of the signal
    fft_signal = fft(received_signal);

    % Frequency axis
    f_axis = linspace(-sampling_frequency/2, sampling_frequency/2, length(received_signal));

    % Find the peak frequency (beat frequency)
    [~, max_index] = max(abs(fft_signal));
    beat_frequency = f_axis(max_index);
end

function outputWaveform = spoofingFMCW(inputWaveform,distanceChange, velocityChange)
    %spoofingFMCW is the function that will spoof fmcw radar intput of
    %(inputWave following what is the distanceChange, and change of velocity
    c=3e8;
    
    %find beat frequency
    beat_frequency = calculate_beat_frequency(inputWaveform, 1e6);
    
    %traditional equation is d  = c*fb/2S(from victims POV)
    %since we are calculating distance from the attackers point of view we must
    %multiply by 2. Fb = St, t = 2d/c(time it takes to go there and back)
    %d = Fb * c/ S
    inputWaveSlope = calculate_slope(inputWaveform, 1e6);
    currentDistance = c * beat_frequency / inputWaveSlope;
    addedTime = 2 * distanceChange / c;
    
    % Calculate the number of samples to shift
    num_samples_to_shift = round(addedTime * 1e6);%sampling frequency
    
    % Create a zero-padded waveform for shifting
    zero_padded_waveform = [zeros(1, num_samples_to_shift), inputWaveform];
    
    % Shift the waveform
    outputWaveform = zero_padded_waveform(1:length(inputWaveform));

end
