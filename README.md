# FlareUI Druid

[**Download the latest release**](https://github.com/Minnona/FlareUI-Druid/releases/latest/download/FlareUI-Druid.zip)

A small [FlareUI](https://github.com/malkkav/FlareUI) plugin for WoW Forever. Hides the extra druid mana bar at full mana while shapeshifted and brings it back as soon as mana drops below full. Works in and out of combat.

## Installation

1. Install FlareUI if you don't already have it.
2. Download the ZIP above and extract `FlareUI_Druid` into your game's `Interface/AddOns` folder.
3. Restart the game and enable **FlareUI Druid** in the addon list.
4. In FlareUI's player-frame Edit Mode settings, turn on **Mana on Shapeshift**.

Full-mana hiding is on by default. FlareUI's files are left unchanged.

## Commands

| Command | What it does |
| --- | --- |
| `/fuidruid` | Show whether full-mana hiding is on. |
| `/fuidruid on` | Hide the extra mana bar at full mana. |
| `/fuidruid off` | Restore FlareUI's usual mana-bar behavior. |

## Frame styles

Modern and FlareUI styles give the hidden bar's space back to the health bar. Forever Style hides the mana bar but keeps its extra row.

Edit Mode previews remain visible. Tested with FlareUI 7.0.12 on WoW Forever.

## Feedback

[Report an issue](https://github.com/Minnona/FlareUI-Druid/issues) with your FlareUI version, frame style, and the output of `/fuidruid debug`.

## Credits and license

FlareUI is made by Malkkav. This is an independent companion addon.

FlareUI Druid is licensed under [GPL-3.0](LICENSE). FlareUI's [MIT license](LICENSES/FlareUI.txt) covers its adapted layout relationships.
