# For developers

How to build, test, sign and release Yaseen Screendraw. The guide for users is [here](GUIDE.md).

## Build

You need Xcode. The package has no outside dependency.

- `swift build`: build the app for development.
- `swift test`: run the unit tests. They open no window and need no permission.
- `scripts/bundle.sh`: make `build/Yaseen Screendraw.app` from a release build and sign it.
- `scripts/bundle.sh --dmg`: also make `build/Yaseen-Screendraw-<version>-arm64.dmg`.
- `scripts/install.sh`: quit the app that runs, put the new app in `/Applications`, and open it. Run `scripts/bundle.sh` first. The script changes `/Applications`, so the owner of the Mac runs it.
- `scripts/make-signing-cert.sh`: make the certificate "Yaseen Local Signing" in your login keychain. Read [The signature](#the-signature) first.
- `swift scripts/make-icon.swift`: draw the app icon again into `Support/AppIcon.icns`. Run it only after a change to the drawing. It also writes three preview pictures into `build/`.

The version is in one place: `CFBundleShortVersionString` in `Support/Info.plist`.

`build/` and `.build/` are in `.gitignore`. `scripts/bundle.sh` removes only its own earlier output from `build/`.

## The code

- `Sources/ScreendrawKit`: all the code of the app, as a library. Thus the tests can import it.
- `Sources/YaseenScreendraw`: the executable. It makes one call: `AppController.main()`.
- `Tests/ScreendrawKitTests`: the unit tests.
- `DrawSession` holds the state of the drawing part, with no window and no view. The state is the mode, the marks, the tool, the Undo history and the clocks of Fade and Hold. It also tells if the marks are hidden.
- The views and the windows are thin layers on top of `DrawSession`. They put a window on the screen only while the app runs (`NSApplication.shared.isRunning`). A test never runs the app, so a test shows no window.
- The package uses the Swift 5 language mode. The compiler of CI can be older than the compiler on your Mac.

## Test

`swift test` runs the full set. Version 1.0.0 has 276 tests.

- A test opens no window and uses no mouse and no keyboard.
- A test never registers a real hotkey or a real login item. It uses a fake one.
- A test keeps the settings in memory. It writes nothing into `~/Library/Preferences`.

### The pen timing test

`PenTimingTests` measures a Pen line of 5,000 points on a screen that already has 100 marks. Run it alone to read the result:

```bash
swift test --filter PenTimingTests
```

It prints one line, for example:

```
Pen line of 5,000 points, best of 3: 54.9 ms in total, 11.0 µs for each point, 0.03 ms for the slowest point
```

- The time is the time of the code of this app on the main thread. That code is the session, the controller, the view with its layers, and the toolbar.
- No window is on a screen. Thus the time has no part of the window server of macOS.
- The test fails when one point costs 1 ms or more on average.

### The pictures from the tests

Some tests draw the real views into a bitmap, with no window. With this variable, they also write the pictures as PNG files:

```bash
SCREENDRAW_PNG_DIR="$PWD/build" swift test
```

The files go into `build/`. They show the toolbar in each form, with its tips. They show the settings form in the light and in the dark look, and the marks. Without the variable, a test run writes no file.

### The log

The app writes one log line when macOS refuses a hotkey at the start. Read it with the full path of the tool (in some shells, `log` is a different command):

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.yaseenarshad.yaseenscreendraw"'
```

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
2. Run `scripts/make-signing-cert.sh`. The script changes your login keychain, so the owner of the Mac runs it. The certificate is self-signed and free. It is valid for 10 years.
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
- You can also start the workflow by hand for a tag that exists. It builds the `.dmg` again and replaces the file of that release.
- `.github/workflows/ci.yml` runs `swift build` and `swift test` on each pull request.
- The two workflows run on the fixed runner `macos-26`. They select the newest Xcode of that runner that is not a beta or a release candidate. They print the tool versions in the log.

A change of the README or of `docs/` needs no new release.

## The license

The license is [MIT](../LICENSE).
