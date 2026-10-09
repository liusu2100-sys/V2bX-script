#!/bin/bash
# Optimized install.sh for V2bX, self-hosted by liusu2100-sys.
# Originally derived from wyx2685/V2bX-script install.sh (credit: upstream).
#
# Same install paths (/usr/local/V2bX, /etc/V2bX), same systemd / OpenRC
# service units, same prompts and arguments as upstream. Differences:
#   * all downloads come from the repositories configured in the
#     "Repository constants" block below (no third-party URLs);
#   * no telemetry / statistics call;
#   * TLS certificates are verified (fallback without verification only if
#     the download fails with a certificate error, with a warning);
#   * more robust OS / version / package-manager / init detection.
#
# Supported: CentOS 7+ / RHEL / Rocky / AlmaLinux / Oracle Linux / Fedora
#            (yum or dnf), Ubuntu 16+, Debian 8+, Alpine (apk + OpenRC),
#            Arch Linux (pacman).
#
# NOTE: this script (and the V2bX management script it installs) requires
# bash. Alpine does not ship bash by default, install it first:
#     apk add bash
#
# Compatible with bash >= 4.2 (CentOS 7). Avoid newer bashisms such as
# `declare -n`, `mapfile -d`, `${var@Q}`, `$EPOCHSECONDS`.
#
# For testing only: `V2BX_INSTALL_SOURCE_ONLY=1 source install.sh` loads the
# functions without running anything.

# ---------------------------------------------------------------------------
# Repository constants: change the owner / repos / branch HERE (keep them in
# sync with V2bX.sh and initconfig.sh). Each value can also be overridden by
# an environment variable of the same name prefixed with V2BX_, e.g.
#     V2BX_REPO_OWNER=someone bash install.sh
# ---------------------------------------------------------------------------
REPO_OWNER="${V2BX_REPO_OWNER:-liusu2100-sys}"
SCRIPT_REPO="${V2BX_SCRIPT_REPO:-${REPO_OWNER}/V2bX-script}"   # install.sh / V2bX.sh / initconfig.sh
SCRIPT_BRANCH="${V2BX_SCRIPT_BRANCH:-main}"
CORE_REPO="${V2BX_CORE_REPO:-${REPO_OWNER}/V2bX}"              # V2bX binaries (GitHub Releases)
SCRIPT_URL_BASE="https://raw.githubusercontent.com/${SCRIPT_REPO}/${SCRIPT_BRANCH}"
RELEASE_API="https://api.github.com/repos/${CORE_REPO}/releases/latest"
RELEASE_DL_BASE="https://github.com/${CORE_REPO}/releases/download"
DOC_URL="https://github.com/${SCRIPT_REPO}/blob/${SCRIPT_BRANCH}/docs/INSTALL.md"
# ---------------------------------------------------------------------------

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

err()  { echo -e "${red}$*${plain}"; }
ok()   { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

# Globals filled by the detect_* functions:
#   release      centos | debian | ubuntu | alpine | arch   (same values as upstream)
#   os_id        lower-case ID from /etc/os-release (or fallback guess)
#   os_id_like   lower-case ID_LIKE from /etc/os-release
#   os_version   integer major version, empty if unknown (e.g. Arch rolling, Debian sid)
#   pkg_mgr      dnf | yum | apt-get | apk | pacman
#   init_system  systemd | openrc
#   arch         64 | arm64-v8a | s390x  (V2bX release asset suffix)
release=""
os_id=""
os_id_like=""
os_version=""
pkg_mgr=""
init_system=""

to_lower() { echo "$*" | tr '[:upper:]' '[:lower:]'; }

# Read KEY from an os-release style file without sourcing it.
# usage: os_release_get KEY [file]
os_release_get() {
    local key="$1" file="${2:-/etc/os-release}"
    [[ -r "${file}" ]] || return 0
    awk -v k="${key}" '
        index($0, k "=") == 1 {
            v = substr($0, length(k) + 2)
            gsub(/^["'\'']|["'\'']$/, "", v)
            print v
            exit
        }' "${file}"
}

# Map a single os-release ID / ID_LIKE token to an upstream "release" value.
map_os_token() {
    case "$1" in
        centos|rhel|redhat|rocky|almalinux|ol|oracle|fedora|amzn|cloudlinux|virtuozzo|eurolinux|scientific)
            echo "centos" ;;
        ubuntu)                     echo "ubuntu" ;;
        debian|raspbian)            echo "debian" ;;
        alpine)                     echo "alpine" ;;
        arch|archarm|manjaro|endeavouros|artix|garuda)
            echo "arch" ;;
        *)                          echo "" ;;
    esac
}

