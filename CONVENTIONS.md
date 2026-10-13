# TTS repository conventions

Prepared 2026-10-13. This directory is a shared reference, not a deployment.
Do not modify `/home/jared/Documents/llm` or the reference repository.

## Exact reference files

Source: https://github.com/UnitVectorY-Labs/docker-llama.cpp-cuda/tree/d8532f61b3f1bf0386e0356182de2544cb102b9f

The following files were downloaded byte-for-byte using `gh api` at that commit:

- `.github/workflows/add-to-project.yml`
- `.github/workflows/chromadb-repo-indexer.yml`
- `.github/workflows/semgrep.yml`
- `.github/workflows/zizmor.yml`
- `.github/dependabot.yml` (original Docker + Actions example)
- `LICENSE` (MIT, copyright 2026 UnitVectorY Labs)

All workflow `uses:` references are full commit SHAs; Semgrep's container is
digest-pinned. The zizmor executable itself is not pinned (`uvx zizmor`).
Copy these standard files into replacement repositories as appropriate; keep
these reference copies unchanged. `dependabot-tts.example.yml` is an adapted
Docker + Actions + pip example, not a verbatim upstream file.

## Container and publication

- Name: `UnitVectorY-Labs/docker-<tts-engine>-cuda`; publish the lowercase matching
  package at `ghcr.io/unitvectory-labs/docker-<tts-engine>-cuda`.
- Native matrix: `linux/amd64` on `ubuntu-24.04`, `linux/arm64` on
  `ubuntu-24.04-arm`. No QEMU. Verify engine/PyTorch/CUDA/audio dependencies on
  each architecture; explicitly document any unsupported architecture.
- Use non-root UID/GID `1000:1000`, writable HOME/cache, persisted HF cache,
  explicit server bind/port, exec-form entrypoint, and no baked-in model secrets.
- Build/test each architecture; assemble the multi-arch manifest only after all
  required builds succeed. Prefer per-job image digests over mutable arch tags.
- Publish mutable `current` for the latest successful build and immutable
  `sha-<full-repository-commit>` for a fixed build. A SHA tag is not enforced
  immutable by GHCR: never overwrite it. For scheduled/manual rebuilds at the
  same source SHA, use `sha-<full-sha>-run-<run-id>-<run-attempt>` instead, or
  skip an existing immutable tag; do not silently replace its contents.
- Resolve upstream revision once per run; pin dependencies/base image digests
  when reproducibility is required. Record source/upstream revisions and OCI
  `org.opencontainers.image.source`, `.revision`, `.licenses` metadata.
- Trigger on relevant `main` pushes, weekly Saturday `0 2 * * 6` (02:00 UTC),
  and `workflow_dispatch`. Include dependency manifests, application files,
  Dockerfile, and build workflow in path filters, not just Dockerfile.
- Serialize publication with concurrency; reference matrix uses fail-fast false,
  30-minute builds, 10-minute manifest/cleanup jobs. Adjust for TTS build cost.
- Optional cleanup: delete untagged versions only, retain at least five; do not
  delete platform manifests still referenced by retained multi-arch indexes.
- README must show the actual `:current` image, tested hardware/API/audio formats,
  cache mounts and model licenses. Reference README's snapshot/dev image is stale.

## Dependabot and permissions

- Track `pip`, `docker`, and `github-actions` manifests at `/` (adjust directories
  to actual manifests). Weekly Saturday 06:00 `America/New_York`, limit 20 PRs
  per ecosystem; retain the `github/codeql-action*` group.
- Default workflow permission: `contents: read`, or `permissions: {}` where no
  checkout/API read is needed. Checkout with `persist-credentials: false`.
- Publishing/manifest/cleanup jobs: `contents: read`, `packages: write`;
  GHCR username `${{ github.actor }}`, password `${{ secrets.GITHUB_TOKEN }}`.
- Security scans: `contents: read`, `security-events: write`; zizmor also uses
  `actions: read`. Do not grant package/contents write to PR validation jobs.
- Project automation uses `PROJECT_GITHUB_ACTION`, project 41, and
  `arc-runner-set`; retain its metadata-only `pull_request_target` behavior,
  never checkout/run untrusted PR code with that credential.
- ChromaDB uses `CHROMADB_URL`, `CHROMADB_TOKEN`, `CHROMADB_MODEL` and
  `arc-runner-set`; confirm inherited org credentials/runner eligibility.
  No repository-level secrets/variables exist in the reference. Org secret
  visibility could not be verified with current CLI scopes.

## Repository settings checklist (apply only when authorized)

- Public, default branch `main`, MIT wrapper license; issues enabled; wiki,
  repository projects, discussions and Pages disabled unless needed.
- Delete merged branches; reference permits merge/squash/rebase and auto-merge.
- Enable Dependabot alerts/security updates, secret scanning and push protection.
- Prefer read-only default Actions token permissions, no PR-review approval by
  Actions, and required validation checks. These are recommendations: reference
  defaults are write and may approve PR reviews; it has no rulesets or returned
  required review/status-check requirements, but forbids force pushes/deletion.
- Reference custom properties: distribution `github-packages`, status
  `Work In Progress`, language/type `unknown`; choose accurate allowed values
  for new repositories. Reference has no topics/homepage; add useful metadata.
- Current gh account JaredHatfield is an active org owner; org permits public
  and private repo creation. No trial repository was created. Token lacks
  `read:packages` and `admin:org`; do not refresh auth/scopes without permission.

## GHCR visibility: manual administrator step required

Checked current official GitHub documentation (2026-10-13): no supported public
Packages REST endpoint changes package visibility, and no supported workflow
`GITHUB_TOKEN` visibility-changing API is documented. Do not invent a
`PATCH .../packages/...` endpoint or use private web APIs/browser automation.
`packages: write` supports publishing, not an automatic public-visibility switch.

First publication defaults to private. Linking a public repository via the OCI
source label inherits access permissions, **not visibility**. After first push,
an org owner/package administrator must use GitHub UI:

Organization -> Packages -> package -> Package settings -> Danger Zone ->
Change visibility -> Public -> confirm package name. Public packages support
anonymous pulls; GitHub warns public visibility cannot be reverted to private.
Verify anonymously afterward. Existing package visibility was not inspected
successfully because the CLI token lacks `read:packages`; no settings changed.

Official sources:
- https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility
- https://docs.github.com/en/rest/packages/packages
- https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
