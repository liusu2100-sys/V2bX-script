#!/bin/bash
# Offline test of install.sh SHA-256 verification (no network, no install).
# usage: bash tests/checksum.sh /path/to/install.sh
# shellcheck disable=SC1090
V2BX_INSTALL_SOURCE_ONLY=1 source "$1"
fail=0
tmp=$(mktemp -d)
printf 'hello v2bx\n' > "${tmp}/z.zip"
h=$(sha256_of "${tmp}/z.zip") || { echo "FAIL no sha256 tool"; exit 1; }
printf 'MD5= x\nSHA1= y\nSHA2-256= %s\nSHA2-512= z\n' "${h}" > "${tmp}/new.dgst"   # OpenSSL 3
printf 'MD5= x\nSHA256= %s\n' "${h}" > "${tmp}/old.dgst"                          # OpenSSL 1.x
printf 'MD5= x\n' > "${tmp}/none.dgst"
check() { local name="$1" want="$2"; shift 2; "$@" >/dev/null 2>&1; local rc=$?
  if [[ ${rc} -eq ${want} ]]; then echo "ok   ${name}"; else echo "FAIL ${name} (rc=${rc}, want ${want})"; fail=1; fi; }
check "openssl3 dgst"          0 verify_zip "${tmp}/z.zip" "${tmp}/new.dgst"
check "openssl1 dgst"          0 verify_zip "${tmp}/z.zip" "${tmp}/old.dgst"
check "dgst without sha256"    1 verify_zip "${tmp}/z.zip" "${tmp}/none.dgst"
printf 'X' >> "${tmp}/z.zip"
check "tampered zip"           1 verify_zip "${tmp}/z.zip" "${tmp}/new.dgst"
rm -rf "${tmp}"
exit ${fail}
