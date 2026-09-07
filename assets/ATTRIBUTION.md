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

## The one modification

Each file is the upstream artwork with a single element deleted: the opaque backing
rectangle,

```html
<path d="M0 0h512v512H0z"/>
```

which game-icons.net includes unless the download is taken with a transparent background.
It has to go. `GraphView._draw_icon` recolours a glyph by modulating white artwork against
the cell, so a file that keeps its backing rect renders as a black square with the shape
knocked out of it, instead of as a shape. Two of the icons this project shipped previously
had it and four did not, which is why the board's blocks did not look like a set.

**So the invariant for anything added here is: exactly one `<path fill="#fff">`, on
transparency, in a `0 0 512 512` viewBox.** Check a new file against that before wiring it
into `BlockCatalog`.
