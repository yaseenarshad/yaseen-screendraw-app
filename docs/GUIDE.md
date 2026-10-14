<p align="center">
  <img src="assets/icon.png" width="96" alt="The icon of Yaseen Screendraw: a white hand-written Y on an indigo square">
</p>

# The guide

How to install and use Yaseen Screendraw, with each detail. The short version is on the [first page](../README.md).

- [Install from a release](#install-from-a-release)
- [The modes](#the-modes)
- [The keys](#the-keys)
- [The toolbar](#the-toolbar)
- [Use the screen while the pen is paused](#use-the-screen-while-the-pen-is-paused)
- [What happens to the marks](#what-happens-to-the-marks)
- [The menu](#the-menu)
- [Settings](#settings)
- [Questions after the install](#questions-after-the-install)

## Install from a release

The app needs a Mac with Apple Silicon and macOS 14 or later.

1. Open the [releases page](https://github.com/yaseenarshad/yaseen-screendraw-app/releases/latest) and download `Yaseen-Screendraw-<version>-arm64.dmg`.
2. Open the `.dmg`. Drag "Yaseen Screendraw" onto the "Applications" link.
3. Start the app from `/Applications`. macOS stops it the first time, because the app is not notarized.
4. Open System Settings, then Privacy & Security. Click "Open Anyway" next to "Yaseen Screendraw". You do this one time.
5. The app shows its icon in the menu bar. Press Control-Option-D and draw.

There is no permission step. The app asks for no macOS permission.

- The app lives in the menu bar. It has no Dock icon and opens no window at its start.
- The first start turns "Open at login" on. To turn it off, open Settings from the menu bar icon.
- Only one copy of the app runs. A second copy quits at once.

## The modes

The app has three modes.

- **Off.** The screen works as usual. The app has no window on the screen and runs no timer.
- **Drawing.** A transparent layer is on each screen. The mouse draws. The layer has the keyboard.
- **Click-through.** The pen is paused. The toolbar stays on the screen. The mouse and the keyboard go to the apps below. The marks stay on the screen, or they are hidden until you draw again (see [Use the screen while the pen is paused](#use-the-screen-while-the-pen-is-paused)).

The menu bar icon is a pencil in a circle. The circle is filled while the mode is drawing or click-through.

- The layer is above each app, a full-screen app, the menu bar and the Dock. In mode drawing, a click on the menu bar or the Dock draws.
- The app below stays the active app while you draw.
- A screenshot shows the marks. The toolbar asks macOS to leave it out of a screen capture. macOS 15 and later can ignore this.

## The keys

| Key | What it does |
| -- | -- |
| Control-Option-D | Turns drawing on and off. The toolbar shows at the place that you gave it. At the first start it is at the bottom centre of the screen that has the pointer. |
| Control-Option-C | Changes between drawing and click-through. From drawing, the marks stay visible. While drawing is off, it shows the toolbar with the pen paused: the screen works as usual, and a click on a tool starts drawing. |
| Esc | Pauses the pen: the mode changes to click-through, and you can use the screen. It removes no mark. The marks are hidden until you draw again. A setting keeps them visible. If a text is open, Esc only cancels that text. If a mark is selected, Esc only removes the selection. |
| Delete | With a selected mark, it removes only that mark. With no selection, it clears all the marks. Drawing stays on. Command-Z brings the marks back. Delete is the one key that removes marks. |
| Shift | During a drag, it makes the mark straight (see [The tools](#the-tools)). |
| Command-Z | Undo. |
| Shift-Command-Z | Redo. |
| Command-comma | Pauses the pen and opens Settings. It does the same as the gear of the toolbar. |

- Control-Option-D and Control-Option-C are the two hotkeys. They work from each app. You can change the two (see [Settings](#settings)).
- Esc, Delete, Shift, Command-Z, Shift-Command-Z and Command-comma are fixed keys. They are not in Settings.
- The fixed keys work only in mode drawing. In click-through, each key goes to the app below.
- Forward Delete does the same as Delete.
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
- You can change each of the 21 keys (see [Settings](#settings)).
- The toolbar keys work only in mode drawing. They are not hotkeys. In click-through and while drawing is off, each key goes to the app that has the keyboard.
- While a text is open, each key is for the typing.
- A key with Command, Control or Option is not a toolbar key.
- Shift and Caps Lock do not stop a key: the case of a letter does not count.
- The app compares the character that the key types, not the position of the key. Thus the keys follow your keyboard layout. Shift with a digit types a different character, so it is not the key of the digit.
- A key during a drag does nothing. The mark in progress keeps its tool, its size and its colour.
- A key that stays down makes one change only.

## The toolbar

<p align="center">
  <img src="assets/toolbar.png" width="860" alt="The toolbar in its two forms: one row, and one column at the edge of a screen. The first button is Click through. Each button shows its key in its corner, and a tip shows the name and the key of one button.">
</p>

The toolbar is one row. From its start:

- The grip: six small dots. A drag of the grip moves the toolbar.
- "Click through": the pointer arrow. A click pauses the pen, and a second click starts it again (see [Use the screen while the pen is paused](#use-the-screen-while-the-pen-is-paused)).
- The tools: Select, Pen, Highlight, Line, Arrow, Rectangle, Ellipse, Text, Stamp. The picture of Select is four arrows.
- Undo, Redo, Clear all.
- Three sizes: Thin, Medium, Thick.
- Six colours: red, amber, green, blue, black, white.
- The switch Fade, Hold, Sticky.
- The gear. It opens Settings (see [The gear](#the-gear)).
- Close, at the end. It does the same as Control-Option-D.

Each button shows its key in its bottom right corner. The key is small, thin and faint. "Click through" shows `esc`, Undo shows `⌘Z`, Redo shows `⇧⌘Z`, Clear all shows `⌫`, and the gear shows `⌘,`. Close shows no key.

Other rules of the toolbar:

- In click-through the toolbar is dim and still takes clicks. The "Click through" button is lit. A click on it, or on a tool, goes back to drawing. Undo, Redo, Clear all, the sizes, the colours and the switch do their work, and the mode stays. If the marks are hidden, you see the result when you draw again. Close stops drawing.
- With two screens there is one toolbar. A mark stays on the screen where its drag started.
- The toolbar never takes the keyboard. After a click on a button, Esc and the typing still work.

### The tools

- **Select:** it draws nothing. It moves and changes the marks that exist (see [Select](#select)).
- **Pen:** a drag draws a line. A click makes a dot.
- **Highlight:** a wide line that you can see through.
- **Line:** a straight line with no head.
- **Arrow:** the head is at the end of the drag.
- **Rectangle and Ellipse:** an outline with no fill.
- **Text:** click, then type. Return finishes the text. Option-Return starts a new line. A click at a different place also finishes the text. An empty text makes no mark.
- **Stamp:** a click puts a filled circle with a number in it. The first stamp is 1. The next stamp has the highest number of the stamps on all screens, plus 1. After Clear all, the next stamp is 1 again.

A Rectangle, an Ellipse, a Line or an Arrow smaller than 4 points makes no mark.

Shift makes the mark of a drag straight. You can press or release Shift in the middle of a drag, and the mark changes at once.

- Pen and Highlight: one straight line from the start to the pointer.
- Line and Arrow: the angle goes in steps of 45 degrees.
- Rectangle and Ellipse: a square or a circle.

The size and the colour apply to each tool and to new marks only. For a Text, the size is the size of the letters. For a Stamp, the size is the size of the circle.

The app remembers the tool, the size, the colour and the switch. At the first start they are Pen, Thick, red and Sticky.

### How long a mark stays

The switch sets how long a new mark stays. Each mark keeps the value that it was drawn with.

- **Fade:** the mark stays for the Fade seconds of Settings (2 at the start). It fades during the last second, and then it is gone.
- **Hold:** the marks stay while you draw. Their clock is the Hold seconds of Settings (5 at the start). It starts at the last pointer down, drag or pointer up of a drawing tool. After the Hold seconds, the marks fade together for 1 second and are gone.
- **Sticky:** the mark stays until you clear it.

A mark that its clock removed does not come back with Undo.

### Select

With Select, a click on a mark selects it. The selected mark shows a thin dashed outline and its handles.

- A click on the line of a mark selects it. For a Rectangle and an Ellipse, a click on the empty inside selects it too. Where two marks are at the same place, the newest mark wins, and a line wins over an empty inside.
- A click on an empty place removes the selection. A different tool, click-through and the stop of drawing remove it too.
- A drag of a mark moves it. The mark stays on its screen.
- A drag of a handle changes the size of a Rectangle, an Ellipse, an Arrow or a Line. A Pen mark, a Highlight mark, a Text and a Stamp only move.
- A size button or a colour button, or its key, changes the selected mark. It is also the size or the colour of the next mark.
- A double-click on a Text mark opens its text again. Return finishes it. An empty text removes the mark.
- Delete removes only the selected mark. Esc removes only the selection. The next Esc pauses the pen.
- A move, a size change, a size or colour change and a delete are one Undo step each.
- A Fade or Hold mark can be selected while it is visible. A move does not start its clock again.
- The switch Fade, Hold, Sticky does not change the selected mark.

### The forms and the place of the toolbar

- A drag of the grip, or of a gap between two groups of buttons, moves the toolbar. The drag makes no mark.
- Drop the toolbar near the left or the right edge of a screen. It becomes one column at that edge. "Near" is: the middle of the toolbar, or the pointer, is less than 120 points from the edge.
- Drop the column away from the two edges. It is one row again.
- The form changes when you release the mouse, not during the drag. After the release, the toolbar is fully in the visible part of the screen.
- On a screen that is too narrow for the row, the toolbar has two rows. On a screen that is too low for the column, it has two columns.
- In a column, each button keeps its key in its corner. Fade, Hold and Sticky keep their full names.
- The app remembers the place and the form. The toolbar is there at the next start of drawing and at the next start of the app.
- Sometimes that screen is gone, or the toolbar is not fully in its visible part. Then the toolbar is one row at the bottom centre of the screen that has the pointer. The first start is the same.
- You can drag the toolbar to the other screen. The rules use the screen that has the pointer when you release the mouse.

### The hover tip

- Rest the pointer on a button for half a second. A small tip shows the name and the key of the button, for example "Arrow  A".
- The tip of "Click through" is "Click through  esc". Close has no key, so its tip is "Close".
- The tip goes away when the pointer leaves the button, and when you click.
- A row has its tip above the button. A column has its tip at the side that has room.
- The tip also shows while a different app is the active app.

### The gear

- The gear is immediately before Close. Its key is Command-comma.
- In mode drawing, the gear first changes the mode to click-through: the marks stay, and the toolbar is dim. Then the settings window opens in front.
- In click-through, the gear opens the settings window. The mode does not change. Marks that are hidden stay hidden.
- A text that is open, or a drag in progress, is finished first.
- After you close the settings window, the mode is still click-through. Press Control-Option-C or click a tool to draw again.

## Use the screen while the pen is paused

There are three ways to pause the pen from mode drawing. Each one changes the mode to click-through.

- **Esc.** The marks are hidden, so the screen is clean. With the setting "Marks stay visible after Esc" on, the marks stay visible.
- **The "Click through" button** of the toolbar. The marks stay visible.
- **Control-Option-C.** The marks stay visible.

To draw again, click a tool, click "Click through", or press Control-Option-C. Hidden marks show again at the same places.

- Hidden marks are not deleted. The app keeps them and the Undo history.
- The clocks of Fade and Hold marks continue while the marks are hidden. A mark whose time is over is gone when you draw again.
- In click-through no window of the app has the keyboard. Esc and each other key go to the app below. Thus Esc pauses the pen, and it does not start it again.
- "Show toolbar" from drawing off also keeps the marks hidden: the Sticky marks that the app keeps show again when you draw.
- Esc during a drag first finishes the mark in progress and keeps it. Then the pen is paused.
- While the pen is paused, the pointer is the usual arrow.

## What happens to the marks

- Control-Option-D and Close stop drawing. The app keeps the Sticky marks in memory and drops the Fade and Hold marks. The Sticky marks show again when you start drawing again.
- Esc removes no mark. It pauses the pen and hides the marks until you draw again.
- Delete removes the selected mark, or each mark when no mark is selected.
- Clear all removes each mark on each screen. One Undo brings them back.
- A hotkey during a drag, or while a text is open, first finishes that mark. Then the mode changes.
- If you remove a screen, the app drops the marks of that screen.
- Quit removes all the marks. The app writes no mark to the disk.

## The menu

Click the menu bar icon. In mode drawing the layer is above the menu bar, so pause the pen first (Esc), or stop drawing.

- "Start drawing" or "Stop drawing", with its hotkey.
- "Show toolbar", with the click-through hotkey, while drawing is off. It shows the toolbar with the pen paused. The Sticky marks that the app keeps stay hidden. Click a tool to draw, and they show again.
- "Click through", with the same hotkey, while drawing is on. It has a check mark in click-through, with visible and with hidden marks.
- "Clear all". It also clears the Sticky marks that the app keeps while drawing is off.
- "Settings…". It is not available in mode drawing. There, use the gear of the toolbar or Command-comma.
- "Quit".

## Settings

<p align="center">
  <img src="assets/settings.png" width="560" alt="The settings window: the two hotkeys, Open at login, Fade seconds and Hold seconds, the switch Marks stay visible after Esc, and the 21 toolbar keys in four groups">
</p>

The settings window stays above the other windows until you close it. Command-W closes it.

- **The two hotkeys.** The rows are "Draw on / off" and "Click through". Click "Change…" next to a hotkey and press the new key. Esc or "Cancel" stops with no change.
  - A hotkey needs Command, Control or Option with the key, or it is a function key (F1 to F20).
  - The two hotkeys must be different.
  - If the app or macOS refuses a key, a red line tells why and the old hotkey stays.
  - A new hotkey works at once. The menu shows it.
- **Open at login.** The switch shows the real state from macOS. The first start of the installed app turns it on one time. You can turn it off here or in System Settings, Login Items.
- **Marks.** "Fade seconds" and "Hold seconds" set how long a Fade mark and the Hold marks stay. The start values are 2 and 5.
  - A value is a whole number from 1 to 60. Type it and press Return or Tab. The app remembers it.
  - If the field is empty or has a different value, a red line tells the rule. The old value stays.
  - A Fade mark keeps the seconds that it was drawn with. The Hold marks on the screen use a new value at once.
  - "Marks stay visible after Esc" is a switch. It is off at the start: Esc hides the marks until you draw again. Turn it on, and the marks stay on the screen after Esc. The new value applies at the next Esc.
- **Toolbar keys.** The 21 keys of the toolbar are in four groups: Tools, Sizes, Colours, Stay. Click the key of a button and type the new key. Esc or a second click stops with no change.
  - A key is one letter, digit or punctuation mark, with no Command, Control or Option. Space, Return, Tab, Esc, Delete and the arrow keys are not possible.
  - Each key belongs to one button only. If a different button has the key, a red line names that button and the old key stays. Give that button a different key first.
  - A new key works at once. The toolbar shows it, and the app remembers it.
  - "Reset to the start keys" gives each of the 21 keys its start value. The two hotkeys do not change.
  - If the stored keys are not valid, the app uses the start keys.
  - While a recorder of a hotkey or of a toolbar key listens, the two hotkeys are paused.

## Questions after the install

**I do not see the menu bar icon.**
A MacBook with a notch hides the icons that do not fit. A full menu bar can put an icon behind the notch.

- At its first start, the app asks macOS for a place to the right of the notch.
- To move an icon, hold Command and drag it. Put the icons that you use most at the right, near the clock.
- The two hotkeys work also when the icon does not show.

**A hotkey does nothing.**
A different app can have the same hotkey. Then macOS refuses it for this app. Open Settings from the menu bar icon. A red line below the hotkey tells this. Click "Change…" and press a different key.

**I cannot click the menu bar icon while I draw.**
In mode drawing, the layer is above the menu bar, and a click there draws. Press Esc or Control-Option-C, or stop drawing. Then click the icon.

**"Settings…" is grey in the menu.**
The row is not available in mode drawing. Click the gear of the toolbar, or press Command-comma.

**A toolbar key does nothing.**
The toolbar keys work only in mode drawing. In click-through, the key goes to the app below. While a text is open, the key is for the typing.

**Esc does not start the pen again.**
Esc pauses the pen. While the pen is paused, Esc goes to the app below. To draw again, click a tool, click "Click through", or press Control-Option-C.

**My marks are gone after Esc.**
They are hidden, not deleted. Click a tool, click "Click through", or press Control-Option-C. The marks show again at the same places. To keep them on the screen after Esc, turn on "Marks stay visible after Esc" in Settings.

**My marks are gone after I stopped drawing.**
Control-Option-D and Close keep only the Sticky marks. They drop the Fade and Hold marks. The Sticky marks show again when you start drawing again.

**The toolbar has two rows, or two columns.**
The screen is too narrow for one row, or too low for one column. If you have two columns, drop the toolbar away from the left and the right edge. Then it is a row.

**The toolbar is in my screenshot.**
The toolbar asks macOS to leave it out of a screen capture. macOS 15 and later can ignore this.

**Where does the app keep my settings?**
In the preferences of macOS: `~/Library/Preferences/com.yaseenarshad.yaseenscreendraw.plist`. The file has the hotkeys, the toolbar keys, the two seconds values and the switch of Esc. It also has your last tool, size, colour and switch. And it has the place of the toolbar and of the menu bar icon. It has no mark.
