# PON-BEAM Build config — Baseline (OTP 30 stock)
# Extraído do Docker: docker cp pon-extract:/opt/erlang-baseline ~/erlang-30-stock
# bin/erl é symlink com ROOTDIR quebrado; usar lib/erlang/bin/erl diretamente.

OTP_BASELINE_ROOT=${OTP_BASELINE_ROOT:-/home/sanonichan/erlang-30-stock}
BASELINE_ERL=${OTP_BASELINE_ROOT}/lib/erlang/bin/erl
BASELINE_ERLC=${OTP_BASELINE_ROOT}/lib/erlang/bin/erlc