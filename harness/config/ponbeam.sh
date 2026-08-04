# PON-BEAM Build config — PON-BEAM (OTP 30 + patch)
# Extraído do Docker: docker cp pon-extract:/opt/erlang-pon ~/erlang-30-pon
# bin/erl é symlink com ROOTDIR quebrado; usar lib/erlang/bin/erl diretamente.

OTP_PONBEAM_ROOT=${OTP_PONBEAM_ROOT:-/home/sanonichan/erlang-30-pon}
PONBEAM_ERL=${OTP_PONBEAM_ROOT}/lib/erlang/bin/erl
PONBEAM_ERLC=${OTP_PONBEAM_ROOT}/lib/erlang/bin/erlc