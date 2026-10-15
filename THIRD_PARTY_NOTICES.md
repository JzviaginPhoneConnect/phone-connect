# Third-party software

PhoneConnect bundles, unmodified, the official release builds of:

| Software | What it does here | License |
|---|---|---|
| [scrcpy](https://github.com/Genymobile/scrcpy) by Genymobile and Romain Vimont | Mirrors and controls the phone | Apache License 2.0 |
| adb (Android SDK Platform-Tools), as included in the scrcpy release | Talks to the phone over USB or the network | Apache License 2.0 |
| Windows builds only: FFmpeg, SDL, libusb, as included in the scrcpy release | Video decoding, window, USB access | FFmpeg and libusb: LGPL 2.1+; SDL: zlib License |

The scrcpy license text is included next to the bundled tools
(`scrcpy-LICENSE.txt`). Source code for all of the above is available from the
linked projects and from the scrcpy release they come from.
