# FFmpeg Static Build for macOS

This directory contains the pre-compiled static libraries, headers, and build configurations for FFmpeg used in this project.

## 1. LGPL Compliance Notice

This project uses FFmpeg under the **LGPL v2.1** (Lesser General Public License). To comply with the requirements for static linking:

* **Source Availability**: The source code for the version of FFmpeg used here can be found at [ffmpeg.org](https://ffmpeg.org/download.html).
* **Re-linkability**: As this is an open-source project, we provide the full build environment. Users can modify the FFmpeg source, run the provided `build.sh` script to generate new `.a` libraries, and re-link the application using the project's source code.
* **No GPL/Non-Free Code**: This build is configured with `--disable-gpl` and `--disable-nonfree` to ensure compatibility with LGPL distribution and App Store guidelines.

## 2. Technical Details

* **Architecture**: `arm64`
* **Format**: Static Libraries (`.a`)
* **Target OS**: macOS (minimum version as specified in project settings)
* **Hardware Acceleration**: Enabled via `--enable-videotoolbox` for optimal performance and power efficiency on Mac hardware.

## 3. Directory Structure

```text
FFmpeg/
├── build.sh            # Automation script to download and compile FFmpeg
├── README.md           # This file
├── include/            # C header files for development
└── lib/                # Pre-compiled .a files (Universal Binaries)
```

## 4. How to Reproduce this Build

To manually rebuild the libraries (e.g., to change modules or update versions), follow these steps:

* **Install Build Dependencies**:

```shell
brew install nasm pkg-config
```

* **Copy this `build.sh` to FFmpeg code folder**
* **Run the Build Script**:

```shell
chmod +x build.sh
./build.sh
```

* **Then you can find the build outputs under the `build/` folder**

* **Copy the Static Libraries to `FFmpeg/lib/`**
* **Copy the headers to `FFmpeg/include/`**

## 5. Acknowledgments

This software uses code of FFmpeg licensed under the LGPLv2.1 and its source can be downloaded from the FFmpeg website.
