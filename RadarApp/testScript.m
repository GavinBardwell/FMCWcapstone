
% Script to Run FMCWRadarSimulation
clear;
addpath('Backend');
addpath('Config_Files')
%addpath('Config_Files');
% Create an instance of FMCWRadarSimulation
radarSim = FMCWSim('default.mat');

% Load configuration file
%radarSim.loadConfig('default.mat');

% Simulate the environment
Nsweep = 64;
xr = radarSim.simulate(Nsweep);

% Plot the waveform
%radarSim.plotWaveform(radarSim.tx_waveform());

% Plot the signal spectrum
%radarSim.plotSignalSpectrum(radarSim.tx_waveform());

% Plot the range-Doppler response

radarSim.plotRangeDoppler(xr);

radarSim.plotRangeVsPower();

radarSim.plotVelocityVsPower();

radarSim.openSpectrumAnalyzer();

%radarSim.createRangeVsPowerrVideo(xr);