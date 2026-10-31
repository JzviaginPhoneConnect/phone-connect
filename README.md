<p align="center"><img src="assets/PhoneConnect.png" width="128" alt="PhoneConnect icon"></p>

# PhoneConnect

**scrcpy in one click, for Mac and Windows.** No terminal, nothing else to install.

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-0070ba?logo=paypal&logoColor=white)](https://paypal.me/jzviagin)

Use your Android phone from your Mac or Windows PC: see its screen in a window, control it with your mouse and keyboard, dial calls without picking it up, and hear its sound on the computer. It also mirrors **Samsung DeX** as a desktop in a window.

PhoneConnect is a ready-to-use app around [scrcpy](https://github.com/Genymobile/scrcpy), the open-source Android screen mirroring tool. scrcpy is great but runs from the command line; PhoneConnect gives you an app you just open:

- **Everything included:** scrcpy and adb ship inside the app. No Homebrew, no Android SDK, no PATH setup.
- **Finds your phone by itself:** USB first, then Ethernet (a USB-C dock), then Wi-Fi, and it remembers the phone, so after one cable connection it works wirelessly.
- **Several phones:** asks which one to connect to, and keeps track of each phone's addresses.
- **Samsung DeX:** mirrors the DeX desktop in a window, even with no monitor attached (with an HDMI dummy plug).
- **Real keyboard:** typing uses the phone's own keyboard layouts, so other languages work.
- **Shows what it's doing** in a small window while it connects, and retries by itself if the picture doesn't come up.

<p align="center">
  <img src="assets/screenshots/dex.png" height="360" alt="PhoneConnect on a Mac, mirroring a Samsung DeX desktop in a window">
  <img src="assets/screenshots/phone.png" height="360" alt="PhoneConnect mirroring an Android phone's screen">
</p>

## Download

The newest version is on the [Releases page](../../releases/latest). Older versions stay available there too.

| Computer | Download |
|---|---|
| Mac, installer (Apple Silicon and Intel) | [PhoneConnect.dmg](../../releases/latest/download/PhoneConnect.dmg) |
| Mac, plain zip (same app) | [PhoneConnect-macOS.zip](../../releases/latest/download/PhoneConnect-macOS.zip) |
| Windows, installer (Intel/AMD and ARM) | [PhoneConnect-Setup.exe](../../releases/latest/download/PhoneConnect-Setup.exe) |
| Windows, no install, Intel/AMD | [PhoneConnect-Windows-x64-portable.zip](../../releases/latest/download/PhoneConnect-Windows-x64-portable.zip) |
| Windows, no install, ARM (e.g. Parallels on an Apple Silicon Mac) | [PhoneConnect-Windows-arm64-portable.zip](../../releases/latest/download/PhoneConnect-Windows-arm64-portable.zip) |

## Install

**Mac**
1. Open **PhoneConnect.dmg** and drag **PhoneConnect** onto the **Applications** folder in the window that appears.
2. Open PhoneConnect from Launchpad or Applications. The first time, macOS blocks it because it isn't from a registered Apple developer. Go to **System Settings → Privacy & Security**, scroll down to the message about PhoneConnect, and click **Open Anyway**. You only need to do this once.

**Windows**
1. Run **PhoneConnect-Setup.exe**. No admin rights are needed.
2. If Windows shows **"Windows protected your PC"**, click **More info → Run anyway**. The app isn't signed with a paid certificate, so this appears once.
3. Start PhoneConnect from the Start menu or the desktop shortcut.

## Phone setup (once)

1. On the phone, go to **Settings → About phone → Software information** and tap **Build number** 7 times to unlock Developer options.
2. In **Settings → Developer options**, turn on **USB debugging**.
3. Plug the phone into the computer with a USB cable and open PhoneConnect. On the phone, tap **Allow** on *"Allow USB debugging?"* and tick **Always allow from this computer**.

## How it works

When you open PhoneConnect:

1. **It finds the phone.** It tries a **USB** cable first, then **Ethernet** (a USB-C dock with a network port), then **Wi-Fi**. The window title shows which one it used, for example *PhoneConnect (Ethernet)*.
2. **It shows the settings** in one window, remembered for each phone:
   - **Show:** **DeX** or the **phone screen** (only when a DeX screen is connected, or the phone can run DeX/desktop mode headless).
   - **Sound:** on the phone, or on the computer (the phone's own speaker is then muted).
   - **Video encoder:** the phone's video encoders, the best one marked ★. Phones without a hardware H.265 encoder (e.g. Redmi A3) get hardware H.264; H.265 done in software is slow and blurry.
4. **The phone opens in a window.** If no picture arrives within 15 seconds, it restarts the connection by itself, up to 3 tries.

**Going cable-free.** Whenever the phone is plugged in, PhoneConnect switches on the phone's network mode and remembers its Wi-Fi and Ethernet addresses. After that you can unplug, and the next launches connect over the network. The phone forgets network mode when it **restarts**, so plug it in once after each restart.

**The Ethernet address** is learned automatically the first time you open PhoneConnect while the phone is in a dock with a network cable. From then on, it uses the wired connection whenever the phone is docked.

**DeX without a monitor.** DeX only starts when the phone thinks a screen is connected. A cheap **HDMI dummy plug** in the dock's HDMI port does the trick.

## Tips

- **Typing in other languages.** PhoneConnect makes your keyboard act as a real keyboard plugged into the phone, so the phone's own layouts work (Hebrew included). Switch language with the phone's shortcut, usually **Ctrl+Space** or **Shift+Space**. On a Mac, first turn off macOS's own Ctrl+Space shortcut: **System Settings → Keyboard → Keyboard Shortcuts → Input Sources**.
- **Mouse and keyboard shortcuts in the window:** right-click is **Back**, middle-click is **Home**. On a Mac, Cmd+B is Back, Cmd+H is Home and Cmd+S is recent apps. On Windows, the same shortcuts use Alt.
- **Lock screen.** Android blacks out the lock screen in any mirror, so you can't see the pattern. Unlock on the phone itself, or use **Settings → Lock screen → Extend Unlock** (trusted places or devices).
- **Calls.** You can dial and answer from the window, but call audio stays on the phone or its Bluetooth earbuds. Android doesn't let screen mirroring carry call audio.

## Troubleshooting

| Problem | What to do |
|---|---|
| "No phone found" | Plug in the USB cable once (always needed after the phone restarts). Check that USB debugging is on and that you tapped **Allow** on the phone. |
| Choppy picture | Use a cable or Ethernet rather than Wi-Fi. On the phone, set **Display → Motion smoothness** to **Standard**. |
| It keeps retrying | Make sure the computer and phone are on the same network and no VPN is running. |
| Anything else | Look at the log of the last run: Mac `/tmp/PhoneConnect.log`, Windows `%TEMP%\PhoneConnect.log` |

## Support

PhoneConnect is free. If it's useful to you, you can support its development with a donation via [PayPal](https://paypal.me/jzviagin). Thank you!

## For developers

How the app is built, tested and released: [DEVELOPMENT.md](DEVELOPMENT.md).

## License

PhoneConnect's own files are under the [MIT License](LICENSE). The bundled software (scrcpy, adb, and on Windows the shell the app runs on) keeps its own licenses: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The full license texts ship with the app in its `licenses` folder, and the exact source code of all bundled software is published in the [third-party sources release](../../releases/tag/third-party-sources-1).

PhoneConnect is an independent project, not affiliated with or endorsed by Genymobile (scrcpy), Google or Samsung.
