# syntax=docker/dockerfile:1
# PyTorch CUDA wheels provide runtime libraries; no CUDA toolkit/devel image.
FROM ubuntu:24.04 AS builder
ARG BREEZE_REF=58ec70ce5fa4cc361bdebf77ec40d1365da00ab2
ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git python3 python3-venv libgomp1 libsndfile1 sox libsox-fmt-all ffmpeg \
    && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
COPY requirements*.txt /opt/requirements/
RUN pip install -r /opt/requirements/requirements-torch.txt \
    && pip install -r /opt/requirements/requirements.txt \
    && pip install --no-deps -r /opt/requirements/requirements-audio.txt \
    && pip install --no-deps -r /opt/requirements/requirements-qwen.txt
RUN git init /opt/breeze-infer \
    && git -C /opt/breeze-infer remote add origin https://github.com/breezeblue-ai/breeze-tts.git \
    && git -C /opt/breeze-infer fetch --depth 1 origin "${BREEZE_REF}" \
    && git -C /opt/breeze-infer checkout --detach FETCH_HEAD \
    && test "$(git -C /opt/breeze-infer rev-parse HEAD)" = "${BREEZE_REF}"

FROM ubuntu:24.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 TOKENIZERS_PARALLELISM=false \
    HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_DISABLE_PROGRESS_BARS=1 \
    HOME=/home/tts XDG_CACHE_HOME=/home/tts/.cache \
    HF_HOME=/home/tts/.cache/huggingface \
    NUMBA_CACHE_DIR=/home/tts/.cache/numba
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates python3 libgomp1 libsndfile1 sox libsox-fmt-all ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && if getent passwd 1000 >/dev/null; then \
         usermod --login tts --home /home/tts "$(getent passwd 1000 | cut -d: -f1)"; \
       else useradd --uid 1000 --user-group --home-dir /home/tts tts; fi \
    && mkdir -p /home/tts/.cache/huggingface /home/tts/.cache/numba \
    && chown -R 1000:1000 /home/tts
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/breeze-infer/breeze_infer /opt/breeze-infer/breeze_infer
COPY --from=builder /opt/breeze-infer/models /opt/breeze-infer/models
COPY --from=builder /opt/breeze-infer/configs /opt/breeze-infer/configs
COPY --from=builder /opt/breeze-infer/LICENSE /opt/breeze-infer/LICENSE
WORKDIR /opt/breeze-infer
USER 1000:1000
EXPOSE 7860
HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7860/health', timeout=4)"
CMD ["python", "-m", "breeze_infer.api", "/model", "--host", "0.0.0.0", "--port", "7860"]

# Gate publication on CPU-only checks against the actual minimal runtime.
FROM runtime AS test
USER root
COPY requirements-test.txt /opt/requirements-test.txt
RUN pip install -r /opt/requirements-test.txt
COPY --from=builder /opt/breeze-infer/tests /opt/breeze-infer/tests
COPY --from=builder /opt/breeze-infer/infer.py /opt/breeze-infer/infer.py
COPY tests /opt/image-tests
USER 1000:1000
RUN HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python -m pytest -q -p no:cacheprovider \
    /opt/image-tests /opt/breeze-infer/tests/test_api.py \
    /opt/breeze-infer/tests/test_api_disconnect.py \
    /opt/breeze-infer/tests/test_attention_config.py \
    /opt/breeze-infer/tests/test_runtime.py \
    /opt/breeze-infer/tests/test_runtime_flags.py \
    /opt/breeze-infer/tests/test_logits_process.py \
    && touch /tmp/cpu-tests-passed

FROM runtime AS final
COPY --from=test /tmp/cpu-tests-passed /opt/cpu-tests-passed
