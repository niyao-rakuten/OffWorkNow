"""User-approved translation-only registration of the imagegen test atlas.

Run from repository root. Preserves original pixels, alpha and proportions.
All 36 cells share a foot baseline and lower-body center; never resize poses.
"""
from pathlib import Path
from PIL import Image

directory = Path(__file__).resolve().parent
source = Image.open(directory / "source/office-girl-stable-imagegen.png").convert("RGBA")
edges = [0, 209, 418, 624, 831, 1040, 1254]
output = Image.new("RGBA", (1536, 1536))
for row in range(6):
    for column in range(6):
        cell = source.crop((column * 209, edges[row], (column + 1) * 209, edges[row + 1]))
        mask = cell.getchannel("A").point(lambda value: 255 if value > 20 else 0)
        lower_top = int(cell.height * 0.75)
        lower = mask.crop((0, lower_top, cell.width, cell.height)).getbbox()
        assert lower is not None
        center = (lower[0] + lower[2]) / 2
        baseline = lower_top + lower[3]
        x, y = round(128 - center), 228 - baseline
        bounds = mask.getbbox()
        assert bounds and bounds[0] + x >= 0 and bounds[2] + x <= 256
        assert bounds[1] + y >= 0 and bounds[3] + y <= 256
        output.alpha_composite(cell, (column * 256 + x, row * 256 + y))
output.save(directory / "office-girl-36frames-stable.png")
print("Aligned 36 frames: 1536 × 1536, fixed x=128 ± 0.5 px, baseline=228 px; no resizing.")
