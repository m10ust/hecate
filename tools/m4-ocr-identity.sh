#!/bin/bash
# OCR the three identity receipts from the located panel bbox
cd ~/Work/hecate || exit 1
for f in m4-7-identity-rig-nvme m4-8-identity-bee-ssh m4-9-identity-tmpfs-unknown; do
  python3 tools/zoom_ocr.py receipts/$f.png 1795 5 1640 680 /tmp/ocr-$f.png 3
  tesseract /tmp/ocr-$f.png /tmp/ocr-$f >/dev/null 2>&1
  echo "===== $f ====="
  grep -vE '^\s*$' /tmp/ocr-$f.txt | head -22
done
