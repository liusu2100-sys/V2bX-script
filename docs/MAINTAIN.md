# 维护说明（MAINTAIN）

本项目已经完全自托管，由 **liusu2100-sys** 自己维护。涉及两个 GitHub 仓库：

| 仓库 | 作用 | 默认分支 |
| --- | --- | --- |
| [liusu2100-sys/V2bX-script](https://github.com/liusu2100-sys/V2bX-script)（本仓库） | 安装脚本、管理脚本、配置向导、文档 | `main` |
| [liusu2100-sys/V2bX](https://github.com/liusu2100-sys/V2bX) | V2bX 程序源码（fork 自 wyx2685/V2bX），用 GitHub Actions 构建并发布 Release | `dev_new` |

用户服务器上的所有下载都只访问这两个仓库（经由 GitHub）。

---

## 1. 仓库结构

### 本仓库 V2bX-script

```text
install.sh        一键安装/更新脚本（V2bX update / install 也是调用它）
V2bX.sh           管理脚本，安装到 /usr/bin/V2bX（以及软链接 /usr/bin/v2bx）
initconfig.sh     首次安装时的配置生成向导，install.sh 下载后 source 并调用 generate_config_file
docs/INSTALL.md   安装教程（给用户看）
docs/MAINTAIN.md  本文件（给维护者看）
tests/smoke.sh    冒烟测试（只加载函数，测试系统识别等，不真正安装）
```

脚本之间的调用关系：

```text
用户执行 bash <(curl ... install.sh)
  ├─ GET https://api.github.com/repos/liusu2100-sys/V2bX/releases/latest   → 取最新 tag
  ├─ GET https://github.com/liusu2100-sys/V2bX/releases/download/<tag>/V2bX-linux-<arch>.zip
  │     （zip 内含 V2bX 程序、geoip.dat、geosite.dat、示例 json 配置）
  ├─ GET raw.githubusercontent.com/liusu2100-sys/V2bX-script/main/V2bX.sh      → /usr/bin/V2bX
  └─ (首次安装且选择生成配置) GET .../main/initconfig.sh

V2bX update / V2bX install   → 下载并运行本仓库 main 分支的 install.sh
V2bX update_shell            → 重新下载本仓库 main 分支的 V2bX.sh
```

`<arch>` 只用到三种：`64`（x86_64）、`arm64-v8a`（aarch64）、`s390x`。

### V2bX 仓库（fork）

- `.github/workflows/release.yml`：构建并发布 Release（见第 2 节）。
- `.github/build/friendly-filenames.json`：GOOS/GOARCH → 资产文件名（如 `linux-amd64` → `linux-64`），**不要改名**，否则 install.sh 找不到文件。
- `example/*.json`：会被打包进 zip（`config.json`、`dns.json`、`route.json`、`custom_outbound.json`、`custom_inbound.json`），install.sh 首次安装时复制到 `/etc/V2bX/`。

---

## 2. 发布新的 V2bX 版本

install.sh 永远安装 **GitHub「Latest」Release**（草稿和预发布不算），所以发布流程就是「打 tag → Actions 构建 → 自动变成 Latest」。

```bash
git clone https://github.com/liusu2100-sys/V2bX.git
cd V2bX
git checkout dev_new
# ……修改代码 / 合并上游（见第 3 节）……
git push origin dev_new

git tag v0.4.1            # tag 必须以 v 开头
git push origin v0.4.1
```

推送 tag 后，Actions 里的 **Build and Release** 工作流会：

1. `release`：为该 tag 创建一个 **草稿（draft）** Release（已存在则跳过）；
2. `build`：并行编译所有平台，每个平台上传 `V2bX-<平台>.zip` 和 `V2bX-<平台>.zip.dgst`（md5/sha1/sha256/sha512），文件名与上游完全相同；
3. `publish`：**全部平台编译成功后**才把 Release 发布并标记为 Latest。

在此之前用户安装拿到的仍是上一个版本，不会出现「Release 已有但文件还没传完」的情况。若有平台编译失败，Release 保持草稿，修复后重新推送一个新 tag，或在 Actions 页面手动运行（见下）。

其他操作：

- **重新构建/补传某个已有 tag**：GitHub → V2bX 仓库 → Actions → Build and Release → Run workflow，`tag` 填 `v0.4.1`。会用 `--clobber` 覆盖同名文件。
- **只测试编译、不发布**：Run workflow 时 `tag` 留空；或推送修改了 `*.go` / `go.mod` / `go.sum` 的提交到 `dev_new`（只生成 Actions Artifacts，不动 Release）。
- **让服务器更新**：发布完成后在服务器执行 `V2bX update`（或重新运行一键安装命令）。
- **回退**：`V2bX update v0.4.0`。如果新版本有严重问题，也可以在 GitHub 上把旧版本 Release 重新设为 Latest（编辑 Release → 勾选 *Set as the latest release*），或删除/改为草稿新版本。
- **验证发布结果**：

  ```bash
  curl -s https://api.github.com/repos/liusu2100-sys/V2bX/releases/latest | grep tag_name
  curl -sIL -o /dev/null -w '%{http_code}\n' \
    https://github.com/liusu2100-sys/V2bX/releases/download/v0.4.1/V2bX-linux-64.zip   # 应为 200
  ```

注意：

- 第一次在 fork 上使用 Actions 时，如果 Actions 页面提示 “Workflows aren't being run on this forked repository”，点一下 **I understand my workflows, go ahead and enable them**。
- 用 `git push` 推送 `.github/workflows/` 下的文件时，个人访问令牌（PAT）需要 `workflow` 权限，否则会被 GitHub 拒绝。
- 当前的 `v0.4.0` Release 是 **上游 v0.4.0 的镜像**：文件从 wyx2685/V2bX 的 v0.4.0 原样下载，逐个用上游 `.dgst` 校验 SHA-256 后上传，tag 指向同一个提交 `3deccaa`。以后的版本由本仓库自己构建。

---

## 3. 同步上游（可选）

上游仍在更新时，可以把改动合并进来：

### V2bX 程序

```bash
cd V2bX
git remote add upstream https://github.com/wyx2685/V2bX.git   # 只需一次
git fetch upstream --tags
git checkout dev_new
git merge upstream/dev_new          # 有冲突就解决后 git commit
git push origin dev_new
# 想发布就打 tag（可以沿用上游版本号，例如上游出了 v0.4.2）：
git tag v0.4.2 && git push origin v0.4.2
```

注意：合并时 `.github/workflows/release.yml` 可能冲突，**保留本仓库的版本**（它负责在 tag 推送时发布 Release，上游版本依赖 Release 事件和第三方 Action）。`git fetch upstream --tags` 会拉下上游的 tag，推送时只推你自己要发布的那个 tag，不要 `git push --tags`。

### 管理脚本

```bash
cd V2bX-script
git remote add upstream https://github.com/wyx2685/V2bX-script.git   # 只需一次
git fetch upstream
git diff main upstream/master -- V2bX.sh initconfig.sh install.sh    # 先看上游改了什么
```

不建议直接 merge（本仓库的脚本改动较多）。推荐看完 diff 后，把需要的改动手工搬过来，然后：

- 确认没有引入新的第三方地址：`grep -n 'wyx2685\|http' V2bX.sh initconfig.sh install.sh`
- 确认上游没有重新加入统计请求（例如 `api.v-50.me/counter_v2bx`）
- 跑检查：`bash -n *.sh && shellcheck -S error install.sh V2bX.sh initconfig.sh`

---

## 4. 修改仓库主人 / 地址（改一处即可）

每个脚本顶部都有一个 **Repository constants** 常量块：

```bash
REPO_OWNER="${V2BX_REPO_OWNER:-liusu2100-sys}"
SCRIPT_REPO="${V2BX_SCRIPT_REPO:-${REPO_OWNER}/V2bX-script}"   # 脚本仓库
SCRIPT_BRANCH="${V2BX_SCRIPT_BRANCH:-main}"                    # 脚本分支
CORE_REPO="${V2BX_CORE_REPO:-${REPO_OWNER}/V2bX}"              # 程序仓库（Releases）
```

- 换 GitHub 用户名 / 组织：只改 `REPO_OWNER`。
- 仓库改名或分支改名：改 `SCRIPT_REPO` / `CORE_REPO` / `SCRIPT_BRANCH`。
- 需要改的文件：`install.sh`、`V2bX.sh`、`initconfig.sh`（三个脚本各自独立运行，所以各有一份，**改的时候三个都改成一样**），再把文档里的链接（`README.md`、`docs/INSTALL.md`、本文件）批量替换：

  ```bash
  grep -rl 'liusu2100-sys' README.md docs | xargs sed -i 's#liusu2100-sys#新用户名#g'
  ```

- 临时测试别的仓库（不改文件）：所有常量都可以用 `V2BX_` 前缀的环境变量覆盖，例如

  ```bash
  V2BX_REPO_OWNER=someone bash install.sh
  ```

- `V2bX.sh` 里还有 `BBR_SCRIPT_URL`（菜单 11，第三方 BBR 脚本，见第 5 节）。

---

## 5. 剩余的外部依赖

「脱离第三方」指的是：安装/更新/管理过程只访问你自己的仓库，不再依赖原作者的仓库、Release 或统计服务。以下依赖仍然存在，属于基础设施或可选功能：

| 依赖 | 何时用到 | 说明 / 替代方案 |
| --- | --- | --- |
| **GitHub**（`github.com`、`api.github.com`、`raw.githubusercontent.com`、`objects.githubusercontent.com`） | 每次安装/更新 | 托管脚本与 Release。API 未登录每小时 60 次限制，超限时可直接指定版本号安装。若要彻底不依赖 GitHub，需要自建下载站并修改常量块里的 URL 格式。 |
| **系统软件源**（yum/dnf/apt/apk/pacman 镜像，EPEL） | 安装依赖 wget curl unzip tar cron socat ca-certificates | 由各发行版提供；EOL 系统需切换归档源。 |
| **GitHub Actions 运行环境** 及官方 Action：`actions/checkout`、`actions/setup-go`、`actions/upload-artifact` | 构建 Release | GitHub 官方维护。已去掉第三方 `svenstaro/upload-release-action`，改用 Runner 自带的 `gh` 命令上传。 |
| **Go 工具链与 Go 模块**（`proxy.golang.org` 及各模块源仓库：Xray-core、sing-box、hysteria、lego 等） | 构建时 | V2bX 本身就是基于这些项目编译的，属于源码依赖；版本锁定在 `go.mod` / `go.sum`。 |
| **Loyalsoldier/v2ray-rules-dat**（`geoip.dat`、`geosite.dat`） | **仅构建时**下载并打进 zip | 运行时和更新时不会再去下载。想去掉这个依赖：把这两个文件上传到你自己的地方（例如本仓库或某个 Release），然后修改 `release.yml` 里的 `GEO_DAT_BASE_URL`。 |
| **ylx2016/Linux-NetSpeed `tcpx.sh`** | 仅当在菜单中选 **11（一键安装 bbr）** | 第三方脚本（会更换内核），不在本仓库维护；不用就不会访问。地址在 `V2bX.sh` 的 `BBR_SCRIPT_URL`。 |
| **v2bx.v-50.me 文档站** | 只在文档里作为参考链接 | 脚本不会访问。 |
| **ghcr.io**（V2bX 仓库的 “Publish Docker image” 工作流） | 仅当在 GitHub 网页上手动发布 Release 或手动运行该工作流时（Actions 自动发布不会触发它） | 与一键安装无关；不需要 Docker 镜像可以在 Actions 中禁用该工作流。 |

---

## 6. 发布脚本改动后的检查清单

```bash
bash -n install.sh V2bX.sh initconfig.sh
shellcheck -S error install.sh V2bX.sh initconfig.sh
grep -n 'wyx2685' install.sh V2bX.sh initconfig.sh   # 只允许出现在注释里（致谢）
docker run --rm -v "$PWD":/t:ro debian:12 bash /t/tests/smoke.sh /t/install.sh
git push origin main
```

推送到 `main` 后立即生效（raw.githubusercontent.com 可能有几分钟缓存）。
