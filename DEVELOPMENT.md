# Developing PhoneConnect

Everything about building, testing and releasing the app. For using it, see the [README](README.md).

## Repository layout

```
app/PhoneConnect.sh          the app: one zsh script, the same on Mac and Windows
platform/macos/, windows/    everything that differs per OS (dialogs, paths, starting scrcpy...),
                             same script names on both; packaged next to the app script
macos/StatusWindow.swift     the Mac status window (what's happening while it connects)
windows/Launcher.cs          PhoneConnect.exe: starts the script with the bundled zsh, icon, no console;
                             with --status it's the Windows status window
tests/                       logic tests with a fake adb and scrcpy (run on both OSes in CI)
windows/installer.iss        Inno Setup script for PhoneConnect-Setup.exe
assets/                      icon (PNG, .icns, .ico), installer background, screenshots, social preview
licenses/                    license texts shipped with the app (see THIRD_PARTY_NOTICES.md)
VERSION                      the first version, used until the first release tag exists
build/next-version.sh        works out the next version (x.y.z) from the tags
build/release-wanted.sh      decides whether a change on main is released or only built
build/versions.env           pinned scrcpy, MSYS2 packages (the Windows shell), their sources, and checksums
build/collect-sources.sh     collects the third-party sources for the sources release
build/build-macos.sh         builds the Mac release files, or a developer build with --dev
build/dmg-settings.py        layout of the .dmg installer window
build/build-windows.ps1      builds the Windows release files, or a developer build with -Dev
.github/workflows/build.yml  builds every pull request; on main, tags and releases each version
.github/workflows/version-preview.yml  comments on each pull request which version it will release
.github/pull_request_template.md       the pull request form, with the release and version boxes
.github/rulesets/main.json   rule that blocks merging into main unless both builds pass
.github/FUNDING.yml          the Sponsor button (PayPal)
```

## Building

The builds download the official scrcpy release (which includes adb) and check it against the pinned checksums. Everything ends up in `dist/`.

### Developer builds (to test a change)

These build only the app, with no installer, `.dmg` or zip, so they're quick to make and run straight from the folder. The version shows it's a developer build, for example **1.0.4-dev+3f2a1b9**: the next version, then the commit it was built from, plus `.changed` if you have changes you haven't committed yet. You'll see it in the dialog titles and the log.

**Mac** (in Terminal, in the repo folder):
```
./build/build-macos.sh --dev --run
```
This builds `dist/dev/PhoneConnect.app` and starts it, closing a running copy first. Leave out `--run` to only build. It doesn't touch the PhoneConnect you installed in Applications.

**Windows** (in PowerShell, in the repo folder):
```
powershell -ExecutionPolicy Bypass -File build\build-windows.ps1 -Dev -Run
```
This builds a ready-to-run folder `dist\dev\PhoneConnect\` for this PC (Intel/AMD or ARM) and starts it. It needs nothing installed, not even Inno Setup: scrcpy, the bundled shell and the tools to unpack it are downloaded by the build.

**Builds from GitHub.** Every pull request, and every change on `main` that isn't released, is also built on GitHub. To download the files, open the run under **Actions** and scroll to **Artifacts**.

### Release builds

GitHub makes these automatically (see below). To make one yourself:

**Mac**, giving the `.dmg` and the zip (the `.dmg` needs a Mac; on Linux you get only the zip):
```
APP_VERSION=1.2.3 ./build/build-macos.sh
```

**Windows**, giving the installer and the portable zips (needs [Inno Setup 6](https://jrsoftware.org/isdl.php); add `-SkipInstaller` to build only the zips):
```
$env:APP_VERSION = "1.2.3"
powershell -ExecutionPolicy Bypass -File build\build-windows.ps1
```

## Versions and releases

Versions look like **x.y.z**, for example 1.4.2. Every release is tagged `vX.Y.Z` and kept on the [Releases page](../../releases), which is the full version history, with the list of changes in each one.

Releases are made by the project's maintainers (people with write access to this repository); merging, pushing to `main` and running the release workflow all need that access. Anyone else can contribute through a pull request from a fork: it gets built and checked, and a maintainer decides whether to merge it.

**How a change gets released:**
1. **Open a pull request into `main`.** GitHub builds the Mac and Windows apps for it. If either build fails, the pull request can't be merged (once the rule below is on).
2. **Choose the version in the pull request form.** By default the **last** number goes up (1.2.3 → 1.2.4). To bump the **middle** number (1.3.0) or the **first** number (2.0.0) instead, tick the matching box under *Version*. A comment on the pull request always shows which version merging it will create, and it updates when you change the boxes.
3. **A maintainer merges it.** GitHub works out the version, builds it, tags the commit `vX.Y.Z` and publishes the release. The tag is only created once both builds succeed.

**Landing a change without releasing it.** Tick **Don't release this change** at the top of the pull request form, or add the label `no-release`. When you merge, `main` is updated and built, but no version is made. The change is included in the next release. For a direct push, put `[no release]` in the commit message.

**Pushing straight to `main`** (maintainers only). Admins can push directly; the rule below lets them skip the pull request. Such a push is built and released like a merged pull request, unless the commit message says `[no release]`. Choose the version the same way, with `[minor]` or `[major]`. Pushes go out without the pull request build check, though, so use a pull request when you want the check first.

Instead of ticking a version box, you can add the label `release:minor` or `release:major` to the pull request. Maintainers can also make a release by hand: **Actions → Build → Run workflow** and choose which number to bump.

The version is built into everything:
- **Mac:** the app's version in Finder's *Get Info*, the dialog titles, the log, and the installer window's name.
- **Windows:** the `.exe` and installer details (*Properties → Details*), *Apps & features*, the dialog titles and the log.

The download links at the top always point to the newest release.

**Turning on the merge check** (once, by a repository admin). GitHub only enforces this if the rule is added. Go to **Settings → Rules → Rulesets → New ruleset → Import a ruleset** and choose `.github/rulesets/main.json`. The rule makes every change go through a pull request whose **Build macOS** and **Build Windows** checks pass, while still letting the repository's admins (you) push straight to `main`. With the [GitHub CLI](https://cli.github.com), you can do it in one line instead:
```
gh api -X POST repos/JzviaginPhoneConnect/phone-connect/rulesets --input .github/rulesets/main.json
```
On a free GitHub account, rulesets work on public repositories. A private repository needs GitHub Pro.

**First version.** Until the first release exists, the first version is taken from the `VERSION` file (`1.0.0`).

**Updating scrcpy** (or any bundled MSYS2 package on Windows). In `build/versions.env`, change the version and checksums (scrcpy's are in `SHA256SUMS.txt` on its release page). Then keep the licensing complete: update the matching `SOURCE_*` lines, bump `THIRD_PARTY_SOURCES_TAG`, and update the versions and the sources link in `THIRD_PARTY_NOTICES.md` and the README. The next release publishes the new sources (see `build/collect-sources.sh`).
