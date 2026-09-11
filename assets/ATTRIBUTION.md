# Icon attribution

Every glyph in this directory comes from [game-icons.net](https://game-icons.net) and is
used under the [Creative Commons Attribution 3.0 Unported licence](https://creativecommons.org/licenses/by/3.0/)
(CC BY 3.0), which requires that the artist be credited.

| File | Icon | Artist |
|---|---|---|
| `power-generator.svg` | [Power generator](https://game-icons.net/1x1/delapouite/power-generator.html) | Delapouite |
| `energise.svg` | [Energise](https://game-icons.net/1x1/lorc/energise.html) | Lorc |
| `ball-glow.svg` | [Ball glow](https://game-icons.net/1x1/lorc/ball-glow.html) | Lorc |
| `energy-tank.svg` | [Energy tank](https://game-icons.net/1x1/delapouite/energy-tank.html) | Delapouite |
| `upgrade.svg` | [Upgrade](https://game-icons.net/1x1/delapouite/upgrade.html) | Delapouite |
| `glowing-artifact.svg` | [Glowing artifact](https://game-icons.net/1x1/delapouite/glowing-artifact.html) | Delapouite |
| `question.svg` | [Uncertainty](https://game-icons.net/1x1/lorc/uncertainty.html) | Lorc |
| `power-lightning.svg` | [Power lightning](https://game-icons.net/1x1/lorc/power-lightning.html) | Lorc |
| `speedometer.svg` | [Speedometer](https://game-icons.net/1x1/delapouite/speedometer.html) | Delapouite |
| `targeting.svg` | [Targeting](https://game-icons.net/1x1/lorc/targeting.html) | Lorc |
| `split-cross.svg` | [Split cross](https://game-icons.net/1x1/lorc/split-cross.html) | Lorc |
| `water-splash.svg` | [Water splash](https://game-icons.net/1x1/lorc/water-splash.html) | Lorc |
| `meteor-impact.svg` | [Meteor impact](https://game-icons.net/1x1/lorc/meteor-impact.html) | Lorc |
| `eye-target.svg` | [Eye target](https://game-icons.net/1x1/delapouite/eye-target.html) | Delapouite |
| `striking-diamonds.svg` | [Striking diamonds](https://game-icons.net/1x1/lorc/striking-diamonds.html) | Lorc |
| `burst-blob.svg` | [Burst blob](https://game-icons.net/1x1/lorc/burst-blob.html) | Lorc |
| `overdrive.svg` | [Overdrive](https://game-icons.net/1x1/lorc/overdrive.html) | Lorc |
| `two-coins.svg` | [Two coins](https://game-icons.net/1x1/delapouite/two-coins.html) | Delapouite |
| `mining.svg` | [Mining](https://game-icons.net/1x1/lorc/mining.html) | Lorc |
| `cut-diamond.svg` | [Cut diamond](https://game-icons.net/1x1/lorc/cut-diamond.html) | Lorc |
| `padlock.svg` | [Padlock](https://game-icons.net/1x1/lorc/padlock.html) | Lorc |
| `exit-door.svg` | [Exit door](https://game-icons.net/1x1/delapouite/exit-door.html) | Delapouite |
| `fast-arrow.svg` | [Fast arrow](https://game-icons.net/1x1/lorc/fast-arrow.html) | Lorc |
| `anticlockwise-rotation.svg` | [Anticlockwise rotation](https://game-icons.net/1x1/delapouite/anticlockwise-rotation.html) | Delapouite |

Four glyphs are **not** from game-icons.net and need no attribution:

| File | Icon | Origin |
|---|---|---|
| `amplify.svg` | Three widening chevrons | Original to this project |
| `compress.svg` | Four arrows converging on a block | Original to this project |
| `teleport.svg` | Two rings joined by a bar | Original to this project |
| `distribute.svg` | One input fanning to three outputs | Original to this project |

## The one modification

Each file is the upstream artwork with a single element deleted: the opaque backing
rectangle,

```html
<path d="M0 0h512v512H0z"/>
```

which game-icons.net includes unless the download is taken with a transparent background.
It has to go. `Icons.draw` recolours a glyph by modulating white artwork, so a file that
keeps its backing rect renders as a black square with the shape knocked out of it, instead
of as a shape. Two of the icons this project shipped previously
had it and four did not, which is why the board's blocks did not look like a set.

**So the invariant for anything added here is: exactly one `<path fill="#fff">`, on
transparency, in a `0 0 512 512` viewBox.** Check a new file against that before wiring it
into `Icons`, and set `mipmaps/generate=true` in its `.import` or it shimmers when drawn
small. It applies to original artwork as much as to a download —
the four original glyphs are drawn to the same shape for the same reason.
