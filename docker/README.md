# PON-BEAM Benchmarks via Docker

## Pr-requisitos

- Docker Engine 24+
- Docker Compose v2+

## Uso

```bash
# Build + benchmark completo (~30 min na primeira vez)
./docker/run_benchmarks_docker.sh

# S rodar benchmarks (se a imagem j foi construda)
./docker/run_benchmarks_docker.sh --quick

# Extrair resultados de uma execuo anterior
./docker/run_benchmarks_docker.sh --extract
```

## Estrutura

```
docker/
├── Dockerfile                    # Build OTP 30 stock + PON-BEAM em Ubuntu
├── docker-compose.yml            # Orquestra o container de benchmark
└── run_benchmarks_docker.sh      # Script de entrada
```

## Como funciona

1. **Estgio 1 (builder):** instala dependncias, compila OTP 30 stock (`/opt/erlang/30-stock`)
2. **Estgio 2 (builder):** compila OTP 30 com `--enable-pon-beam` (`/opt/erlang/30-pon`)
3. **Estgio 3 (final):** container enxuto (s libs de runtime) com ambos ERTS + harness
4. **Entrypoint:** executa `run.sh`, salva resultados em `/pon-beam/harness/results/latest/`
5. **Extrao:** script copia os resultados para `harness/results/docker/`

## Build OTP

O build do OTP 30 demora ~15-20 minutos. O Dockerfile usa cache de camadas:
- Se o `otp/` no mudou, o cache reutiliza os bins compilados
- Use `docker compose build --no-cache` para forar rebuild completo

## Resultados

```
harness/results/docker/
├── diff/
│   └── index.html       # Relatrio comparativo
├── baseline/             # JSONs do OTP stock
├── ponbeam/              # JSONs do PON-BEAM
└── benchmark.log         # Log completo
```
