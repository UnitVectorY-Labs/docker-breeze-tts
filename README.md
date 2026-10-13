# docker-breeze-tts

Purpose-built CUDA 13 / PyTorch image for the official Breeze-TTS-2 streaming
server. Native Linux ARM64 (including NVIDIA GB10, compute capability 12.1)
and AMD64 builds replace a roughly 39 GB SGLang-based image. No SGLang, vLLM,
FlashAttention, CUDA compiler, or model weights are included.

## Run

Download `BreezeBlue/Breeze-TTS-2` separately in accordance with its model
license. The directory must include the checkpoint, tokenizer/configuration
files, and `audio_tokenizer/`. Nothing downloads weights during the build.

```sh
docker run --rm --gpus all --user 1000:1000 \
  -p 127.0.0.1:7860:7860 \
  -v /absolute/path/to/breeze-tts-2:/model:ro \
  ghcr.io/unitvectory-labs/docker-breeze-tts:current
```

Requires the NVIDIA Container Toolkit and a host driver compatible with CUDA
13.0. `/model` must be readable by UID/GID 1000. The image runs nonroot by
default, with writable caches under `/home/tts/.cache` and temporary uploads
under `/tmp`. For a read-only root filesystem, supply writable mounts for
both directories. It is not necessary to mount a Hugging Face cache for this
fully local checkpoint. Optional persistent cache:
`-v /absolute/writable/cache:/home/tts/.cache` (owned by 1000:1000).

Default command (unchanged upstream API):

```sh
python -m breeze_infer.api /model --host 0.0.0.0 --port 7860
```

To join an existing llama-swap deployment, add `--network llama-backend` and
the desired `--name`; this repository does not modify deployment configs.
The service has no built-in authentication; keep it private or use an
authenticated reverse proxy.

## API

`GET /health` returns 200 after initialization (503 if the handler is reached
before runtime initialization). Uvicorn may not accept connections during
startup; health checks can therefore also see connection refusal while loading.

`POST /v1/audio/speech` accepts **multipart**, not OpenAI JSON:
required `text`; optional `instruction`, `cfg_scale` (default 1.0), `seed`
(default 42), and paired `ref_audio` + `ref_text` for voice cloning.
It streams raw mono **24 kHz signed 16-bit little-endian PCM**, not WAV.
Responses carry `X-Sample-Rate` and `X-Sample-Format` headers. Only one request
runs at a time; concurrent requests receive 409.

```sh
curl --fail -F 'text=Hello from Breeze.' \
  -F 'instruction=A clear English voice.' \
  http://127.0.0.1:7860/v1/audio/speech -o breeze.pcm
ffplay -f s16le -ar 24000 -ac 1 breeze.pcm
```

## Compatibility and implementation

- Unmodified upstream code pinned to
  `58ec70ce5fa4cc361bdebf77ec40d1365da00ab2` from
  [breezeblue-ai/breeze-tts](https://github.com/breezeblue-ai/breeze-tts).
- Ubuntu 24.04 / Python 3.12, virtual environment at `/opt/venv`. PyTorch's
  official CUDA wheels supply runtime libraries, without a devel/toolkit image.
- Preserves the actual installed versions inspected in the earlier GB10 image:
  **torch 2.13.0+cu130**, **torchaudio 2.11.0+cu130**, **transformers 4.57.3**,
  **accelerate 1.12.0**, **qwen-tts 0.1.1**. Remaining direct inference
  dependencies are explicitly pinned in `requirements*.txt` to the installed
  versions from that image; Dependabot can propose upgrades.
- CPU checks inspect the wheel's compiled `sm_120` target (the earlier image
  reports the same target list). This is not an on-device sm_121 validation.
- The inherited Torch/Torchaudio combination is an intentional compatibility
  exception: Torchaudio metadata requires Torch 2.11.0, and no Torchaudio 2.13
  CUDA wheel was available when migrating. It is installed with `--no-deps`;
  Qwen is likewise installed without resolution, with **all its dependencies
  declared explicitly**. `pip check` has exactly this one accepted mismatch;
  tests fail on any additional mismatch. This is not a generally supported
  upstream Torch/Torchaudio pairing. CPU import/resampling tests and previous
  image inference are evidence, not proof of all native operator compatibility.
- Uses upstream **bfloat16 / eager attention**; no model, attention, or upstream
  source changes. SGLang's conflicting `kernels` package is never installed.
- Multi-stage build keeps Git, tests, development tooling, and upstream assets
  out of the final image. A final-stage dependency forces CPU checks before
  publication. Runtime still includes FFmpeg, SoX, and libsndfile for audio.

## Validation status

The earlier SGLang-based image passed GB10 GPU inference and produced non-silent
24 kHz PCM through llama-swap. **The replacement image has not been GPU tested.**
Every native architecture build runs runtime imports, CPU bfloat16 matrix
multiplication, Torchaudio CPU resampling, dependency metadata checks, writable
cache/nonroot checks, and selected upstream API/disconnect/attention/runtime
tests offline, without models. Successful publication establishes those CPU
checks only. Run a real health + synthesis test on GB10 before replacing a
production deployment; do not assume import tests establish sm_121 execution.

## Builds and maintenance

GitHub Actions builds on native `ubuntu-24.04-arm` and `ubuntu-24.04` runners;
no emulation. Pushes affecting Dockerfile, requirements, tests, `.dockerignore`,
or the build workflow trigger builds. Manual `workflow_dispatch` and weekly
Saturday **02:00 UTC** builds are enabled. PRs build/test but never publish.
Actions are pinned by commit SHA. OCI source/revision/license labels link the
package to this repository.

Published tags: `current`, `sha-<full git SHA>` (first successful build only),
`sha-<full git SHA>-run-<run ID>-<attempt>`, and per-architecture run tags
with `-arm64` / `-amd64` suffixes. Scheduled/manual rebuilds update `current`
and create unique run tags without replacing the first SHA tag. Pin a manifest
digest for strict immutable deployments. Dependabot checks Docker, Python, and Actions
weekly; review upgrades carefully, especially the compatibility pins above.

```sh
docker build -t breeze-tts:local .
gh workflow run docker-build.yml --repo UnitVectorY-Labs/docker-breeze-tts
```

The public source repository does not automatically make a newly created GHCR
package public. If anonymous pulls are denied, an organization package admin
must set package visibility to public; no CLI auth scopes need changing.

## License

Container packaging: MIT (`LICENSE`). Upstream code retains its Apache-2.0
license at `/opt/breeze-infer/LICENSE`. Dependencies retain their own licenses;
model weights are external and subject to their model license.
