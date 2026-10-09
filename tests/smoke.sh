#!/bin/bash
# shellcheck disable=SC2034,SC2154,SC2317  # vars/functions come from the sourced install.sh
# Smoke test: load install.sh functions only (no install, no services).
# usage: bash smoke.sh /path/to/install.sh [--install-base] [--no-os-release]
script="$1"; shift
do_base=0; no_osr=0
for a in "$@"; do
  case "$a" in --install-base) do_base=1 ;; --no-os-release) no_osr=1 ;; esac
done
if [[ $no_osr == 1 ]]; then
  rm -f /etc/os-release /usr/lib/os-release
fi
V2BX_INSTALL_SOURCE_ONLY=1
# shellcheck source=/dev/null
source "$script"
echo "bash=${BASH_VERSION}"
detect_os
detect_arch
( check_os_version ) ; echo "check_os_version_rc=$?"
detect_os_version
detect_pkg_manager
detect_init
echo "RESULT release=${release} os_id=${os_id} id_like='${os_id_like}' os_version=${os_version:-<none>} arch=${arch} pkg_mgr=${pkg_mgr} init=${init_system}"
echo "packages: $(base_packages)"
# main() arg dispatch with heavy functions stubbed
( install_base(){ :; }; install_V2bX(){ echo "install_V2bX argc=$# args=[$*]"; }; EUID=0 main ) 2>/dev/null | grep argc
( install_base(){ :; }; install_V2bX(){ echo "install_V2bX argc=$# args=[$*]"; }; main v0.1.2 ) | grep argc
if [[ $do_base == 1 ]]; then
  echo "--- install_base (real package install) ---"
  install_base
  for c in wget curl unzip tar socat; do printf '%s=%s ' "$c" "$(command -v $c >/dev/null && echo ok || echo MISSING)"; done; echo
fi
