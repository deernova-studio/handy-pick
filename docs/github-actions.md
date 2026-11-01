# 签名 DMG 与手动发布

本流程参考 deernova-studio/linse：仅手动运行，在 GitHub 托管 Mac 中测试、构建 arm64 应用、Developer ID 签名、Apple 公证，最后发布到本仓库的私有 Release。普通 push 和 PR 不启动构建。

## 首次配置

打开 [Actions Secrets](https://github.com/deernova-studio/quick-snap/settings/secrets/actions)，配置与 linse 相同的三个仓库 Secrets：

| 名称 | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | 包含 Developer ID Application 证书和私钥的 p12，以 Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | p12 导出密码 |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple 公证用的 App 专用密码 |

不使用 Apple Development 证书替代 Developer ID，不使用 Apple 登录密码或 Mac 开机密码。私钥与密码只填 GitHub Secrets，不提交到 Git。GitHub 已保存的仓库 Secrets 无法通过 API 读出后复制，需使用原始签名资料配置新仓库。

在 Variables 中设置 `APPLE_ID` 和 `APPLE_TEAM_ID`，需与签名身份的开发者团队一致。这两项可以参考 linse 的变量；三个 Secrets 也必须属于同一团队。

云端只在签名步骤注入 Secrets，使用临时钥匙串，结束时始终清理。下载和发布使用任务自带的 GITHUB_TOKEN，无需额外 PAT。

## 发布

1. 推送已完成实际交互测试的代码到 main。
2. 打开 [发布 macOS 版本](https://github.com/deernova-studio/quick-snap/actions/workflows/release.yml)，选择 Run workflow 和 main。
3. 填写版本号、构建号与更新说明。首次建议 0.2.1 / 15，后续使用新版本号。
4. 到 [Releases](https://github.com/deernova-studio/quick-snap/releases) 下载 `QuickSnap-<版本号>-macOS-arm64.dmg` 和 `SHA256SUMS.txt`。仓库及附件保持私有。

只允许从 main 发布。发布指向本次运行的固定提交；先验证版本和配置，再测试、编译、签名、公证。应用先附上公证票据，再制作带 Applications 快捷入口的 DMG；DMG 本身也签名、公证、附票并通过 Gatekeeper 和完整性验证。

最后创建草稿 Release，上传 DMG 和校验文件；GitHub 返回的 SHA-256 匹配后才发布。不会覆盖已有版本或移动已有标签。同一次运行上传失败，可 Re-run failed jobs 继续自己的草稿。Actions 临时附件保留 7 天，正式 Release 附件不受此限制。

## 本机验证与打包

```sh
one run quick-snap:check
one run quick-snap:pack
```

本地按仓库 README，在 One CLI 源码仓库执行 `one install` 安装开发版。CI 则在独立 runner 上从固定提交构建 One，通过 `one run` 调用本地相同的检查、签名和公证任务；签名凭据仍由 GitHub Secrets 注入临时钥匙串。

本机开发打包输出到 apps/quick-snap/build/distribution-dev，不替换已安装的 Quick Snap，也不修改现有权限。

本机持有正式证书与钥匙串公证授权时：

```sh
SIGNING_IDENTITY='Developer ID Application: 你的证书名称 (TEAMID)' \
NOTARY_PROFILE='你的钥匙串公证配置名' \
one run quick-snap:release
```

正式产物只在应用和 DMG 的公证、票据及 Gatekeeper 验证全部通过后写入 apps/quick-snap/build/releases。公证中断保留提交 ID，可重运行继续等待。正式候选目录不会被覆盖，修改候选内容前应换用新构建号。

适用于 Apple 芯片、macOS 14+。流水线验证脚本、Swift 核心测试和 Release 编译；真实鼠标、键位录入、屏幕录制权限、多屏和输入框粘贴兼容性仍需实机测试。正式分发签名与本机开发签名不同，首次安装后 macOS 可能要求重新授权。

公证等待中断后，用相同的 `QUICK_SNAP_VERSION`、`QUICK_SNAP_BUILD_NUMBER` 和 `NOTARY_PROFILE` 执行 `one run quick-snap:notarize` 继续原候选，不要重新执行 release 覆盖候选。`release` 只签名公证，上传 GitHub Release 仍由手动流水线负责。
