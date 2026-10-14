<p align="center">
  <img src="docs/assets/banner.png" width="860" alt="Yaseen Screendraw. Draw on top of any app on your Mac with one hotkey.">
</p>

<p align="center">
  <a href="https://github.com/yaseenarshad/yaseen-screendraw-app/releases/latest"><img src="https://img.shields.io/github/v/release/yaseenarshad/yaseen-screendraw-app?label=version" alt="The newest version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/yaseenarshad/yaseen-screendraw-app" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B%20%C2%B7%20Apple%20Silicon-blue" alt="macOS 14 or later, Apple Silicon">
</p>

<p align="center">
  <a href="https://github.com/yaseenarshad/yaseen-screendraw-app/releases/latest"><b>Download</b></a> ·
  <a href="#the-answer">How it works</a> ·
  <a href="#the-four-keys-to-know">Keys</a> ·
  <a href="docs/GUIDE.md">Guide</a>
</p>

<p align="center">
  <b>Stop wiggling your mouse. Press one key and circle the exact spot, on top of any app.</b>
</p>

<p align="center">
  <img src="docs/assets/hero.gif" width="860" alt="Press Control-Option-D, and the toolbar shows. Draw a circle, an arrow and number stamps on a recipe. Press Esc: the marks hide, and the pointer ticks a check box in the app. Click the Pen, and the marks are back.">
</p>

<p align="center">
  <a href="https://github.com/yaseenarshad/yaseen-screendraw-app/releases/latest"><b>Download for Mac</b></a><br>
  <sub>Free · Apple Silicon · macOS 14 or later · under 400 KB · no permission</sub>
</p>

## The problem

Every time I shared my screen, I ended up wiggling my mouse and saying "no, look here". The screen pen I tried would not let me change its keys. So I built a small one where you can customize any key.

You know these moments:

- You wiggle your mouse over the spot. Somebody still asks "where?"
- You turn on a screen pen, and your screen is dead. You can't click one thing under it.
- You draw five marks. Then everyone waits while you clean them up by hand.
- Its shortcut fights with an app that you use every day, and you can't change it.

## The answer

Yaseen Screendraw makes your pointer a pen on top of any app, and one key gives you your screen back.

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/assets/step-1.png" width="260" alt="The keys Control, Option and D"><br><b>1. Press Control-Option-D</b><br>Your pointer is a pen.</td>
    <td align="center" width="33%"><img src="docs/assets/step-2.png" width="260" alt="A mark on a window, with the toolbar below it"><br><b>2. Draw</b><br>A circle, an arrow, a number.</td>
    <td align="center" width="33%"><img src="docs/assets/step-3.png" width="260" alt="The key Esc. The pen is paused: the toolbar is dim, the Click through button is lit, and the pointer clicks in the app."><br><b>3. Press Esc</b><br>You work in your app again.</td>
  </tr>
</table>

## What it does

### Show the exact spot, in any app

Press **Control-Option-D** in any app. Your pointer is a pen, above each window, a full-screen app, the menu bar and the Dock. Each tool, size and colour has one key: **A** for an arrow, **R** for a rectangle, **4** for red.

**So what:** nobody waits while you look for a button. You press one key and circle it.

<p align="center">
  <img src="docs/assets/toolbar.png" width="860" alt="The toolbar in its two forms: one row, and one column at the edge of a screen. The first button is Click through. Each button shows its key in its corner, and a tip shows the name and the key of one button.">
</p>

### Click right through your marks

Click the first button of the toolbar, or press **Control-Option-C**. The pen pauses, your marks stay, and each click goes to the app below. Do you want a clean screen? Press **Esc**: the marks hide until you draw again, and nothing is deleted.

**So what:** your screen is never dead. You point, you click, you point again.

<p align="center">
  <img src="docs/assets/click-through.gif" width="860" alt="A click on the Click through button pauses the pen. The marks stay on the screen while the pointer works in the app below them.">
</p>

### Marks that clean up after themselves

One switch on the toolbar sets how long a new mark stays:

- **Fade:** the mark is gone after 2 seconds.
- **Hold:** the marks stay while you draw. They fade together 5 seconds after your last mark.
- **Sticky:** the mark stays until you remove it.

You set the two times yourself, from 1 to 60 seconds.

**So what:** you point at ten things in a row, and you clean up nothing.