# Legacy detection (identical to upstream), used only when /etc/os-release
# and the distro-specific release files give no answer.
detect_os_legacy() {
    local issue="" proc=""
    [[ -r /etc/issue ]] && issue=$(cat /etc/issue)
    [[ -r /proc/version ]] && proc=$(cat /proc/version)

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif echo "${issue}" | grep -Eqi "alpine"; then
        release="alpine"
    elif echo "${issue}" | grep -Eqi "debian"; then
        release="debian"
    elif echo "${issue}" | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif echo "${issue}" | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
        release="centos"
    elif echo "${proc}" | grep -Eqi "debian"; then
        release="debian"
    elif echo "${proc}" | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif echo "${proc}" | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
        release="centos"
    elif echo "${proc}" | grep -Eqi "arch"; then
        release="arch"
    fi
}

detect_os() {
    local token rh=""
    release=""
    os_id=""
    os_id_like=""

    # 1) /etc/os-release (all supported systems except very old ones)
    if [[ -r /etc/os-release ]]; then
        os_id=$(to_lower "$(os_release_get ID)")
        os_id_like=$(to_lower "$(os_release_get ID_LIKE)")
    fi

    # 2) distro specific release files
    if [[ -z "${os_id}" ]]; then
        if [[ -r /etc/redhat-release ]]; then
            rh=$(to_lower "$(cat /etc/redhat-release)")
            case "${rh}" in
                *fedora*)               os_id="fedora" ;;
                *rocky*)                os_id="rocky" ;;
                *alma*)                 os_id="almalinux" ;;
                *oracle*)               os_id="ol" ;;
                *centos*)               os_id="centos" ;;
                *"red hat"*|*redhat*)   os_id="rhel" ;;
                *)                      os_id="centos" ;;
            esac
        elif [[ -f /etc/alpine-release ]]; then
            os_id="alpine"
        elif [[ -f /etc/arch-release ]]; then
            os_id="arch"
        elif [[ -r /etc/lsb-release ]] && grep -qi "ubuntu" /etc/lsb-release; then
            os_id="ubuntu"
        elif [[ -f /etc/debian_version ]]; then
            os_id="debian"
        fi
    fi

    release=$(map_os_token "${os_id}")

    # 3) derivatives: walk ID_LIKE (e.g. "rhel centos fedora", "ubuntu debian")
    if [[ -z "${release}" && -n "${os_id_like}" ]]; then
        for token in ${os_id_like}; do
            release=$(map_os_token "${token}")
            [[ -n "${release}" ]] && break
        done
    fi

    # 4) upstream heuristics as last resort
    if [[ -z "${release}" ]]; then
        detect_os_legacy
    fi

    if [[ -z "${release}" ]]; then
        err "未检测到系统版本，请联系脚本作者！\n"
        exit 1
    fi
}

detect_os_version() {
    local v=""
    os_version=""

    if [[ -r /etc/os-release ]]; then
        v=$(os_release_get VERSION_ID)
    fi
    if [[ -z "${v}" && -r /etc/redhat-release ]]; then
        v=$(grep -oE '[0-9]+(\.[0-9]+)*' /etc/redhat-release | head -n 1)
    fi
    if [[ -z "${v}" && -r /etc/lsb-release ]]; then
        v=$(os_release_get DISTRIB_RELEASE /etc/lsb-release)
    fi
    if [[ -z "${v}" && -r /etc/debian_version ]]; then
        v=$(head -n 1 /etc/debian_version)   # "8.11" or "bookworm/sid"
    fi

    # keep the integer major part only ("16.04" -> 16, "8.9" -> 8, "3.20.3" -> 3)
    v=${v%%.*}
    if [[ "${v}" =~ ^[0-9]+$ ]]; then
        os_version=${v}
    fi
}

