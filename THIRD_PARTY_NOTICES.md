# Third-party software

PhoneConnect bundles, unmodified, the official release builds of:

| Software | What it does here | License |
|---|---|---|
| [scrcpy](https://github.com/Genymobile/scrcpy) by Genymobile and Romain Vimont | Mirrors and controls the phone | Apache License 2.0 |
| adb (Android SDK Platform-Tools), as included in the scrcpy release | Talks to the phone over USB or the network | Apache License 2.0 |
| Windows builds only: FFmpeg, SDL, libusb, as included in the scrcpy release | Video decoding, window, USB access | FFmpeg and libusb: LGPL 2.1+; SDL: zlib License |
| Windows builds only, in `shell\`: from [MSYS2](https://www.msys2.org): its runtime (based on Cygwin), zsh, GNU coreutils, grep, sed and gawk, libxml2 (`xmllint`), and the libraries they need: ncurses, readline, PCRE, PCRE2, libiconv, libintl (gettext), GMP, MPFR, zlib, GCC runtime libraries | The shell PhoneConnect's script runs on, and the tools it uses | MSYS2 runtime: LGPL 3+; zsh: zsh license (MIT-style); coreutils, grep, sed, gawk, readline: GPL 3+; GMP, MPFR, libiconv, libintl: LGPL 3+ / LGPL 2.1+; GCC runtime: GPL 3+ with the GCC Runtime Library Exception; libxml2, ncurses: MIT; PCRE, PCRE2: BSD; zlib: zlib License |

The scrcpy license text is included next to the bundled tools
(`scrcpy-LICENSE.txt`). License files that MSYS2 packages ship are in
`shell\usr\share\licenses`; the GNU GPL and LGPL texts are at https://www.gnu.org/licenses/. Source code for all of the above is available from the
linked projects and from the scrcpy release they come from. The MSYS2 packages are
the unmodified builds named in `build/versions.env`; their exact sources are at
https://repo.msys2.org/msys/sources/ and https://github.com/msys2/MSYS2-packages.
