# docker-breeze-tts

Purpose-built CUDA 13 / PyTorch image for the official Breeze-TTS-2 streaming
server. Native Linux ARM64 (including NVIDIA GB10, compute capability 12.1)
and AMD64 builds replace a roughly 39 GB SGLang-based image. No SGLang, vLLM,
FlashAttention, CUDA compiler, model weights, shell, or package manager are included.
The final runtime is **Google Distroless `cc-debian13:nonroot`**, with the
Python 3.13 interpreter/standard library and required audio ELF dependencies
copied from a matching `python:3.13-slim-trixie` build environment.

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

Default entrypoint is `/opt/venv/bin/python -m breeze_infer.api`; the default
arguments are `/model --host 0.0.0.0 --port 7860` (unchanged upstream API).
To override arguments, append them after the image name. There is no shell.
The equivalent full command is:

```sh
python -m breeze_infer.api /model --host 0.0.0.0 --port 7860
```

To join an existing llama-swap deployment, add `--network llama-backend` and
the desired `--name`; this repository does not modify deployment configs.
The service has no built-in authentication; keep it private or use an
authenticated reverse proxy.

### Security caveat for preserved compatibility pins

At migration time, Dependabot reports four high and two moderate advisories in
the preserved Transformers/Accelerate versions. They concern model-loading,
checkpoint paths, saving/training paths, and custom code. These pins are retained
to avoid an unvalidated upstream/model dependency migration, **not** because
they are free of vulnerabilities. Review the repository's Security/Dependabot
alerts before deploying. Only mount trusted, verified checkpoints; never let
API clients choose model paths or supply checkpoints. Consider adding
`-e HF_HUB_OFFLINE=1 -e TRANSFORMERS_OFFLINE=1` at runtime to enforce local
loading. Offline mode does not fix unsafe local checkpoint contents. Dependency
updates need upstream compatibility and GPU synthesis validation.

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
- Debian 13 / Python 3.13, virtual environment at `/opt/venv`. PyTorch's
  official CUDA wheels supply runtime libraries, without a devel/toolkit image.
- Reviewed Dependabot bumps update **torch to 2.14.1+cu130** and **NumPy to
  2.5.2**; the earlier GPU-validated image used Torch 2.13.0 and NumPy 2.3.5.
  Preserves **torchaudio 2.11.0+cu130**, **transformers 4.57.3**,
  **accelerate 1.12.0**, **qwen-tts 0.1.1**. Remaining direct inference
  dependencies are explicitly pinned in `requirements*.txt` to the installed
  versions from that image except the reviewed NumPy bump; Dependabot can
  propose further upgrades. Torch 2.14.1 is not GPU-validated here.
- CPU checks inspect the wheel's compiled `sm_120` target (the earlier image
  reports the same target list). This is not an on-device sm_121 validation.
- The different Torch/Torchaudio versions are an intentional compatibility
  exception: no matching Torchaudio 2.14 CUDA wheel was available when migrating.
  The downloaded Torchaudio 2.11 CUDA wheel declares no Torch requirement in
  its dependency metadata, so version differences do not break requirement checks.
  Torchaudio and Qwen are installed with `--no-deps`, with **all dependencies
  declared explicitly**. Every unsatisfied dependency requirement fails CI.
  Python 3.13's bundled pip reports the ARM64 cuSPARSELt 0.8.1 wheel as
  unsupported after successfully installing its ARM64 wheel (an internal wheel
  platform-tag defect); CI validates requirements directly with packaging and
  tests actual Torch imports/operators rather than suppressing dependency errors.
  This is not
  a generally supported upstream Torch/Torchaudio pairing. CPU import/resampling
  tests and previous image inference are evidence, not proof of all native
  operator compatibility.
- Uses upstream **bfloat16 / eager attention**; no model, attention, or upstream
  source changes. SGLang's conflicting `kernels` package is never installed.
- Multi-stage build keeps Git, tests, pip, shells, package managers, development
  tooling, and upstream assets out of the final image. `assemble_runtime.py`
  collects Python and transitive ELF dependencies for FFmpeg, SoX (including
  format plugins), libsndfile, and libgomp; no Ubuntu/CUDA base is disguised as
  Distroless. Exec-form tests run in the actual shell-free runtime and force
  CPU checks before publication. The inherited Distroless user is overridden
  to UID/GID 1000, with owned writable cache directories.

## Validation status

The earlier SGLang-based image passed GB10 GPU inference and produced non-silent
24 kHz PCM through llama-swap. **The replacement image has not been GPU tested.**
Every native architecture build runs runtime imports, CPU bfloat16 matrix
multiplication, Torchaudio CPU resampling, dependency metadata checks, writable
cache/nonroot checks, audio binary execution, absence of shells/installers,
and selected upstream API/disconnect/attention/runtime
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

Published tags: `current`, `current-arm64`, `current-amd64`,
`sha-<full git SHA>` (first successful build only),
`sha-<full git SHA>-run-<run ID>-<attempt>`, and per-architecture run tags
with `-arm64` / `-amd64` suffixes. Scheduled/manual rebuilds update `current`
and create unique run tags without replacing the first SHA tag. Pin a manifest
digest for strict immutable deployments. Dependabot checks Docker, Python, and Actions
weekly; review upgrades carefully, especially the compatibility pins above.
All five initial Dependabot PRs were reviewed: Torch/NumPy and the setup-uv /
CodeQL Actions upgrades were incorporated; the Ubuntu 26.04 bump was superseded
by the Debian 13 builder required for the requested Distroless runtime.

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
