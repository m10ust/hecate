#!/bin/bash
# OCR-verify the four fresh shots
cd ~/Work/hecate || exit 1
for f in m4-11-schedule m4-12-firstrun m4-13-warn-live m4-14-panel-follows; do
  python3 tools/zoom_ocr.py receipts/$f.png 1795 5 1640 700 /tmp/ocr-$f.png 4
  tesseract /tmp/ocr-$f.png /tmp/ocr-$f --psm 6 2>/dev/null
  echo "===== $f ====="
  grep -vE '^\s*$' /tmp/ocr-$f.txt | head -16
done
