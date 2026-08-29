# W2D3 — Containerise

## Part 1 — Containerise

### Docker Image

The service was containerised with `python:3.11-slim`. The Dockerfile copies
and installs the requirements before copying the application code so that
Docker can reuse the dependency layer when only application code changes.
Package installation uses `--no-cache-dir`, and PyTorch is installed from the
CPU wheel index.

The service runs as the non-root `app` user. `HF_HOME` is configured as
`/home/app/.cache/huggingface`; this cache directory is created during the
build and assigned to `app`, allowing the mounted named volume to remain
writable. Uvicorn listens on `0.0.0.0:8000`.

The resulting image started successfully and served both `GET /health` and
`POST /v1/chat/completions`.

![Successful local container and API requests](images/w2d3-container-local-pass.png)

### Model Cache Volume

The container was run with a named Hugging Face cache volume:

```bash
docker run -d --name serving -p 8000:8000 \
  -v hf-cache:/home/app/.cache/huggingface \
  lamai7/aidc-serving:cpu-v1
```

The running service successfully answered:

- `GET /health`
- `POST /v1/chat/completions`

The container was then removed and recreated using the same `hf-cache` named
volume. The second startup reused the cached model and did not download it
again.

![Hugging Face named-volume cache reuse](images/w2d3-hf-cache-reuse.png)

### Naive vs Slim Measurement

| stage                               |         image size |
| ----------------------------------- | -----------------: |
| naive build (full base, cached pip) |            17.9 GB |
| slim CPU build                      |            2.98 GB |
| measured reduction                  | 14.92 GB (\~83.4%) |

The measured gap was unusually large because the naive build installed
PyTorch from the default package source and included CUDA/Triton-related
dependencies. The final Dockerfile explicitly used the PyTorch CPU wheel
index. Its other slimming choices were `python:3.11-slim`, pip's
`--no-cache-dir`, and `.dockerignore`.

![Naive and slim Docker image sizes](images/w2d3-naive-vs-slim.png)

### Docker Hub

The final image was pushed successfully as:

```text
lamai7/aidc-serving:cpu-v1
```

The completed push returned a `sha256` digest.

![Successful Docker Hub push and digest](images/w2d3-dockerhub-push.png)

### Verification

Final verification used:

```bash
IMAGE=lamai7/aidc-serving:cpu-v1 ./verify.sh
```

The important verifier output was:

```text
pulling lamai7/aidc-serving:cpu-v1 ...
health: 200
completion: ok
GREEN CHECK: PASS
```

The verifier performed a fresh registry pull. This proves that the published
image works, rather than verifying only the locally built copy.

![Published image green check](images/w2d3-green-check-pass.png)