# Is this an Enterprise Linux clone (where the "CentOS 7+" rule applies)?
is_el_clone() {
    case "${os_id}" in
        centos|rhel|rocky|almalinux|ol|cloudlinux|virtuozzo|eurolinux|scientific) return 0 ;;
    esac
    return 1
}

check_os_version() {
    detect_os_version

    case "${release}" in
        centos)
            # Fedora / Amazon Linux etc. use their own version scheme: skip.
            is_el_clone || return 0
            if [[ -z "${os_version}" ]]; then
                warn "无法识别系统版本号，跳过版本检查"
                return 0
            fi
            if [[ ${os_version} -le 6 ]]; then
                err "请使用 CentOS 7 或更高版本的系统！\n"
                exit 1
            fi
            if [[ ${os_version} -eq 7 ]]; then
                err "注意： CentOS 7 无法使用hysteria1/2协议！\n"
            fi
            if [[ "${os_id}" == "centos" && ${os_version} -le 8 ]]; then
                warn "提示：CentOS ${os_version} 已停止维护 (EOL)，官方软件源可能不可用；若依赖安装失败，请自行将 yum 源切换至 vault.centos.org 等归档源后重试。"
            fi
            ;;
        ubuntu)
            [[ "${os_id}" == "ubuntu" ]] || return 0
            if [[ -z "${os_version}" ]]; then
                warn "无法识别系统版本号，跳过版本检查"
                return 0
            fi
            if [[ ${os_version} -lt 16 ]]; then
                err "请使用 Ubuntu 16 或更高版本的系统！\n"
                exit 1
            fi
            ;;
        debian)
            [[ "${os_id}" == "debian" || "${os_id}" == "raspbian" ]] || return 0
            # testing / sid have no VERSION_ID: nothing to check
            [[ -z "${os_version}" ]] && return 0
            if [[ ${os_version} -lt 8 ]]; then
                err "请使用 Debian 8 或更高版本的系统！\n"
                exit 1
            fi
            if [[ ${os_version} -le 9 ]]; then
                warn "提示：Debian ${os_version} 已停止维护 (EOL)，若依赖安装失败，请自行将 apt 源切换至 archive.debian.org 后重试。"
            fi
            ;;
        # alpine / arch (rolling): no version requirement, same as upstream
    esac
}

detect_arch() {
    arch=$(uname -m)
    case "${arch}" in
        x86_64|x64|amd64) arch="64" ;;
        aarch64|arm64)    arch="arm64-v8a" ;;
        s390x)            arch="s390x" ;;
        *)
            arch="64"
            err "检测架构失败，使用默认架构: ${arch}"
            ;;
    esac
    echo "架构: ${arch}"

    # getconf may be missing on minimal systems: an empty result must not be
    # mistaken for a 32-bit system.
    if command -v getconf >/dev/null 2>&1; then
        if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ]; then
            echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
            exit 2
        fi
    fi
}

detect_pkg_manager() {
    pkg_mgr=""
    case "${release}" in
        centos)
            # CentOS 7: yum only; EL8+/Fedora: dnf (yum is just an alias there)
            if command -v dnf >/dev/null 2>&1; then
                pkg_mgr="dnf"
            elif command -v yum >/dev/null 2>&1; then
                pkg_mgr="yum"
            fi
            ;;
        debian|ubuntu) command -v apt-get >/dev/null 2>&1 && pkg_mgr="apt-get" ;;
        alpine)        command -v apk >/dev/null 2>&1 && pkg_mgr="apk" ;;
        arch)          command -v pacman >/dev/null 2>&1 && pkg_mgr="pacman" ;;
    esac
    if [[ -z "${pkg_mgr}" ]]; then
        warn "未找到可用的包管理器，将跳过依赖安装，请手动安装 wget curl unzip tar socat ca-certificates"
    fi
}

