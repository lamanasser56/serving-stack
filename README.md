# serving-stack

The one system this course builds. Your team creates this repository once from
the template, and every lab from week 2 to graduation is a change to it. There
is no week where you start again.

## What is here

```text
app/        the FastAPI model-serving application and OpenAI-compatible API
docs/       the API contract the Agentic AI cohort integrates against
scripts/    verify-env.sh, which checks your machine against what the labs need
PINS.md     every version this course depends on
setup.md    how to work in this repository
```

The repository began with a deliberately small structure. The serving system
is added one lab at a time, and by week 6 another cohort's agents will be
calling it.

## What you add, and when

| Week | Day | What you add |
| --- | --- | --- |
| 2 | Mon | `app/` behind an OpenAI-compatible `/v1` on CPU |
| 2 | Tue | `Dockerfile`, and your image on Docker Hub |
| 2 | Wed | `Dockerfile.gpu`, the same code on a GPU |
| 2 | Thu | `compose.yaml`, the stack described rather than run by hand |
| 3 | Thu | `bench/`, the harness that measures all of it |

Each one is a lab, and each one starts from files that day hands you. Lab
instructions, decks, and quizzes are on the course Drive, one folder per week.
This repository is your code.

## Start here

```bash
./scripts/verify-env.sh     # checks your machine, writes verify-env-report.json
```

Then read `setup.md`. It is short, and it covers the two things that go wrong:
committing a key, and committing a model.

# Implementation Progress

## W2D1

W2D1 profiled `Qwen/Qwen2.5-1.5B-Instruct` on an NVIDIA T4 at fp16, int8,
and int4 precision. The work compared predicted weight memory with resident
VRAM, measured generation throughput, and observed context-length memory
growth. The benchmark implementation is in `generate.py`, with machine-readable
measurements in `results.json`.

| Precision | Measured VRAM | Throughput |
| --- | ---: | ---: |
| fp16 | 3.29 GB | 28.9 tokens/s |
| int8 | 1.87 GB | 5.1 tokens/s |
| int4 | 1.24 GB | 11.7 tokens/s |

The results verified that quantisation reduced memory but did not improve
generation speed on this T4. Detailed evidence is in
[`artifacts/w2d1/`](artifacts/w2d1/README.md).

## W2D2

W2D2 implemented a CPU-only FastAPI service for
`Qwen/Qwen2.5-0.5B-Instruct` with:

- `GET /health`
- `GET /v1/models`
- Non-streaming `POST /v1/chat/completions`
- OpenAI-compatible response shapes and token accounting

The standard OpenAI Python client worked by changing only its `base_url`. The
API verifier returned `GREEN CHECK: PASS` with a valid completion and usage of
35 prompt tokens, 3 completion tokens, and 38 total tokens.

Contract hardening and fuzzing exercised 12 cases: ten invalid requests
correctly returned HTTP 422 and two unusual valid requests returned HTTP 200.
All 12 passed. A compatibility lab also reproduced a failure with Transformers
5.16.1, diagnosed `apply_chat_template` returning `BatchEncoding`, and fixed
the service by using `return_dict=True` and reading
`encoded["input_ids"]`—without downgrading. The verifier and OpenAI client both
passed after the fix.

Detailed API, fuzzing, and compatibility evidence is in
[`artifacts/w2d2/`](artifacts/w2d2/README.md).

## W2D3

### Containerisation

The serving application was packaged in a CPU-focused `python:3.11-slim`
image. Requirements are installed before application code to preserve the
dependency cache layer. The build uses pip's `--no-cache-dir` and the PyTorch
CPU wheel source, then runs the service as the non-root `app` user.

Model weights remain outside the image in a named Hugging Face cache volume at
`/home/app/.cache/huggingface`. Local container tests passed for `/health` and
`/v1/chat/completions`, and recreating the container reused the mounted cache.

| Build | Image size |
| --- | ---: |
| Naive image | 17.9 GB |
| Slim CPU image | 2.98 GB |
| Reduction | 14.92 GB (~83.4%) |

The final image was published as `lamai7/aidc-serving:cpu-v1`. A verifier
removed the local copy, pulled the published image fresh, checked health and a
real completion, and ended with `GREEN CHECK: PASS`.

See [`artifacts/w2d3/README.md`](artifacts/w2d3/README.md) for the detailed
container evidence.

### Multi-stage Build Golf

A standalone lightweight registry service was created under
`w2d3-multistage/`. The multi-stage build copies only runtime dependencies,
`main.py`, and `registry.json` into the final image.

| Measurement | Naive | Multi-stage | Saving |
| --- | ---: | ---: | ---: |
| Docker-reported disk usage | 349 MB | 237 MB | 112 MB (32.1%) |
| Final verifier measurement | 87.6 MB | 56.8 MB | 30.8 MB (35.2%) |

The two size pairs come from different Docker size measurements and display
metrics. Both demonstrate the same reduction. The multi-stage image remained
below the 300 MB target, retained the required registry endpoints, saved more
than 20%, and finished with `GREEN CHECK: PASS`.

### Docker Layer Cache Bug Lab

The broken Dockerfile placed `COPY . .` before `pip install`, so a comment-only
code edit invalidated the source layer and the following dependency layer. The
fix copied `requirements.txt` first, installed dependencies, and copied the
application afterward.

After the correction, the pip-install step showed `Using cache`, and the
measured code-only rebuild completed in **1.917 seconds**. The optional
`.dockerignore` stretch is not claimed as part of this bug lab.

## Current State

At the end of W2D3, the repository contains:

- A FastAPI serving application with local CPU inference.
- An OpenAI-compatible `/v1` API and validated request/response contract.
- A CPU Docker image with an external Hugging Face model cache.
- A published Docker Hub image with fresh-pull verification.
- API, fuzzing, image, and registry verification tooling.
- A lightweight multi-stage registry experiment.
- A reproduced and corrected Docker layer-cache ordering bug.

## Progress Status

| Stage | Status |
| ----- | --------- |
| W2D1 | Completed |
| W2D2 | Completed |
| W2D3 | Completed |
| W2D4 | Next |
| W2D5 | Next |

W2D4 and W2D5 are the next stages. This README will be extended after those
labs are completed.
