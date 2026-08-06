# PON-BEAM Build config — PON-BEAM real (OTP 30 + #ifdef PON_BEAM overlay)
# Build in-tree: /home/sanonichan/projetos/pon-beam/otp (make -j1, serial).
# os binarios residem em otp/bin (erl script) e otp/bin/x86_64-...-gnu/beam.smp.
# O bin/erl derivado do tree calcula o ROOTDIR pela própria localização.

OTP_PONBEAM_ROOT=${OTP_PONBEAM_ROOT:-/home/sanonichan/projetos/pon-beam/otp}
PONBEAM_ERL=${OTP_PONBEAM_ROOT}/bin/erl
PONBEAM_ERLC=${OTP_PONBEAM_ROOT}/bin/erlc