# Python 3.7: the newest interpreter essentia-tensorflow's prebuilt Linux
# wheel supports per Essentia's own docs (their tutorial states Python
# 3.5-3.7 for the pip-installable TensorFlow build). Plain `essentia`
# (BPM/key only, no TensorFlow) also runs fine on 3.7 if you'd rather skip
# the TensorFlow install entirely — see requirements.txt.
FROM python:3.7-slim

WORKDIR /app

# ffmpeg widens the set of audio formats MonoLoader can decode beyond
# libsndfile's built-in set (e.g. some mp3/m4a variants).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY download_models.sh .
RUN chmod +x download_models.sh
# Best-effort at build time: mood/genre tagging is optional, so a failed
# or skipped download (no network in this build environment, or the user
# only wants BPM/key) must not fail the whole image build.
RUN ./download_models.sh || echo "Continuing without tagging models."

EXPOSE 8686
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8686"]
