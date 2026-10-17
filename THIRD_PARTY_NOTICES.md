# Third-party software

PhoneConnect (MIT License) bundles the following software, unmodified, from its
official release builds. The full license texts are in the `licenses` folder that
ships with the app (`licenses/README.md` says which text covers what).

**Source code** of all of it, the exact versions in this release, is published at
https://github.com/JzviaginPhoneConnect/phone-connect/releases/tag/third-party-sources-1
and is also available from the projects linked below.

## In both the Mac and the Windows app

| Software | Version | What it does here | License |
|---|---|---|---|
| [scrcpy](https://github.com/Genymobile/scrcpy) by Genymobile and Romain Vimont | 5.0.1 | Mirrors and controls the phone | Apache 2.0 |
| adb, from [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools), as included in the scrcpy release | 37.0.1 | Talks to the phone over USB or the network | Apache 2.0; its notice lists further components (`licenses/adb-NOTICE.txt`) |
| [FFmpeg](https://ffmpeg.org) (built into scrcpy; separate DLLs on Windows) | 9.0.2 | Video and audio decoding | LGPL 2.1 or later |
| [SDL](https://libsdl.org) (built into scrcpy; `SDL3.dll` on Windows) | 3.4.18 | Window, input, sound | zlib |
| [libusb](https://libusb.info) (built into scrcpy; `libusb-1.0.dll` on Windows) | 1.0.30 | USB access | LGPL 2.1 or later |

On macOS, FFmpeg, SDL and libusb are linked into the scrcpy program. Their complete
source, and scrcpy's with its build scripts (`app/deps/` in the scrcpy source), are in
the source release above, so you can rebuild scrcpy with modified versions of them.

## Windows app only: the shell PhoneConnect runs on (`shell\`)

Unmodified packages from [MSYS2](https://www.msys2.org) (versions in `build/versions.env`
of this project):

| Software | License |
|---|---|
| MSYS2 runtime (based on Cygwin) | LGPL 3 or later |
| zsh | zsh license (MIT-style) |
| GNU coreutils, grep, sed, gawk, readline | GPL 3 or later |
| GMP, MPFR | LGPL 3 or later |
| libiconv, libintl (gettext) | LGPL 2.1 or later |
| GCC runtime libraries | GPL 3 with the GCC Runtime Library Exception |
| libxml2 (`xmllint`), ncurses | MIT-style |
| PCRE, PCRE2 | BSD |
| zlib | zlib |

License files that these packages include are also in `shell\usr\share\licenses`.
Their source packages (upstream source plus MSYS2's build recipe and patches) are in
the source release above, and at https://repo.msys2.org/msys/sources/.

## Trademarks

Android is a trademark of Google LLC; Samsung and DeX are trademarks of Samsung
Electronics. PhoneConnect is an independent project, not affiliated with or endorsed
by Google, Samsung or Genymobile.
