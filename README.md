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
| Control-Option-D | Turns drawing on and off. The toolbar shows at the place that you gave it. At the first start it is at the bottom centre of the screen that has the pointer. |
| Control-Option-C | Changes between drawing and click-through. It does nothing while drawing is off. |
| Esc | Cancels the text that is open. With a selected mark, it removes only the selection. With neither, it clears all the marks and stops drawing. |
| Delete | With a selected mark, it removes only that mark. With no selection, it clears all the marks. Drawing stays on. Command-Z brings the marks back. |
| Shift | During a drag, it makes the mark straight (see "How the tools work"). |
| Command-Z | Undo. |
| Shift-Command-Z | Redo. |
| Command-comma | Pauses the pen and opens Settings. It does the same as the gear of the toolbar. |

- Control-Option-D and Control-Option-C work from each app. You can change the two (see "Settings").
- Esc, Delete, Shift, Command-Z, Shift-Command-Z and Command-comma are fixed keys. They are not in Settings.
- Esc, Delete, Command-Z, Shift-Command-Z and Command-comma work only in mode drawing. In click-through, each key goes to the app below.
- While a text is open, Delete, Command-Z and Shift-Command-Z are for the typing.
- Undo goes back 200 steps.

### The toolbar keys

Each tool, size, colour and value of the switch has a key. The key does the same as a click on the button. These are the keys at the start:

| Button | Key |  | Button | Key |  | Button | Key |
| -- | -- | -- | -- | -- | -- | -- | -- |
| Select | V |  | Text | T |  | Green | 6 |
| Pen | W |  | Stamp | N |  | Blue | 7 |
| Highlight | H |  | Thin | 1 |  | Black | 8 |
| Line | D |  | Medium | 2 |  | White | 9 |
| Arrow | A |  | Thick | 3 |  | Fade | F |
| Rectangle | R |  | Red | 4 |  | Hold | G |
| Ellipse | O |  | Amber | 5 |  | Sticky | S |

- P also selects the Pen, while no button has the key P.
- L also selects the Line, while no button has the key L.
- Each button of the toolbar shows its key in its bottom right corner. Undo shows ⌘Z, Redo shows ⇧⌘Z, Clear all shows ⌫, the gear shows ⌘, and Close shows esc.
- You can change each of the 21 keys (see "Settings").
- The toolbar keys work only in mode drawing. They are not global hotkeys. In click-through and while drawing is off, each key goes to the app that has the keyboard.
- While a text is open, each key is for the typing.
- A key with Command, Control or Option is not a toolbar key.
- Shift and Caps Lock do not stop a key: the case of a letter does not count.
- The app compares the character that the key types, not the position of the key. Thus the keys follow your keyboard layout. Shift with a digit types a different character, so it is not the key of the digit.
- A key during a drag does nothing. The mark in progress keeps its tool, its size and its colour.
- A key that stays down makes one change only.

## The toolbar

The toolbar is one row. From its start:

- The grip: six small dots. A drag of the grip moves the toolbar.
- The tools: Select, Pen, Highlight, Line, Arrow, Rectangle, Ellipse, Text, Stamp.
- Undo, Redo, Clear all.
- Three sizes: Thin, Medium, Thick.
- Six colours: red, amber, green, blue, black, white.
- The switch Fade, Hold, Sticky.
- The gear. It opens Settings (see "The gear").
- Close, at the end. It does the same as Control-Option-D.

Each button shows its key in its bottom right corner (see "The toolbar keys").

How the tools work:

- Select: it draws nothing. It moves and changes the marks that exist (see "Select").
- Pen: a drag draws a line. A click makes a dot.
- Highlight: a wide line that you can see through.
- Line: a straight line with no head.
- Arrow: the head is at the end of the drag.
- Rectangle and Ellipse: an outline with no fill.
- Text: click, then type. Return finishes the text. Option-Return starts a new line. A click at a different place also finishes the text. An empty text makes no mark.
- Stamp: a click puts a filled circle with a number in it. The first stamp is 1. The next stamp has the highest number of the stamps on all screens, plus 1. After Clear all, the next stamp is 1 again.
- A Rectangle, an Ellipse, a Line or an Arrow smaller than 4 points makes no mark.

Shift makes the mark of a drag straight. You can press or release Shift in the middle of a drag, and the mark changes at once.

- Pen and Highlight: one straight line from the start to the pointer.
- Line and Arrow: the angle goes in steps of 45 degrees.
- Rectangle and Ellipse: a square or a circle.

The size and the colour apply to each tool and to new marks only. For a Stamp, the size is the size of the circle. The app remembers the tool, the size, the colour and the switch. At the first start they are Pen, Thick, red and Sticky.

The switch sets how long a new mark stays. Each mark keeps the value that it was drawn with.

