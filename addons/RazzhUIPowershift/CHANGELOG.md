# RazzhUIPowershift

## Unreleased

- New module for druids who powershift. A powershift macro (`/cancelform`, then `/cast Bear Form`) leaves the game thinking you have no form for three seconds: the action bar drops to the caster bar and your form's abilities say "Must be in Bear Form". With this module one key leaves the form as you press it and takes it again as you let go, and everything works at once.
- To use it from an action bar, put a macro with `#showtooltip Bear Form` and `/click RazzhUIPowershiftBear` on a bar: the key of that slot becomes the powershift key while that slot is showing. For Cat Form the button is `RazzhUIPowershiftCat`. A bear macro on your bear bar and a cat macro on your cat bar can share a key. Clicking the slot with the mouse only casts the form, as the form's own button does.
- You can also bind a key directly under Options > Keybindings > AddOns > RazzhUI Powershift.
