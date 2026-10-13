# Yaseen Screendraw

A small app for the Mac that lets you draw on the screen with the mouse. Press a hotkey, draw on top of any app, and press the hotkey again to stop.

- It is a native Swift app. It lives in the menu bar and has no Dock icon.
- It needs macOS 14 or later on an Apple Silicon Mac.
- It asks for no macOS permission.
- It has no outside dependency.

## The modes

The app has three modes.

- **Off.** The screen works as usual. The app has no overlay window and runs no timer.
- **Drawing.** A transparent overlay is on each screen. The mouse draws. The overlay has the keyboard.
- **Click-through.** The marks stay on the screen. The mouse and the keyboard go to the apps below.

The menu bar icon is a pencil in a circle. The circle is filled while the mode is drawing or click-through.

- The overlay is above each app, a full-screen app, the menu bar and the Dock. In mode drawing, a click on the menu bar or the Dock draws.
- A screenshot shows the marks. The toolbar asks macOS to leave it out of a screen capture. macOS 15 and later can ignore this.

## The keys

| Key | What it does |
| -- | -- |
| Control-Option-D | Turns drawing on and off. A toolbar shows at the bottom centre of the screen that has the pointer. |
| Control-Option-C | Changes between drawing and click-through. It does nothing while drawing is off. |
| Esc | Cancels the text that is open. With no open text, it clears all the marks and stops drawing. |
| Command-Z | Undo. |
| Shift-Command-Z | Redo. |

- Control-Option-D and Control-Option-C work from each app. You can change the two (see "Settings").
- Esc, Command-Z and Shift-Command-Z work only in mode drawing. In click-through, each key goes to the app below.
- While a text is open, Command-Z and Shift-Command-Z are for the typing.
- Undo goes back 200 steps.

## The toolbar

Row 1:

- The tools: Pen, Highlight, Arrow, Rectangle, Ellipse, Text.
- Undo, Redo, Clear all.
- Close, at the right end. It does the same as Control-Option-D.

Row 2:

- Three sizes: Thin, Medium, Thick.
- Six colours: red, amber, green, blue, black, white.
- The switch Fade, Hold, Sticky.

How the tools work:

- Pen: a drag draws a line. A click makes a dot.
- Highlight: a wide line that you can see through.
- Arrow: the head is at the end of the drag.
- Rectangle and Ellipse: an outline with no fill.
- Text: click, then type. Return finishes the text. Option-Return starts a new line. A click at a different place also finishes the text. An empty text makes no mark.
- A Rectangle, an Ellipse or an Arrow smaller than 4 points makes no mark.

The size and the colour apply to each tool and to new marks only. The app remembers the tool, the size, the colour and the switch. At the first start they are Pen, Thick, red and Sticky.

The switch sets how long a new mark stays. Each mark keeps the value that it was drawn with.

- Fade: the mark is at full strength for 1 second. Then it fades for 1 second and is gone.
- Hold: the marks stay while you draw. 5 seconds after the last pointer down, drag or pointer up, they fade together for 1 second and are gone.
- Sticky: the mark stays until you clear it.

Other rules of the toolbar:

- A drag that starts between the buttons moves the toolbar. At the next start of drawing it is at the bottom centre again.
- In click-through the toolbar is dim and still takes clicks. A click on a tool goes back to drawing with that tool.
- With two screens there is one toolbar. A mark stays on the screen where its drag started.

## What happens to the marks

- Control-Option-D and Close stop drawing. The app keeps the Sticky marks in memory and drops the Fade and Hold marks. The Sticky marks show again when you start drawing again.
- Esc clears all the marks and stops drawing. Start drawing again and press Command-Z one time to get them back.
- Clear all removes each mark on each screen. One Undo brings them back.
- Quit removes all the marks. The app writes no mark to the disk.

## The menu

Click the menu bar icon. In mode drawing the overlay is above the menu bar, so change to click-through first, or stop drawing.

- "Start drawing" or "Stop drawing", with its hotkey.
- "Click through", with its hotkey. It is available while drawing is on. It has a check mark in click-through.
- "Clear all". It also clears the Sticky marks that the app keeps while drawing is off.
- "Settings…". It is not available in mode drawing.
- "Quit".

## Settings

- **The two hotkeys.** Click "Change…" next to a hotkey and press the new key. Esc or "Cancel" stops with no change.
  - A hotkey needs Command, Control or Option with the key, or it is a function key (F1 to F20).
  - The two hotkeys must be different.
  - If the app or macOS refuses a key, a red line tells why and the old hotkey stays.
- **Open at login.** The switch shows the real state from macOS. The first start of the installed app turns it on one time. You can turn it off here or in System Settings, Login Items.

## Install from a release

