# PON-BEAM Benchmark Docker
# Baseado no Dockerfile oficial do Erlang/OTP (erlang:29)
# Constrói OTP 30 stock + PON-BEAM em estágios separados
#
# Uso:
#   docker build -f docker/Dockerfile -t pon-beam-bench .
#   docker run --name pon-beam-results pon-beam-bench
#   docker cp pon-beam-results:/pon-beam/harness/results/latest/. ./results/

# ============================================================
# ESTGIO 1: Build OTP 30 stock (baseline)
# ============================================================
FROM debian:trixie-slim AS builder-stock

RUN apt-get update && \
    apt-get install -y build-essential autoconf m4 libncurses-dev \
                       libssl-dev unixodbc-dev && \
    rm -rf /var/lib/apt/lists/*

ENV ERL_TOP=/otp
COPY otp /otp

RUN cd /otp && \
    ./configure --prefix=/opt/erlang-baseline \
                --without-javac --without-odbc --without-wx && \
    make -j$(nproc) && \
    make install

# ============================================================
# ESTGIO 2: Build OTP 30 com PON-BEAM
# ============================================================
FROM debian:trixie-slim AS builder-pon

RUN apt-get update && \
    apt-get install -y build-essential autoconf m4 libncurses-dev \
                       libssl-dev unixodbc-dev && \
    rm -rf /var/lib/apt/lists/*

ENV ERL_TOP=/otp
COPY otp /otp

RUN cd /otp && \
    rm -rf erts/x86_64-pc-linux-gnu erts/emulator/x86_64-pc-linux-gnu \
           config.* config.log config.status erts/config.log && \
    ./configure --prefix=/opt/erlang-pon \
                --without-javac --without-odbc --without-wx \
                --enable-pon-beam && \
    make -j$(nproc) && \
    make install

# ============================================================
# ESTGIO 3: Imagem final com ambos ERTS + harness
# ============================================================
FROM debian:trixie-slim

RUN apt-get update && \
    apt-get install -y libssl3t64 libncurses6 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder-stock /opt/erlang-baseline /opt/erlang-baseline
COPY --from=builder-pon /opt/erlang-pon /opt/erlang-pon
COPY harness /pon-beam/harness
COPY docs /pon-beam/docs

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
echo "Resultados salvos em: /pon-beam/harness/results/latest/"\n\
echo "Para extrair: docker cp pon-beam-results:/pon-beam/harness/results/latest/. ./results/"\n' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