# Choose the init system from what is actually running, falling back to the
# upstream rule (Alpine -> OpenRC, everything else -> systemd).
detect_init() {
    if [[ -d /run/systemd/system ]]; then
        init_system="systemd"
    elif [[ "${release}" == "alpine" ]]; then
        init_system="openrc"
    elif command -v systemctl >/dev/null 2>&1; then
        init_system="systemd"
    elif command -v openrc-run >/dev/null 2>&1 || command -v rc-update >/dev/null 2>&1; then
        init_system="openrc"
        warn "检测到 OpenRC，将安装 OpenRC 服务；V2bX 管理脚本可能仅在 Alpine 上支持 OpenRC。"
    else
        init_system="systemd"
    fi
}

# Run the package manager quietly (same as upstream: output discarded).
pkg_cmd() {
    case "${pkg_mgr}" in
        # strict=0: skip unavailable packages instead of aborting (dnf4 + dnf5)
        dnf)     dnf install -y --setopt=strict=0 "$@" ;;
        yum)     yum install -y "$@" ;;
        apt-get) DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" ;;
        apk)     apk add "$@" ;;
        pacman)  pacman -S --noconfirm --needed "$@" ;;
        *)       return 1 ;;
    esac
}

# Install packages; if the batch fails (e.g. one name unknown on this
# release, which makes apt/pacman/apk abort the whole transaction), retry
# one by one so the remaining dependencies still get installed.
# yum skips unknown names by itself and dnf runs with strict=0, so they are
# not retried (a retry would only multiply timeouts on dead EOL mirrors).
pkg_install() {
    local p rc=0
    pkg_cmd "$@" >/dev/null 2>&1 && return 0
    case "${pkg_mgr}" in yum|dnf) return 1 ;; esac
    for p in "$@"; do
        pkg_cmd "${p}" >/dev/null 2>&1 || rc=1
    done
    return ${rc}
}

pkg_update() {
    case "${pkg_mgr}" in
        apt-get) DEBIAN_FRONTEND=noninteractive apt-get update -y ;;
        apk)     apk update ;;
        pacman)  pacman -Sy --noconfirm ;;
        *)       return 0 ;;   # yum/dnf refresh metadata on demand
    esac
}

# Print the dependency list for the detected distro.
base_packages() {
    case "${release}" in
        centos) echo "wget curl unzip tar crontabs cronie socat ca-certificates" ;;
        # bash is already required to run this script; listed so the V2bX
        # management script (also bash) is guaranteed to work.
        alpine) echo "bash wget curl unzip tar socat ca-certificates" ;;
        debian|ubuntu) echo "wget curl unzip tar cron socat ca-certificates" ;;
        # "cron" is only a virtual provide on Arch; name the real package (cronie).
        arch)   echo "wget curl unzip tar cronie socat ca-certificates" ;;
    esac
}

install_base() {
    local pkgs missing="" c
    pkgs=$(base_packages)

    if [[ -n "${pkg_mgr}" ]]; then
        if ! pkg_update >/dev/null 2>&1; then
            warn "软件源更新失败，请检查软件源配置（EOL 系统请切换至归档源）"
        fi
        if [[ "${release}" == "centos" ]] && is_el_clone; then
            # Same single transaction as upstream; EPEL is optional (skipped
            # automatically where unavailable, e.g. RHEL without extra repos).
            pkgs="epel-release ${pkgs}"
        fi
        # shellcheck disable=SC2086  # word splitting of the package list is intended
        pkg_install ${pkgs} || true
    fi

    case "${release}" in
        centos)        update-ca-trust force-enable >/dev/null 2>&1 || true ;;
        alpine|debian|ubuntu) update-ca-certificates >/dev/null 2>&1 || true ;;
    esac

    for c in wget curl unzip tar; do
        command -v "${c}" >/dev/null 2>&1 || missing="${missing} ${c}"
    done
    if [[ -n "${missing}" ]]; then
        warn "以下依赖未能安装:${missing}，请检查软件源后手动安装"
    fi
}

service_status_cmd() {
    if command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX status
    else
        service V2bX status
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ "${init_system}" == "openrc" ]]; then
        temp=$(service_status_cmd 2>/dev/null | awk '{print $3}')
        [[ "${temp}" == "started" ]] && return 0 || return 1
    else
        temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        [[ "${temp}" == "running" ]] && return 0 || return 1
    fi
}

