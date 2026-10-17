# syntax=docker/dockerfile:1
FROM python:3.14-slim-trixie AS builder
ARG BREEZE_REF=58ec70ce5fa4cc361bdebf77ec40d1365da00ab2
ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends \
    git libgomp1 libsndfile1 sox libsox-fmt-all ffmpeg \
    && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
COPY requirements*.txt /opt/requirements/
RUN pip install -r /opt/requirements/requirements-torch.txt \
    && pip install -r /opt/requirements/requirements.txt \
    && pip install --no-deps -r /opt/requirements/requirements-audio.txt \
    && pip install --no-deps -r /opt/requirements/requirements-qwen.txt \
    && pip install --target /opt/test-deps -r /opt/requirements/requirements-test.txt
RUN git init /opt/breeze-infer \
    && git -C /opt/breeze-infer remote add origin https://github.com/breezeblue-ai/breeze-tts.git \
    && git -C /opt/breeze-infer fetch --depth 1 origin "${BREEZE_REF}" \
    && git -C /opt/breeze-infer checkout --detach FETCH_HEAD \
    && test "$(git -C /opt/breeze-infer rev-parse HEAD)" = "${BREEZE_REF}"
COPY assemble_runtime.py /opt/assemble_runtime.py
RUN python /opt/assemble_runtime.py

FROM gcr.io/distroless/cc-debian13:nonroot AS runtime
ENV PATH="/opt/venv/bin:/usr/local/bin:/usr/bin" \
    LD_LIBRARY_PATH=/usr/local/lib \
    PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    TOKENIZERS_PARALLELISM=false \
    HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_DISABLE_PROGRESS_BARS=1 \
    HOME=/home/tts XDG_CACHE_HOME=/home/tts/.cache \
    HF_HOME=/home/tts/.cache/huggingface \
    NUMBA_CACHE_DIR=/home/tts/.cache/numba
ENV TORCH_PYTHON_NATIVE_USER_GRAPH_ORDER_FN=runtime_policy.aten_cuda_only
COPY --from=builder /opt/runtime-root/ /
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/breeze-infer/breeze_infer /opt/breeze-infer/breeze_infer
COPY --from=builder /opt/breeze-infer/models /opt/breeze-infer/models
COPY --from=builder /opt/breeze-infer/configs /opt/breeze-infer/configs
COPY --from=builder /opt/breeze-infer/LICENSE /opt/breeze-infer/LICENSE
COPY runtime_policy.py /opt/breeze-infer/runtime_policy.py
WORKDIR /opt/breeze-infer
USER 1000:1000
EXPOSE 7860
ENTRYPOINT ["/opt/venv/bin/python", "-m", "breeze_infer.api"]
CMD ["/model", "--host", "0.0.0.0", "--port", "7860"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
    CMD ["/opt/venv/bin/python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7860/health', timeout=4)"]

# Run all CPU tests in the actual shell-free final runtime.
FROM runtime AS validated
COPY --from=builder /opt/test-deps /opt/test-deps
COPY --from=builder /opt/breeze-infer/tests /opt/breeze-infer/tests
COPY --from=builder /opt/breeze-infer/infer.py /opt/breeze-infer/infer.py
COPY tests /opt/image-tests
ENV PYTHONPATH=/opt/test-deps HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
RUN ["/opt/venv/bin/python", "-m", "pytest", "-q", "-p", "no:cacheprovider", "/opt/image-tests", "/opt/breeze-infer/tests/test_api.py", "/opt/breeze-infer/tests/test_api_disconnect.py", "/opt/breeze-infer/tests/test_attention_config.py", "/opt/breeze-infer/tests/test_runtime.py", "/opt/breeze-infer/tests/test_runtime_flags.py", "/opt/breeze-infer/tests/test_logits_process.py"]
RUN ["/opt/venv/bin/python", "-c", "from pathlib import Path; Path('/tmp/cpu-tests-passed').touch()"]

FROM runtime AS final
COPY --from=validated /tmp/cpu-tests-passed /opt/cpu-tests-passed
