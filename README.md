# V2bX 一键安装脚本（兼容性优化版）

本项目是 [wyx2685/V2bX-script](https://github.com/wyx2685/V2bX-script) 中 `install.sh` 的**优化分支**。
在**不改变任何功能和行为**的前提下（安装路径、下载地址、systemd / OpenRC 服务文件、提示文字与颜色、版本参数均与上游一致），
重点改进了系统识别、版本判断、包管理器选择和依赖安装的兼容性与健壮性。

> 注意：脚本仍然从上游 **wyx2685/V2bX 的 GitHub Releases** 下载 V2bX 程序，
> 并从上游 V2bX-script 仓库下载管理脚本 `V2bX.sh` 与 `initconfig.sh`，本仓库不分发任何二进制文件。

## 支持的系统

| 系统 | 版本 | 包管理器 | 服务管理 |
| --- | --- | --- | --- |
| CentOS / RHEL / Rocky Linux / AlmaLinux / Oracle Linux | 7 及以上 | yum（7）/ dnf（8+） | systemd |
| Fedora（及 Amazon Linux 等 RHEL 系衍生版） | 当前版本 | dnf / yum | systemd |
| Ubuntu | 16.04 及以上 | apt-get | systemd |
| Debian | 8 及以上 | apt-get | systemd |
| Alpine Linux | 当前版本 | apk | OpenRC |
| Arch Linux（及 Manjaro 等衍生版） | 滚动更新 | pacman | systemd |

架构：`x86_64/amd64`、`aarch64/arm64`、`s390x`（与上游相同，不支持 32 位系统）。

> **Alpine 用户**：脚本本身及安装的管理脚本都需要 bash，请先执行 `apk add bash`。
>
> **CentOS 7 / 8、Debian 8 / 9 等已停止维护（EOL）的系统**：官方软件源可能已下线，脚本只会给出提示、不会修改你的软件源。
> 如依赖安装失败，请自行切换至归档源（如 `vault.centos.org`、`archive.debian.org`）后重试。
> 另外 CentOS 7 无法使用 hysteria1/2 协议（与上游相同）。

## 使用方法

使用 root 用户执行：

```bash
# 安装最新版本
bash <(curl -Ls https://raw.githubusercontent.com/liusu2100-sys/V2bX-script/main/install.sh)

# 安装指定版本（与上游参数一致）
bash <(curl -Ls https://raw.githubusercontent.com/liusu2100-sys/V2bX-script/main/install.sh) v0.x.x
```

（将 `liusu2100-sys/V2bX-script` 替换为实际的仓库地址。）

安装完成后与上游一样使用 `V2bX` / `v2bx` 命令管理：`V2bX start|stop|restart|status|log|update|generate|uninstall ...`

安装位置（与上游一致）：

- 程序：`/usr/local/V2bX/`
- 配置：`/etc/V2bX/`
- 服务：`/etc/systemd/system/V2bX.service`（systemd）或 `/etc/init.d/V2bX`（OpenRC）
- 管理脚本：`/usr/bin/V2bX`（以及软链接 `/usr/bin/v2bx`）

## 相对上游的改动

- **系统识别**：优先读取 `/etc/os-release` 的 `ID` / `ID_LIKE`（不直接 source，避免副作用），识别 centos、rhel、rocky、almalinux、ol、fedora、ubuntu、debian、alpine、arch 及其衍生版；
  缺少 os-release 时依次回退到 `/etc/redhat-release`、`/etc/alpine-release`、`/etc/arch-release`、`/etc/lsb-release`、`/etc/debian_version`，最后才使用上游的 `/etc/issue`、`/proc/version` 规则（容器中 `/proc/version` 反映的是宿主机内核，容易误判）。
- **版本判断**：只取主版本号整数（`16.04`→16、`8.9`→8），兼容缺少 `VERSION_ID` 的系统（Arch 滚动版、Debian testing/sid）；版本限制只作用于对应的原生发行版（如 Fedora、Amazon Linux 不再套用 “CentOS 7+” 规则）；无法识别版本号时给出提示而不是误判退出。
- **包管理器**：RHEL 系优先 dnf、否则 yum；dnf 使用 `--setopt=strict=0`，某个包不存在时不会导致整批依赖安装失败；apt 使用 `apt-get` + `DEBIAN_FRONTEND=noninteractive`（避免交互卡住）；pacman 使用 `--noconfirm --needed`；apt/apk/pacman 批量安装失败时自动逐个重试。
- **依赖修正**：Arch 上的 `cron` 只是虚拟包名（由多个提供者满足），改为明确安装 `cronie`；RHEL 系额外安装 `cronie`；Alpine 额外列出 `bash`；Ubuntu 的两次安装合并为一次；`epel-release` 仅在 RHEL 克隆版上安装（Fedora 上不存在）。
- **安装后检查**：依赖安装后检查 wget / curl / unzip / tar 是否可用，缺失时给出提示。
- **EOL 提示**：CentOS 7/8、Debian 8/9 给出软件源已归档的提示，不修改任何软件源配置。
- **服务管理识别**：根据实际运行的 init 系统（`/run/systemd/system`、`systemctl`、OpenRC）选择 systemd 或 OpenRC，无法判断时回退到上游规则（Alpine 用 OpenRC，其他用 systemd）；在主流系统上结果与上游完全一致。
- **32 位检测**：系统缺少 `getconf` 时不再被误判为 32 位系统而退出。
- **Bug 修复**：
  - 更新安装后的 “V2bX 重启成功 / 可能启动失败” 判断：上游在 `check_status` 与 `$?` 之间插入了 `echo`，导致永远显示成功；现改为 `if check_status; then`。
  - 保持上游 “不带参数即安装最新版” 的语义（不会把空参数当作版本号）。
- **代码结构**：拆分为函数、变量全部加引号，通过 `bash -n` 与 `shellcheck` 检查；兼容 CentOS 7 的 bash 4.2。
  可通过 `V2BX_INSTALL_SOURCE_ONLY=1 source install.sh` 只加载函数用于测试（正常执行时无影响）。

## 测试

`tests/smoke.sh` 只加载脚本函数，测试系统识别、版本检查、包管理器与 init 选择以及依赖安装（不下载 V2bX、不创建服务），例如：

```bash
docker run --rm -v "$PWD":/t:ro centos:7 bash /t/tests/smoke.sh /t/install.sh
docker run --rm -v "$PWD":/t:ro alpine sh -c 'apk add bash && bash /t/tests/smoke.sh /t/install.sh --install-base'
```
