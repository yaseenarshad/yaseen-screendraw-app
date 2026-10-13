# Yaseen Screendraw

A small app for the Mac that lets you draw on the screen with the mouse. Press a hotkey, draw on top of any app, and press the hotkey again to stop.

- It is a native Swift app. It lives in the menu bar and has no Dock icon.
- It needs macOS 14 or later on an Apple Silicon Mac.
- It asks for no macOS permission.
- It has no outside dependency.

## The hotkeys

| Key | What it does |
| -- | -- |
| Control-Option-D | Turns drawing on and off. A toolbar shows at the bottom of the screen that has the pointer. |
| Control-Option-C | Turns click-through on and off while drawing is on. The marks stay, and the clicks go to the apps below. |
| Esc | Clears all the marks and stops drawing. |

You can change the two hotkeys. Click the menu bar icon, open Settings, and click "Change…" next to a hotkey. Settings also has the "Open at login" switch.

## The toolbar

- Tools: Pen, Highlight, Arrow, Rectangle, Ellipse, Text.
- Three sizes and six colours.
- Undo, Redo, Clear all, Close.
- A switch sets how long a new mark stays:
  - Fade: the mark goes away 2 seconds after you finish it.
  - Hold: the marks go away together, 5 seconds after the last drawing.
  - Sticky: the mark stays until you clear it.

Control-Option-D stops drawing and keeps the Sticky marks. They show again when you start drawing again.

## Install from a release

1. Open the [releases page](../../releases) and download `Yaseen-Screendraw-<version>-arm64.dmg`.
2. Open the `.dmg`. Drag "Yaseen Screendraw" onto the "Applications" link.
3. Start the app from `/Applications`. macOS stops it the first time, because the app is not notarized.
4. Open System Settings, then Privacy & Security. Click "Open Anyway" next to "Yaseen Screendraw". You do this one time.
5. The app shows its icon in the menu bar. Press Control-Option-D and draw.

There is no permission step. The app asks for no macOS permission.

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
