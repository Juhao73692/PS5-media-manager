# PS5-media-manager

(Note: This README is currently a Work In Progress. Sections below are yet to be completed.)

---

## ⚖️ License & Legal Compliance

### Project License

This project is licensed under the **GNU Lesser General Public License v2.1 (LGPLv2.1)**.

See the [LICENSE](LICENSE) file in the root directory for the full license text.

> **Important for Contributors:** All new source files must include the LGPLv2.1 copyright header.

### FFmpeg Usage & Compliance

This project statically links to the **FFmpeg** multimedia framework (Version: `release/8.0`).

To comply with the LGPLv2.1 requirements regarding static linking, we provide the following:

1. **Re-linkability**: This project is open-source. Any user can modify the FFmpeg source code, use our provided build scripts to compile new static libraries (`.a`), and re-link them with this project's object files or source code.
2. **Build Scripts**: The exact configuration and compilation steps used for FFmpeg are provided in the `/FFmpeg` directory.
3. **LGPL Build Flags**: Our FFmpeg build is configured with `--disable-gpl` and `--disable-nonfree` to ensure it remains strictly under LGPL and is suitable for distribution (including via the macOS App Store).
4. **Hardware Acceleration**: We utilize the `Apple VideoToolbox` framework via FFmpeg for hardware-accelerated decoding/encoding, ensuring optimal performance on macOS.

For more details on how to build FFmpeg for this project, see [FFmpeg/README.md](FFmpeg/README.md).

---

## [WIP] Introduction

## [WIP] Features

## [WIP] Requirements

## [WIP] Installation & Usage

---

## Acknowledgments

- **FFmpeg**: This project uses the FFmpeg multimedia framework (<http://ffmpeg.org>).
