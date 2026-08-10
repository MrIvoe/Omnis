# Omnis Essentia analysis service

A small HTTP wrapper around real, unmodified [Essentia](https://essentia.upf.edu/)
that gives the Omnis app real BPM/key/mood analysis. `Omnis-Plugins/lib/audio_analysis_plugin.dart`
is the client that talks to this.

## Why this exists as a separate service

Essentia is a C++ library. Its own official tutorials only support running
it via Python on **Linux** (a prebuilt `essentia-tensorflow` pip wheel) or
**macOS** (building from source) — there is no supported way to run it
inside a Windows desktop app or a mobile Flutter binary, official or
otherwise. Compiling Essentia (and its TensorFlow dependency) from source
for Android/iOS/Windows and binding the result via `dart:ffi` is a
native-build project measured in days, not something that fits inside a
single source-editing pass. Running Essentia here, in its own normal
Python environment, and having the app call it over HTTP is the practical
way to get *real* Essentia results into the app today.

## ✅ Verification status

**Built, run, and verified end-to-end** via `docker build` + `docker run`
against a synthetic 440Hz test tone: `/health` reported
`{"essentia": true, "tagging_model": true}`, and `/analyze` returned a
real BPM, correctly identified the tone's key as A minor, and produced
plausible mood/genre tags (`instrumental`, `ambient`, ...) from the
MusiCNN model. `RhythmExtractor2013`'s return signature (the thing most
likely to have drifted across Essentia versions) is confirmed correct as
written.

One real bug was caught and fixed in this process:
`requirements.txt` used to install *both* `essentia` and
`essentia-tensorflow` unconditionally on Linux — they share the same
top-level `essentia` package namespace, so whichever pip happened to
install second silently overwrote the other's files. In practice that
was always plain `essentia`, so `TensorflowPredictMusiCNN` never
actually existed at import time even with the model files downloaded and
`essentia-tensorflow` reporting a successful install — `/health` would
have quietly reported `tagging_model: false` forever. The two are now
mutually exclusive by platform marker.

Still worth sanity-checking on a track you know well before trusting it
for your whole library — a pure test tone isn't a substitute for real
music across genres — but the pipeline itself, top to bottom, is real
and working, not just carefully-researched.

## What it does

- `POST /analyze` — accepts one audio file (`multipart/form-data`, field
  name `audio`), returns:
  ```json
  {
    "bpm": 128.4,
    "key": "C",
    "scale": "minor",
    "mood": "energetic",
    "genres": ["electronic", "techno"]
  }
  ```
- BPM and key/scale come from vanilla Essentia (`RhythmExtractor2013`,
  `KeyExtractor`) — deterministic DSP, no ML model, always available.
- `mood`/`genres` come from Essentia's MusiCNN auto-tagging model
  (`TensorflowPredictMusiCNN`), **only if you've downloaded the model
  files** (see below). Without them, those two fields come back `null`/
  empty and BPM/key still work — the service degrades gracefully rather
  than requiring the heavier TensorFlow install to do anything at all.

## Deploying it

### Option A — Docker (recommended)

```bash
cd tools/essentia_service
docker build -t omnis-essentia .
docker run -p 8686:8686 omnis-essentia
```

Then in the Omnis app: Settings → Audio analysis (Essentia) → set the URL
to `http://<this machine's IP>:8686`.

### Option B — bare Python (Linux only, per Essentia's own support matrix)

```bash
cd tools/essentia_service
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
./download_models.sh   # optional — mood/genre tagging
uvicorn app:app --host 0.0.0.0 --port 8686
```

## Models (optional, for mood/genre tagging)

`download_models.sh` fetches `msd-musicnn-1.pb` and `msd-musicnn-1.json`
from essentia.upf.edu (the same files the tutorial uses) into `./models/`.
The `.json` file's `classes` list is read at request time to map the
model's output indices to real tag names — deliberately not hardcoded
here, since getting that mapping wrong would silently mislabel every
track rather than fail loudly.

## Security note

This service has no authentication and accepts arbitrary file uploads for
analysis. It's meant for a trusted local network (your own machine, your
own LAN, or a container only the app can reach) — don't expose it to the
open internet without adding your own auth in front of it.
