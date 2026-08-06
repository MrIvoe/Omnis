# Omnis Essentia analysis service

A small HTTP wrapper around real, unmodified [Essentia](https://essentia.upf.edu/)
that gives the Omnis app real BPM/key/mood analysis. `lib/plugins/audio_analysis_plugin.dart`
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

## ⚠️ Verification status

**This has not been built or run.** The coding session that wrote it had
network access and a CMake/MSVC/Android toolchain, but no running Docker
daemon and no Python interpreter, and Essentia's own tutorials only
support Linux/macOS in the first place — none of which this Windows
session could exercise. This is a careful, from-the-docs implementation of
Essentia's [own documented API](https://essentia.upf.edu/documentation.html)
and [TensorFlow auto-tagging tutorial](https://essentia.upf.edu/tutorial_tensorflow_auto-tagging_classification_embeddings.html),
not a tested artifact. **Build and run it once yourself and sanity-check
the output on a track you know well before trusting it for your library.**
The most likely thing to need adjusting is `RhythmExtractor2013`'s exact
return signature, which has changed across Essentia versions.

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