<p align="center">
  <img src="docs/assets/fade-hold-sticky.gif" width="860" alt="One mark fades by itself after a short time, and one mark stays on the screen.">
</p>

### Fix one mark, keep the rest

Press **V**, and drag a mark to move it. Drag a handle of a shape to change its size. Press **N**, and each click stamps the next number: 1, 2, 3. Hold **Shift** for a straight line, a square or a circle.

**So what:** a wrong mark costs you one drag, not the full drawing. And people follow your steps by number.

<p align="center">
  <img src="docs/assets/select-and-stamps.gif" width="860" alt="Three clicks put the number stamps 1, 2 and 3. Then Select moves a mark and changes its size.">
</p>

### No more shortcut fights

Change the two hotkeys. Change each of the 21 toolbar keys: nine tools, three sizes, six colours, and Fade, Hold, Sticky. Is a key taken? A red line tells you, and your old key stays.

**So what:** the pen fits the apps that you use. Your apps do not have to fit the pen.

<p align="center">
  <img src="docs/assets/settings.png" width="560" alt="The settings: the two hotkeys, Open at login, Fade seconds and Hold seconds, the switch Marks stay visible after Esc, and the 21 toolbar keys in four groups">
</p>

And more:

- Put the toolbar where you want it: one row, or one column at the edge of a screen. It stays there.
- Undo goes back 200 steps.
- Stop with Control-Option-D, and your Sticky marks are back the next time you draw.
- One switch in Settings keeps your marks on the screen after Esc.
- No Dock icon. The app lives in the menu bar.

## The proof

Measured on version 1.0.0. No estimates.

| What | Number |
| -- | -- |
| The download | Under 400 KB |
| The app on your disk | 1 MB |
| Permissions that the app asks for | 0 |
| Automatic tests behind each version | 276 |

What the app does not need:

- No permission. The app draws on top of your screen. It does not read your screen.
- No account.
- No payment.
- No internet. The app has no network code.

And while you do not draw, the app has no window on your screen and runs no timer. It waits for your hotkey.

## The doubts

**Is it safe?**
Yes. The app does not read your screen, and it has no network code, so nothing leaves your Mac. It saves no mark to your disk. The code is in this repo, and you can read each line.

**Does it work with two screens?**
Yes. You draw on every screen that you plug in. One toolbar serves them all, and you drag it to the screen that you want.

**Does it cost money?**
No. It is free, with the [MIT license](LICENSE). No trial, no account, no paid version.

**Why does macOS warn me at the first start?**
Apple asks a developer for a yearly fee to take that warning away, and this app is free. You click "Open Anyway" one time. After that, the app opens like any other app.

**Does it run on an Intel Mac or on Windows?**
No. It is for Macs with Apple Silicon.

## The download

[**Download the newest `.dmg`**](https://github.com/yaseenarshad/yaseen-screendraw-app/releases/latest). You need a Mac with Apple Silicon and macOS 14 or later.

1. Open the `.dmg`.
2. Drag **Yaseen Screendraw** to **Applications**.
3. Open the app. macOS stops it the first time.
4. Go to **System Settings › Privacy & Security** and click **Open Anyway**.

That is all. There is no permission step. The pencil icon is in your menu bar, and the app opens at login, so your hotkey is always ready. You can turn that off in Settings.

The first three things to try:

1. Press **Control-Option-D** and circle something. Press **Esc**: the circle hides, and your screen works again.
2. Click the Pen on the toolbar. The circle is back. Press **A**, draw an arrow, and click the first button of the toolbar. Your marks stay, and your clicks go to the app below.
3. Click the Pen again. Press **F** and draw. Each new mark is gone after 2 seconds. Press **S** to make your marks stay again.

### The four keys to know

| Key | What it does |
| -- | -- |
| Control-Option-D | Draw on and off. |
| Control-Option-C | Pause the pen and keep your marks on the screen. Press it again to draw. While drawing is off, it shows the toolbar. |
| Esc | Pause the pen and hide your marks until you draw again. It deletes nothing. |
| Delete | Remove all the marks, or only the selected mark. |

You can change the first two in Settings. The [guide](docs/GUIDE.md) has each other key.

## For developers

The app is one Swift package: a library, a small executable and the tests, with no outside package. The [developer page](docs/DEVELOPMENT.md) tells how to build, test, sign and release it. The [guide](docs/GUIDE.md) has each detail for users.

The license is [MIT](LICENSE).