1. Open the [releases page](../../releases) and download `Yaseen-Screendraw-<version>-arm64.dmg`.
2. Open the `.dmg`. Drag "Yaseen Screendraw" onto the "Applications" link.
3. Start the app from `/Applications`. macOS stops it the first time, because the app is not notarized.
4. Open System Settings, then Privacy & Security. Click "Open Anyway" next to "Yaseen Screendraw". You do this one time.
5. The app shows its icon in the menu bar. Press Control-Option-D and draw.

There is no permission step. The app asks for no macOS permission.

The first start turns "Open at login" on. To turn it off, open Settings from the menu bar icon.

## Build

You need Xcode.

- `swift build`: build the app for development.
- `swift test`: run the unit tests.
- `scripts/bundle.sh`: make `build/Yaseen Screendraw.app` from a release build and sign it.
- `scripts/bundle.sh --dmg`: also make `build/Yaseen-Screendraw-<version>-arm64.dmg`.
- `scripts/install.sh`: quit the app that runs, put the new app in `/Applications`, and open it. Run `scripts/bundle.sh` first.
- `scripts/make-signing-cert.sh`: make the certificate "Yaseen Local Signing" in your login keychain. Read "The signature" below first.
- `swift scripts/make-icon.swift`: draw the app icon again into `Support/AppIcon.icns`. Run it only after a change to the drawing. It also writes three preview pictures into `build/`.

The version is in one place: `CFBundleShortVersionString` in `Support/Info.plist`.

## The signature

`scripts/bundle.sh` signs with the certificate "Yaseen Local Signing". With a fixed certificate, each build has the same signature, and macOS sees each build as the same app. Set `SIGN_IDENTITY` to use a certificate with a different name.

If the keychain does not have the certificate, the script signs ad-hoc and prints this:

```
WARNING: the keychain does not have the certificate "Yaseen Local Signing". The signature will be ad-hoc. macOS sees each ad-hoc build as a different app.
```

Set `REQUIRE_SIGN_IDENTITY=1` to make that an error. Then the script stops before the build.

The app asks for no macOS permission, so an ad-hoc build works. The app uses no entitlement and no usage description.

### Make the certificate (one time)

Yaseen Screenshot uses the same certificate. If you made the certificate for that app, do not make it again.

1. Check if the keychain has the certificate:

   ```bash
   security find-identity -p codesigning
   ```

   If the list shows `"Yaseen Local Signing"`, go to step 3. The text `CSSMERR_TP_NOT_TRUSTED` next to it is normal for a self-signed certificate.
2. Run `scripts/make-signing-cert.sh`. The script changes your login keychain, so the owner of the Mac runs it.
3. Run `scripts/bundle.sh`. The first time, macOS can ask if `codesign` can use the key. Enter your login password and click "Always Allow".
4. Check the signature:

   ```bash
   codesign -d -r- "build/Yaseen Screendraw.app"
   ```

   The output must name a certificate (`certificate leaf = H"…"`). It must not show `cdhash`.

Keep this certificate. A new certificate is a new signature.

### Give the certificate to GitHub (one time)

The release workflow signs with the same certificate. It reads two repository secrets. The secrets of the Yaseen Screenshot repository do not apply to this repository. Add them here too.

1. Select a password for the `.p12` file. Then export the certificate and its private key:

   ```bash
   security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P 'YOUR-P12-PASSWORD' -o ~/yaseen-local-signing.p12
   ```

   This command exports all the identities in the login keychain. If the keychain has other identities, use Keychain Access instead: select "Yaseen Local Signing" in "My Certificates", then File, Export Items, format "Personal Information Exchange (.p12)".
2. Add the two secrets with the GitHub CLI. Run these commands in the repository folder:

   ```bash
   base64 -i ~/yaseen-local-signing.p12 | gh secret set SIGN_CERT_P12_BASE64
   gh secret set SIGN_CERT_PASSWORD
   ```

   The second command asks for the value. Paste the password of the `.p12` file.
3. Delete the file:

   ```bash
   rm ~/yaseen-local-signing.p12
   ```

Without the two secrets, the release workflow signs ad-hoc. It writes a warning in its log, and the release page tells that the build is ad-hoc signed.

## Releases

- No release is cut automatically.
- Set the new version in `Support/Info.plist` (`CFBundleShortVersionString`) and merge it into `main`.
- Tag that commit `vX.Y.Z` and push the tag. `.github/workflows/release.yml` builds the `.dmg` and attaches it to the GitHub release of that tag. It makes the release if it does not exist.
- The workflow fails if the tag is not the version in `Support/Info.plist`.
- The workflow writes the kind of signature at the top of the release text: the certificate, or ad-hoc.
- `.github/workflows/ci.yml` runs `swift build` and `swift test` on each pull request.
