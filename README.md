# Jetson TX2 Lane Detection
Lane detection for the Nvidia Jetson TX2 using OpenCV4Tegra

## Table of Contents

1. [Dependencies](#dependencies)
2. [Usage](#usage)
3. [Configurations](#configurations)

## Dependencies
Requires a Jetson TX2 running L4T 28.1 (JetPack 3.1)

Use install_depend.sh to install the following dependencies:
* GNU Scientific Library (libgsl-dev): used for polynomial curve fitting

## Usage
#### Run all scripts from lane_detection directory
```bash
	./build.sh 		#builds all files
	./build.sh clean 	#removes all files generated by build.sh
```

```bash
	./install_depend.sh	#installs all dependencies
```

```bash
	bin/detect.cu	#runs executable using config.txt configurations
```

## Configurations
#### Modify config.txt to change configuration settings
* video_file: path to video file from execution directory
* lane_degree: degree of polynomial that defines lanes
* lane_filter: filter for curve to remove jitter lane
* lane_start_threshold: pixel threshold for searching for lane
* left_lane_start: percentage of width of frame to start looking for left lane
* right_lane_start: percentage of width of frame to start looking for right lane
* row_step: stride for stepping through rows
* col_step: stride for stepping through columns
