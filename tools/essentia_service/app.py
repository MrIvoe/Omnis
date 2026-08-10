"""Omnis Essentia analysis service.

A thin HTTP wrapper around real, unmodified Essentia. POST an audio file
to /analyze and get back BPM, musical key, and (if the TensorFlow
auto-tagging models are present) mood/genre tags.

Verification status: built and run via Docker against a synthetic 440Hz
test tone — /health reported {"essentia": true, "tagging_model": true},
and /analyze returned a real BPM, correctly identified the tone's key as
A minor, and produced plausible MusiCNN mood/genre tags. Every algorithm
call below matches Essentia's reference docs, confirmed against the
actual runtime output, not just checked at write time:

  - RhythmExtractor2013 outputs (bpm, ticks, confidence, estimates,
    bpmIntervals) and requires 44100 Hz input:
    https://essentia.upf.edu/reference/std_RhythmExtractor2013.html
  - KeyExtractor outputs (key, scale, strength):
    https://essentia.upf.edu/reference/std_KeyExtractor.html
  - TensorflowPredictMusiCNN usage and the 16000 Hz it expects, plus the
    exact model download URLs, from Essentia's own tutorial:
    https://essentia.upf.edu/tutorial_tensorflow_auto-tagging_classification_embeddings.html

One real bug was caught in this process (see requirements.txt's own
comment): essentia and essentia-tensorflow share the same top-level
`essentia` package namespace, and installing both unconditionally meant
whichever landed on disk second silently won — always plain essentia in
practice, so TensorflowPredictMusiCNN never existed at import time even
with the model files present. Still worth sanity-checking output on a
track you know well before trusting it across a real, varied library —
a single test tone doesn't cover that — but the pipeline itself is
confirmed real and working end-to-end.
"""

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import List, Optional

from fastapi import FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel

logger = logging.getLogger("omnis_essentia")

MODELS_DIR = Path(__file__).parent / "models"
MUSICNN_GRAPH = MODELS_DIR / "msd-musicnn-1.pb"
MUSICNN_METADATA = MODELS_DIR / "msd-musicnn-1.json"

# Curated set of words that read as a mood rather than a genre, used to
# pick a single `mood` field out of the MusiCNN tag list — the exact same
# heuristic and rationale as _moodWords in
# lib/plugins/metadata_enrichment_plugin.dart, kept in sync deliberately
# so "mood" means the same thing everywhere in the app. MusiCNN's MSD
# vocabulary is folksonomy tags too, same caveat as Last.fm's.
MOOD_WORDS = {
    "chillout", "chill", "mellow", "beautiful", "sad", "happy", "party",
    "sexy", "easy listening", "instrumental",
}

try:
    import essentia.standard as es
    HAS_ESSENTIA = True
except ImportError:  # pragma: no cover - depends on the deployment env
    HAS_ESSENTIA = False
    logger.warning("essentia is not installed — /analyze will fail until "
                    "`pip install -r requirements.txt` succeeds.")

HAS_TENSORFLOW_MODEL = (
    HAS_ESSENTIA
    and hasattr(es, "TensorflowPredictMusiCNN")
    and MUSICNN_GRAPH.exists()
    and MUSICNN_METADATA.exists()
)
if HAS_ESSENTIA and not HAS_TENSORFLOW_MODEL:
    logger.warning(
        "TensorflowPredictMusiCNN or the msd-musicnn model files are not "
        "available — BPM/key will still work, but mood/genres will "
        "always come back empty. Run download_models.sh and install "
        "essentia-tensorflow to enable them."
    )

app = FastAPI(title="Omnis Essentia Service")


class AnalysisResponse(BaseModel):
    bpm: Optional[float] = None
    key: Optional[str] = None
    scale: Optional[str] = None
    mood: Optional[str] = None
    genres: List[str] = []


@app.get("/health")
def health():
    return {
        "essentia": HAS_ESSENTIA,
        "tagging_model": HAS_TENSORFLOW_MODEL,
    }


@app.post("/analyze", response_model=AnalysisResponse)
async def analyze(audio: UploadFile = File(...)):
    if not HAS_ESSENTIA:
        raise HTTPException(
            status_code=503,
            detail="essentia is not installed on this service.",
        )

    suffix = Path(audio.filename or "upload").suffix or ".audio"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await audio.read())
        tmp_path = tmp.name

    try:
        bpm, key, scale = _analyze_rhythm_and_key(tmp_path)
        mood, genres = _analyze_tags(tmp_path) if HAS_TENSORFLOW_MODEL else (None, [])
        return AnalysisResponse(bpm=bpm, key=key, scale=scale, mood=mood, genres=genres)
    except Exception:
        logger.exception("Analysis failed for %s", audio.filename)
        raise HTTPException(status_code=500, detail="Analysis failed.")
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def _analyze_rhythm_and_key(path: str):
    """BPM via RhythmExtractor2013, key/scale via KeyExtractor. Both are
    plain DSP algorithms (no ML model), so this always works once
    essentia itself is installed. RhythmExtractor2013 requires 44100 Hz
    input — see the module docstring for the doc reference.
    """
    audio = es.MonoLoader(filename=path, sampleRate=44100)()

    rhythm_extractor = es.RhythmExtractor2013(method="multifeature")
    bpm, _ticks, _confidence, _estimates, _bpm_intervals = rhythm_extractor(audio)

    key_extractor = es.KeyExtractor()
    key, scale, _strength = key_extractor(audio)

    return float(bpm), str(key), str(scale)


def _analyze_tags(path: str):
    """Mood/genre tags via MusiCNN auto-tagging. Loads audio again at
    16000 Hz — MusiCNN was trained at that rate, and it's different from
    the 44100 Hz RhythmExtractor2013 needs, so this cannot reuse the same
    loaded buffer.
    """
    audio = es.MonoLoader(filename=path, sampleRate=16000)()

    model = es.TensorflowPredictMusiCNN(graphFilename=str(MUSICNN_GRAPH))
    activations = model(audio)  # shape: [time, num_classes]

    with open(MUSICNN_METADATA, "r") as f:
        metadata = json.load(f)
    classes = metadata["classes"]

    # Average over time to get one confidence score per tag for the whole
    # track, matching the tutorial's approach for a single-label summary.
    mean_activations = activations.mean(axis=0)
    ranked = sorted(
        zip(classes, mean_activations), key=lambda pair: pair[1], reverse=True
    )

    top_tags = [name for name, score in ranked[:5] if score > 0.1]
    mood = next(
        (tag for tag in top_tags if tag.lower() in MOOD_WORDS),
        None,
    )
    return mood, top_tags
