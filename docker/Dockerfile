# PON-BEAM Benchmark Docker
# Clona OTP 30 do GitHub oficial + aplica patch PON-BEAM
#
# Uso:
#   docker build -f docker/Dockerfile -t pon-beam-bench .
#   docker run --name pon-beam-results pon-beam-bench
#   docker cp pon-beam-results:/pon-beam/harness/results/latest/. ./results/

# ============================================================
# ESTGIO 1: Build OTP 30 stock (baseline)
# ============================================================
FROM debian:bullseye-slim AS builder-stock

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential autoconf m4 libncurses-dev libssl-dev \
    unixodbc-dev git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/otp
RUN git clone --single-branch --depth 1 \
    https://github.com/erlang/otp.git . \
    && ./otp_build autoconf \
    && ./configure --prefix=/opt/erlang-baseline \
                   --without-javac --without-odbc --without-wx \
    && make -j$(nproc) \
    && make install

# ============================================================
# ESTGIO 2: Build OTP 30 com PON-BEAM
# ============================================================
FROM debian:bullseye-slim AS builder-pon

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential autoconf m4 libncurses-dev libssl-dev \
    unixodbc-dev git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/otp
RUN git clone --single-branch --depth 1 \
    https://github.com/erlang/otp.git . \
    && ./otp_build autoconf

# Aplica o patch PON-BEAM
COPY pon-beam-erts.tar.gz /tmp/
RUN tar xzf /tmp/pon-beam-erts.tar.gz -C /usr/src/otp \
    && rm /tmp/pon-beam-erts.tar.gz \
    && ls -la erts/emulator/beam/pon_*.c erts/include/internal/pon_*.h

RUN ./configure --prefix=/opt/erlang-pon \
                --without-javac --without-odbc --without-wx \
    && (cd erts && ERL_TOP=/usr/src/otp ./configure \
        --prefix=/opt/erlang-pon --enable-pon-beam) \
    && make -j$(nproc) \
    && make install

# ============================================================
# ESTGIO 3: Imagem final com ambos ERTS + harness
# ============================================================
FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl1.1 libncurses6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder-stock /opt/erlang-baseline /opt/erlang-baseline
COPY --from=builder-pon /opt/erlang-pon /opt/erlang-pon
COPY harness /pon-beam/harness

RUN echo '#!/bin/bash\n\
echo "PON-BEAM Benchmark Runner"\n\
echo "========================================="\n\
echo ""\n\
echo "OTP Stock:"\n\
/opt/erlang-baseline/bin/erl -noshell -eval '\''\
  io:format("  Versao: ~s~n", [erlang:system_info(otp_release)]),\
  halt().'\''\n\
echo ""\n\
echo "PON-BEAM:"\n\
/opt/erlang-pon/bin/erl -noshell -eval '\''\
  io:format("  Versao: ~s~n", [erlang:system_info(otp_release)]),\
  io:format("  PON_BEAM: ~p~n", [erlang:system_info(pon_stats) /= undefined]),\
  halt().'\''\n\
echo ""\n\
echo "========================================="\n\
echo "Executando benchmarks..."\n\
export OTP_BASELINE_ROOT=/opt/erlang-baseline\n\
export OTP_PONBEAM_ROOT=/opt/erlang-pon\n\
cd /pon-beam/harness\n\
bash run.sh 2>&1\n\
echo ""\n\
echo "Resultados: /pon-beam/harness/results/latest/"\n' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