# wget with certificate verification; only if it fails with a TLS/certificate
# error (wget exit code 5, e.g. outdated CA bundle on an EOL system) retry
# once without verification and print a warning.
# usage: wget_tls OUTPUT URL [extra wget args...]
wget_tls() {
    local out="$1" url="$2" rc
    shift 2
    wget -N --progress=bar "$@" -O "${out}" "${url}"
    rc=$?
    if [[ ${rc} -eq 5 ]]; then
        warn "TLS 证书校验失败（系统 CA 证书可能过旧），将跳过证书校验重试一次：${url}"
        wget --no-check-certificate -N --progress=bar "$@" -O "${out}" "${url}"
        rc=$?
    fi
    return ${rc}
}

# curl with certificate verification, same fallback (curl exit 35/51/58/60/77/83
# are TLS / certificate errors). Fails on HTTP errors (-f).
# usage: curl_tls OUTPUT URL
curl_tls() {
    local out="$1" url="$2" rc
    curl -fLs -o "${out}" "${url}"
    rc=$?
    case "${rc}" in
        35|51|58|60|77|83)
            warn "TLS 证书校验失败（系统 CA 证书可能过旧），将跳过证书校验重试一次：${url}"
            curl -kfLs -o "${out}" "${url}"
            rc=$?
            ;;
    esac
    return ${rc}
}

get_latest_version() {
    local json rc
    json=$(curl -fLs "${RELEASE_API}")
    rc=$?
    case "${rc}" in
        35|51|58|60|77|83)
            warn "TLS 证书校验失败（系统 CA 证书可能过旧），将跳过证书校验重试一次：${RELEASE_API}"
            json=$(curl -kfLs "${RELEASE_API}")
            ;;
    esac
    echo "${json}" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/'
}

download_v2bx_zip() {
    local version="$1"
    local url="${RELEASE_DL_BASE}/${version}/V2bX-linux-${arch}.zip"
    wget_tls /usr/local/V2bX/V2bX-linux.zip "${url}"
}

install_service() {
    if [[ "${init_system}" == "openrc" ]]; then
        rm -f /etc/init.d/V2bX
        cat <<EOF > /etc/init.d/V2bX
#!/sbin/openrc-run

name="V2bX"
description="V2bX"

command="/usr/local/V2bX/V2bX"
command_args="server"
command_user="root"

pidfile="/run/V2bX.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
    else
        rm -f /etc/systemd/system/V2bX.service
        cat <<EOF > /etc/systemd/system/V2bX.service
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/V2bX/
ExecStart=/usr/local/V2bX/V2bX server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop V2bX
        systemctl enable V2bX
    fi
    echo -e "${green}V2bX ${last_version}${plain} 安装完成，已设置开机自启"
}

start_service() {
    if [[ "${init_system}" == "openrc" ]]; then
        if command -v rc-service >/dev/null 2>&1; then
            rc-service V2bX start
        else
            service V2bX start
        fi
    else
        systemctl start V2bX
    fi
}

copy_default_configs() {
    local f
    for f in dns.json route.json custom_outbound.json custom_inbound.json; do
        if [[ ! -f "/etc/V2bX/${f}" ]]; then
            cp "${f}" /etc/V2bX/
        fi
    done
}

print_usage() {
    echo -e ""
    echo "V2bX 管理脚本使用方法 (兼容使用V2bX执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "V2bX              - 显示管理菜单 (功能更多)"
    echo "V2bX start        - 启动 V2bX"
    echo "V2bX stop         - 停止 V2bX"
    echo "V2bX restart      - 重启 V2bX"
    echo "V2bX status       - 查看 V2bX 状态"
    echo "V2bX enable       - 设置 V2bX 开机自启"
    echo "V2bX disable      - 取消 V2bX 开机自启"
    echo "V2bX log          - 查看 V2bX 日志"
    echo "V2bX x25519       - 生成 x25519 密钥"
    echo "V2bX generate     - 生成 V2bX 配置文件"
    echo "V2bX update       - 更新 V2bX"
    echo "V2bX update x.x.x - 更新 V2bX 指定版本"
    echo "V2bX install      - 安装 V2bX"
    echo "V2bX uninstall    - 卸载 V2bX"
    echo "V2bX version      - 查看 V2bX 版本"
    echo "------------------------------------------"
}

