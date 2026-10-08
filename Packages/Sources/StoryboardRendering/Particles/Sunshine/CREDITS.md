# Sunshine light shafts

From **Free Sunshine Photoshop Brushes 5** (`.abr`, Photoshop v6.2 brush file).

Licence: **open licence, as stated by the project author.** The source site and
licence text were not recorded when the pack was added — if they turn up, put
them here, since these files ship inside the binary and are copied into every
exported beatmap folder.

Extracted with `scripts/abr-to-png.swift` (white, mask in alpha), scaled to
1024 on the long side and **feathered on every side** — most of these brushes
run into the edge of their own canvas, and drawn on the stage that edge is a
visible cut:

```
magick <tip>.png -filter Lanczos -resize 1024x1024 -channel A \
  -fx 'ff=min(min(1,min(min(i/(w*0.12),(w-1-i)/(w*0.12)),(h-1-j)/(h*0.18))),j/(h*0.07)); a*ff*ff*(3-2*ff)' \
  +channel -strip -define png:color-type=6 sunshine_NN.png
```

12% on the sides, 18% at the bottom, 7% at the top (where the light starts,
so it fades in instead of beginning on a sawn-off edge), smoothstepped.
Five of the pack's fifteen tips: the rest were near-duplicates of these or a
haze with no direction to it.

| File | Brush | What it is |
|---|---|---|
| `sunshine_01.png` | #1 | A thin ray, leaning right from its source |
| `sunshine_11.png` | #11 | Broad diagonal rays from the top left |
| `sunshine_12.png` | #12 | Stage lights: three sources, beams crossing |
| `sunshine_13.png` | #13 | A fan of rays opening downward from the top centre |
| `sunshine_15.png` | #15 | A bright, soft spotlight cone |
