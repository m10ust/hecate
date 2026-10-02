#!/bin/bash
# Hecate M4: sync tree -> installed plugin, then shoot on-screen receipts
set -u
cd ~/Work/hecate || exit 1
SRC=io.github.m10ust.hecate
DST=~/.config/omarchy/plugins/io.github.m10ust.hecate

echo "== 1. sync tree to installed plugin =="
rsync -a --delete --exclude '__pycache__' "$SRC/" "$DST/"
diff -r --exclude '__pycache__' "$SRC" "$DST" && echo "TREE == INSTALLED"