install_V2bX() {
    if [[ -e /usr/local/V2bX/ ]]; then
        rm -rf /usr/local/V2bX/
    fi

    mkdir -p /usr/local/V2bX/
    cd /usr/local/V2bX/ || exit 1

    if [[ $# -eq 0 ]]; then
        last_version=$(get_latest_version)
        if [[ -z "${last_version}" ]]; then
            err "检测 V2bX 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 V2bX 版本安装"
            exit 1
        fi
        echo -e "检测到 V2bX 最新版本：${last_version}，开始安装"
        if ! download_v2bx_zip "${last_version}"; then
            err "下载 V2bX 失败，请确保你的服务器能够下载 Github 的文件"
            exit 1
        fi
    else
        last_version=$1
        echo -e "开始安装 V2bX $1"
        if ! download_v2bx_zip "${last_version}"; then
            err "下载 V2bX $1 失败，请确保此版本存在"
            exit 1
        fi
    fi

    unzip V2bX-linux.zip
    rm -f V2bX-linux.zip
    chmod +x V2bX
    mkdir -p /etc/V2bX/
    cp geoip.dat /etc/V2bX/
    cp geosite.dat /etc/V2bX/

    install_service

    if [[ ! -f /etc/V2bX/config.json ]]; then
        cp config.json /etc/V2bX/
        echo -e ""
        echo -e "全新安装，请先参看教程：${DOC_URL}，配置必要的内容"
        first_install=true
    else
        start_service
        sleep 2
        echo -e ""
        # Test check_status directly: upstream read $? after an echo, so the
        # result was always "success".
        if check_status; then
            ok "V2bX 重启成功"
        else
            err "V2bX 可能启动失败，请稍后使用 V2bX log 查看日志信息，若无法启动，则可能更改了配置格式，请前往文档查看：${DOC_URL}"
        fi
        first_install=false
    fi

    copy_default_configs

    if ! curl_tls /usr/bin/V2bX.tmp "${SCRIPT_URL_BASE}/V2bX.sh"; then
        rm -f /usr/bin/V2bX.tmp
        err "下载 V2bX 管理脚本失败：${SCRIPT_URL_BASE}/V2bX.sh"
    else
        mv -f /usr/bin/V2bX.tmp /usr/bin/V2bX
    fi
    chmod +x /usr/bin/V2bX
    if [[ ! -L /usr/bin/v2bx ]]; then
        ln -s /usr/bin/V2bX /usr/bin/v2bx
        chmod +x /usr/bin/v2bx
    fi

    cd "${cur_dir}" || true
    rm -f install.sh
    print_usage

    # 首次安装询问是否生成配置文件
    if [[ ${first_install} == true ]]; then
        read -rp "检测到你为第一次安装V2bX,是否自动直接生成配置文件？(y/n): " if_generate
        if [[ ${if_generate} == [Yy] ]]; then
            if curl_tls ./initconfig.sh "${SCRIPT_URL_BASE}/initconfig.sh"; then
                # shellcheck source=/dev/null
                source initconfig.sh
                rm -f initconfig.sh
                generate_config_file
            else
                rm -f initconfig.sh
                err "下载 initconfig.sh 失败，请稍后运行 V2bX generate 生成配置文件"
            fi
        fi
    fi
}

main() {
    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

    detect_os
    detect_arch
    check_os_version
    detect_pkg_manager
    detect_init

    ok "开始安装"
    install_base
    # Upstream calls `install_V2bX $1` unquoted: an empty/missing $1 means
    # "latest version". Preserve that (quoting "$1" would pass an empty arg).
    if [[ -n "${1:-}" ]]; then
        install_V2bX "$1"
    else
        install_V2bX
    fi
}

if [[ "${V2BX_INSTALL_SOURCE_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
