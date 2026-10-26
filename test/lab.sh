#!/usr/bin/env bash
# What the lab's header comment promises, checked from inside the lab's own network and through
# docker exec, which is how the platform's terminal reaches the lab's Python: run by check.sh.
set -euo pipefail
: "${NET:?run through test/check.sh}"
: "${CID:?run through test/check.sh}"
probe() { docker run --rm --network "$NET" lab-check-probe bash -c "$1"; }
run() { docker exec "$CID" "$@"; }
# Prints what a step says, and fails with it when the line wanted is not there.
want() { echo "$out" | grep -Fxq "$1" || { echo "no line '$1' in: $out" >&2; exit 1; }; }

echo "- JupyterLab answers with no token to type"
probe '
set -eu
code=$(curl -s -o /dev/null -w "%{http_code}" http://jupyter:8888/lab)
[ "$code" = 200 ] || { echo "JupyterLab answered $code" >&2; exit 1; }
curl -fs http://jupyter:8888/api/contents | grep -q "start.ipynb" || { echo "no start.ipynb" >&2; exit 1; }
curl -fs -H "Host: someone-8888.example.com" -H "Origin: https://someone-8888.example.com" \
  http://jupyter:8888/api/kernelspecs | grep -q python3 || { echo "a proxied host is refused" >&2; exit 1; }
echo "- no way out to the internet"
if curl -s -m 4 -o /dev/null https://example.com; then echo "the lab reached the internet" >&2; exit 1; fi
'

echo "- the work folder holds five pictures, the notebook and the eight step scripts"
run ls images/coins.png images/shapes.png images/road.png images/scan.png images/gradient.png \
  start.ipynb steps/look.py steps/grey.py steps/threshold.py steps/blur.py steps/edges.py \
  steps/count.py steps/resize.py steps/find.py >/dev/null
run python3 -c "
from PIL import Image
for name, size, mode in [('coins', (320, 240), 'RGB'), ('shapes', (300, 200), 'RGB'), ('road', (320, 240), 'L'),
                         ('scan', (320, 240), 'L'), ('gradient', (256, 64), 'L')]:
    p = Image.open('images/%s.png' % name)
    assert (p.size, p.mode) == (size, mode), (name, p.size, p.mode)
"

echo "- look.py: a 320 by 240 RGB picture, a dark background pixel and a gold coin pixel"
out=$(run python3 steps/look.py)
want "size: (320, 240)"; want "mode: RGB"
want "pixel at 10, 10: (35, 35, 35)"; want "pixel at 50, 50: (197, 157, 62)"; want "grey mean: 57.6"

echo "- grey.py: the grey picture is mode L, its pixels fall in the dark and the middle bands, and it is saved"
out=$(run python3 steps/grey.py)
want "colour mode: RGB grey mode: L"; want "grey pixel at 50, 50: 158"
want "pixels from 0 to 63: 63231"; want "pixels from 64 to 127: 0"
want "pixels from 128 to 191: 13566"; want "pixels from 192 to 255: 3"
want "saved coins_grey.png"
run python3 -c "import sys; sys.exit(open('coins_grey.png', 'rb').read(8) != bytes([137, 80, 78, 71, 13, 10, 26, 10]))"

echo "- threshold.py: a higher threshold keeps fewer pixels, and the mask is saved"
out=$(run python3 steps/threshold.py)
want "threshold 30 keeps 58806 pixels of 76800"; want "threshold 100 keeps 13569 pixels of 76800"
want "threshold 160 keeps 10062 pixels of 76800"; want "saved coins_mask.png"
test -n "$(run find coins_mask.png -size +0)"

echo "- blur.py: blurring an empty patch of the scan lowers its spread from 25.3 to 4.9"
out=$(run python3 steps/blur.py)
want "spread of an empty patch before: 25.3"; want "spread of an empty patch after: 4.9"
want "saved scan_blurred.png"

echo "- edges.py: edges are found on the shapes picture"
out=$(run python3 steps/edges.py)
want "picture pixels: 60000"; want "edge pixels: 1326"; want "saved shapes_edges.png"

echo "- count.py: nine coins, three of each of the three sizes"
out=$(run python3 steps/count.py)
want "objects found: 9"; want "areas in pixels: [657, 657, 657, 1313, 1313, 1313, 2553, 2553, 2553]"

echo "- resize.py: half and cropped pictures are 160 by 120, and a PNG and a JPEG are written"
out=$(run python3 steps/resize.py)
want "original: (320, 240)"; want "half size: (160, 120)"; want "cropped: (160, 120)"
echo "$out" | grep -Eq "^full\.png [0-9]+ bytes$" && echo "$out" | grep -Eq "^half\.png [0-9]+ bytes$" \
  && echo "$out" | grep -Eq "^full\.jpg [0-9]+ bytes$" || { echo "no file sizes in: $out" >&2; exit 1; }
run python3 -c "import sys; sys.exit(open('full.jpg', 'rb').read(3) != bytes([255, 216, 255]))"

echo "- find.py: a piece cut from 30, 30 is found there again with a perfect score"
out=$(run python3 steps/find.py)
want "piece cut from the corner at 30, 30, size (40, 40)"; want "best match starts at 30 30"
want "match score: 1.0"

echo "- the starter notebook runs from top to bottom inside the memory limit"
run jupyter nbconvert --to notebook --execute start.ipynb --output /tmp/ran.ipynb >/dev/null 2>&1 \
  || { echo "start.ipynb does not run" >&2; exit 1; }
echo "  ok"
