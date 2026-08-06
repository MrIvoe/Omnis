#!/usr/bin/env bash
# Fetches the MusiCNN auto-tagging model files from essentia.upf.edu — the
# exact same files and URLs Essentia's own tutorial uses:
# https://essentia.upf.edu/tutorial_tensorflow_auto-tagging_classification_embeddings.html
#
# Optional: the service works without these (BPM/key only). Run this if
# you also want mood/genre tagging and have installed essentia-tensorflow.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p models
cd models

BASE_URL="https://essentia.upf.edu/models/autotagging/msd"

if [ ! -f msd-musicnn-1.pb ]; then
  echo "Downloading msd-musicnn-1.pb..."
  curl -fL -o msd-musicnn-1.pb "$BASE_URL/msd-musicnn-1.pb"
fi

if [ ! -f msd-musicnn-1.json ]; then
  echo "Downloading msd-musicnn-1.json..."
  curl -fL -o msd-musicnn-1.json "$BASE_URL/msd-musicnn-1.json"
fi

echo "Models ready in $(pwd)"
