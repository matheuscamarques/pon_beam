# PON-BEAM Benchmarks via Docker

## Prerequisites

- Docker Engine 24+
- Docker Compose v2+

## Usage

```bash
# Full build + benchmark execution (~30 min on first run)
./docker/run_benchmarks_docker.sh

# Run benchmarks only (if image is already built)
./docker/run_benchmarks_docker.sh --quick

# Extract results from a previous run
./docker/run_benchmarks_docker.sh --extract
```

## Structure

```
docker/
├── Dockerfile                    # Multi-stage build for OTP 30 stock + PON-BEAM on Ubuntu
├── docker-compose.yml            # Orchestrates the benchmark container
└── run_benchmarks_docker.sh      # CLI entrypoint script
```

## How It Works

1. **Stage 1 (builder):** Installs build dependencies and compiles Stock OTP 30 (`/opt/erlang/30-stock`).
2. **Stage 2 (builder):** Compiles OTP 30 with `--enable-pon-beam` (`/opt/erlang/30-pon`).
3. **Stage 3 (final):** Lean runtime container with both ERTS targets + benchmark harness.
4. **Entrypoint:** Executes `run.sh`, writing results to `/pon-beam/harness/results/latest/`.
5. **Extraction:** Script copies HTML & JSON results to local `harness/results/docker/`.

## OTP Compilation Cache

Building Erlang/OTP 30 takes ~15–20 minutes. The `Dockerfile` leverages layer caching:
- If `otp/` source has not changed, Docker reuses cached ERTS binaries.
- Use `docker compose build --no-cache` to force a clean rebuild.

## Output Artifacts

```
harness/results/docker/
├── diff/
│   └── index.html       # Interactive comparative HTML report
├── baseline/             # Stock OTP benchmark JSONs
├── ponbeam/              # PON-BEAM benchmark JSONs
└── benchmark.log         # Complete execution log
```
