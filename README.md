# serving-stack

The one system this course builds. Your team creates this repository once from
the template, and every lab from week 2 to graduation is a change to it. There
is no week where you start again.

## What is here

```
app/        empty. Your service goes here, starting week 2 day 2
docs/       the API contract the Agentic AI cohort integrates against
scripts/    verify-env.sh, which checks your machine against what the labs need
PINS.md     every version this course depends on
setup.md    how to work in this repository
```

That is the whole repository, and the shortness of that list is the point. You
are not given a finished system to read. You build one, a day at a time, and by
week 6 another cohort's agents are calling it.

## What you add, and when

| Week | Day | What you add |
|---|---|---|
| 2 | Mon | `app/` behind an OpenAI-compatible `/v1` on CPU |
| 2 | Tue | `Dockerfile`, and your image on Docker Hub |
| 2 | Wed | `Dockerfile.gpu`, the same code on a GPU |
| 2 | Thu | `compose.yaml`, the stack described rather than run by hand |
| 3 | Thu | `bench/`, the harness that measures all of it |

Each one is a lab, and each one starts from files that day hands you. Lab
instructions, decks and quizzes are on the course Drive, one folder per week.
This repository is your code.

## Start here

```bash
./scripts/verify-env.sh     # checks your machine, writes verify-env-report.json
```

Then read `setup.md`. It is short, and it covers the two things that go wrong:
committing a key, and committing a model.

## W2D1: First Contact with GPU Memory

This lab measures the GPU memory usage and generation throughput of
`Qwen/Qwen2.5-1.5B-Instruct` on an NVIDIA T4 at three numerical precisions.
The measurements were collected in Google Colab and compared with estimates
from the formula:

> Model weight memory ≈ number of parameters × bytes per parameter

### Prediction (before running the notebook)

For a 1.5-billion-parameter model, my weight-memory predictions were:

- **fp16:** 1.5B × 2 bytes = **3.0 GB**
- **int8:** 1.5B × 1 byte = **1.5 GB**
- **int4:** 1.5B × 0.5 bytes = **0.75 GB**
- **Runtime overhead:** approximately **1–2 GB** in addition to the weights
- **fp32 on a 15 GB T4:** **Yes.** The weights should occupy about 6 GB, so
  the model should fit before accounting for larger contexts and runtime
  allocations.

### Results

| dtype | predicted GB | measured GB | observed bytes/param | tokens/s |
| --- | ---: | ---: | ---: | ---: |
| fp16 | 3.00 | 3.29 | 2.19 | 28.9 |
| int8 | 1.50 | 1.87 | 1.25 | 5.1 |
| int4 | 0.75 | 1.24 | 0.83 | 11.7 |

Observed bytes per parameter was calculated as measured resident GPU bytes
divided by 1.5 billion parameters.

### Observations

The measured values are higher than the weights-only predictions because
resident GPU memory also includes the CUDA context, allocator reservations,
model buffers, and tensors that remain at higher precision. This fixed overhead
has a proportionally larger effect on the quantized models, which is why the
observed bytes per parameter are above the theoretical 1 byte for int8 and
0.5 bytes for int4.

Quantization reduced memory usage but did not improve generation speed in this
experiment. fp16 was fastest at 28.9 tokens/s. int8 was slowest at 5.1 tokens/s,
while int4 reached 11.7 tokens/s. This ordering is expected on the T4 because
the bitsandbytes int8 and int4 paths use different kernels and perform
dequantization during generation.

The machine-readable measurements are stored in `results.json`, and the
benchmark implementation is stored in `generate.py`. The complete illustrated
lab report is available in [`artifacts/w2d1/README.md`](artifacts/w2d1/README.md).