- Fade: the mark stays for the Fade seconds of Settings (2 at the start). It fades during the last second, and then it is gone.
- Hold: the marks stay while you draw. The Hold seconds of Settings (5 at the start) start at the last pointer down, drag or pointer up of a drawing tool. After them, the marks fade together for 1 second and are gone.
- Sticky: the mark stays until you clear it.

### Select

With Select, a click on a mark selects it. The selected mark shows a thin dashed outline and its handles.

- A click on an empty place removes the selection. A different tool, click-through and the stop of drawing remove it too.
- A drag of a mark moves it. The mark stays on its screen.
- A drag of a handle changes the size of a Rectangle, an Ellipse, an Arrow or a Line. A Pen mark, a Highlight mark, a Text and a Stamp only move.
- A size button or a colour button, or its key, changes the selected mark. It is also the size or the colour of the next mark.
- A double-click on a Text mark opens its text again. Return finishes it. An empty text removes the mark.
- Delete removes only the selected mark. Esc removes only the selection.
- A move, a size change, a size or colour change and a delete are one Undo step each.
- A Fade or Hold mark can be selected while it is visible. A move does not start its clock again.
- The switch Fade, Hold, Sticky does not change the selected mark.

Other rules of the toolbar:

- In click-through the toolbar is dim and still takes clicks. A click on a tool goes back to drawing with that tool.
- With two screens there is one toolbar. A mark stays on the screen where its drag started.

### The forms and the place of the toolbar

- A drag of the grip, or of a gap between two groups of buttons, moves the toolbar. The drag makes no mark.
- Drop the toolbar near the left or the right edge of a screen. It becomes one column at that edge. "Near" is: the middle of the toolbar, or the pointer, is less than 120 points from the edge.
- Drop the column away from the two edges. It is one row again.
- The form changes when you release the mouse, not during the drag. After the release, the toolbar is fully in the visible part of the screen.
- On a screen that is too narrow for the row, the toolbar has two rows. On a screen that is too low for the column, it has two columns.
- In a column, each button keeps its key in its corner. Fade, Hold and Sticky keep their full names.
- The app remembers the place and the form. The toolbar is there at the next start of drawing and at the next start of the app.
- If that screen is gone, or the toolbar is not fully in its visible part, the toolbar is at the bottom centre of the screen that has the pointer, as one row. The first start is the same.
- You can drag the toolbar to the other screen. The rules use the screen that has the pointer when you release the mouse.

### The hover tip

- Rest the pointer on a button for half a second. A small tip shows the name and the key of the button, for example "Arrow  A".
- The tip goes away when the pointer leaves the button, and when you click.
- A row has its tip above the button. A column has its tip at the side that has room.
- The tip also shows while a different app is the active app.

### The gear

- The gear is immediately before Close. Its key is Command-comma.
- In mode drawing, the gear first changes the mode to click-through: the marks stay, and the toolbar is dim. Then the settings window opens in front.
- In click-through, the gear opens the settings window. The mode does not change.
- A text that is open, or a drag in progress, is finished first.
- After you close the settings window, the mode is still click-through. Press Control-Option-C or click a tool to draw again.

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
- "Settings…". It is not available in mode drawing. There, use the gear of the toolbar or Command-comma.
- "Quit".

## Settings

- **The two hotkeys.** Click "Change…" next to a hotkey and press the new key. Esc or "Cancel" stops with no change.
  - A hotkey needs Command, Control or Option with the key, or it is a function key (F1 to F20).
  - The two hotkeys must be different.
  - If the app or macOS refuses a key, a red line tells why and the old hotkey stays.
- **Open at login.** The switch shows the real state from macOS. The first start of the installed app turns it on one time. You can turn it off here or in System Settings, Login Items.
- **Marks.** "Fade seconds" and "Hold seconds" set how long a Fade mark and the Hold marks stay. The start values are 2 and 5.
  - A value is a whole number from 1 to 60. Type it and press Return or Tab. The app remembers it.
  - If the field is empty or has a different value, a red line tells the rule and the old value stays.
  - A Fade mark keeps the seconds that it was drawn with. The Hold marks on the screen use a new value at once.
- **Toolbar keys.** The 21 keys of the toolbar are in four groups: Tools, Sizes, Colours, Stay. Click the key of a button and type the new key. Esc or a second click stops with no change.
  - A key is one letter, digit or punctuation mark, with no Command, Control or Option. Space, Return, Tab, Esc, Delete and the arrow keys are not possible.
  - Each key belongs to one button only. If a different button has the key, a red line names that button and the old key stays. Give that button a different key first.
  - A new key works at once. The toolbar shows it, and the app remembers it.
  - "Reset to the start keys" gives each of the 21 keys its start value. The two hotkeys do not change.
  - If the stored keys are not valid, the app uses the start keys.
  - While a recorder of a hotkey or of a toolbar key listens, the two hotkeys are paused.

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
- `SCREENDRAW_PNG_DIR="$PWD/build" swift test`: also write pictures of the toolbar, of the settings form and of the marks into `build/`. The tests draw them with no window.
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
