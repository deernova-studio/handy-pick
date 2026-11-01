# One 共享签名凭据与 macOS 发布

证书、私钥和公证授权只保存在 One 使用的 Infisical 共享凭据库中。本机通过 `one exec --global` 获取；GitHub Actions 用 OIDC 临时身份从同一项目、环境和目录获取，不再复制 Apple 凭据到 GitHub Secrets。

## 一次性配置

1. 在 https://app.infisical.com 注册账户并创建组织，然后在 Mac 终端运行 `one login`，选择同一组织。One 会创建或找回 `shared-credentials` 项目。
   首次在共享项目的 Production 环境建立 `apple/macos` 目录。当前 One 的全局写入不会自动创建缺失目录；新设备复用这个已有目录即可，无需再建。
2. 准备有效的 **Developer ID Application 证书及私钥**（带密码的 P12），以及 Apple App 专用密码。可以创建新证书，也可以复用旧证书；Apple Development 不能替代 Developer ID。
3. 在 HandyPick 仓库的本机终端运行 `one run quick-snap:signing-setup`。确认显示的共享凭据库后，输入 P12 路径、导出密码、Apple 账户邮箱、Team ID 和 App 专用密码。密码只在终端隐藏输入，不发到聊天、不写入命令历史。
4. 导入工具先用临时钥匙串验证证书及 Apple 公证登录，再通过 `one env set --stdin` 写入。也可以在 One Desktop 的 Shared credentials 页面手动配置下面五项。
5. 执行 `one run quick-snap:signing-check`，验证从云端取用的完整链路。

固定位置：共享凭据项目，环境 **prod**，目录 **/apple/macos**。

| 变量 | 内容 |
| --- | --- |
| MACOS_CERTIFICATE_P12_BASE64 | 同时包含 Developer ID 证书和私钥的 P12，Base64 编码；导入工具自动转换 |
| MACOS_CERTIFICATE_PASSWORD | P12 导出密码 |
| APPLE_ID | 拥有对应团队公证权限的 Apple 账户邮箱 |
| APPLE_TEAM_ID | 10 位开发者团队 ID |
| APPLE_APP_SPECIFIC_PASSWORD | Apple App 专用密码，不是账户登录密码 |

这些共享项可供同一团队的其他 macOS 项目复用。不要在此目录放无关凭据。覆盖现有项会影响所有引用它们的项目；更新凭据后先执行 signing-check，再发布。

## 换一台 Mac

安装 Xcode、包含 Swift 支持的 One CLI，并克隆仓库，然后：

```sh
one login
one mise trust
one mise install
one run quick-snap:signing-check
one run quick-snap:release
```

登录同一 Infisical 账户与组织即可找回共享凭据，不用再次导入 P12、配置 Apple ID 或手动建立 notarytool profile。自建服务需在登录时指定 `--site-url`。证书或密码过期、撤销、账户权限变化时，需要在中心位置更新；新设备仍需登录授权。

## GitHub Actions 首次授权

One 当前使用浏览器用户会话，不能把个人 session.json 复制到 CI。CI 使用 Infisical 官方 OIDC Action，并指向 One 的同一个 shared-credentials 项目。

在 Infisical 组织创建专用 Machine Identity，启用 OIDC，并添加到该共享凭据项目；仅授予读取 prod 环境 /apple/macos 的所需权限，不授予写入或管理权限。

当前账户套餐不支持创建自定义权限角色，目录授权也受套餐限制。CI 的最小权限授权尚未完成；不要直接改成整个共享项目的 Viewer 来绕过限制，否则它会读取将来放在其他目录的凭据。现阶段本机的 One 登录取用不受此限制。CI 需另行选定支持目录授权的配置后再启用；仓库 Variables 尚未填写时，流水线会在准备阶段明确停止。

OIDC 配置（当前仓库的真实 immutable subject，不能省略数字 ID）：

| 配置 | 值 |
| --- | --- |
| Discovery URL / Issuer | https://token.actions.githubusercontent.com |
| Subject | `repo:deernova-studio@350152411/quick-snap@1441079779:ref:refs/heads/main` |
| Audience | `one-macos-signing` |
| Claims | `repository_id=1441079779`、`ref=refs/heads/main`、`event_name=workflow_dispatch` |
| Access Token TTL / Max TTL | 3600 秒 |

参考 [Infisical 官方 GitHub OIDC 文档](https://infisical.com/docs/documentation/platform/identities/oidc-auth/github)。仓库更名、转移或自定义 OIDC subject 后，重新用 `gh api repos/deernova-studio/quick-snap/actions/oidc/customization/sub` 核对配置。

在 [GitHub Actions Variables](https://github.com/deernova-studio/quick-snap/settings/variables/actions) 设置：

- `INFISICAL_IDENTITY_ID`：上述 Machine Identity ID。
- `INFISICAL_PROJECT_SLUG`：One 共享凭据项目的 slug，不是项目显示名或 ID。
- `INFISICAL_SITE_URL`：可选，默认 https://app.infisical.com。

这些是非敏感定位信息，无需再存 Apple 证书或密码到 GitHub。现有旧 Secrets 不再被此流水线读取；确认新流程成功后可自行移除。后续新增仓库仍需授权对应的 CI 身份，但不需要重复上传证书。

## 发布与恢复

本机：`one run quick-snap:release`。使用 QUICK_SNAP_VERSION / QUICK_SNAP_BUILD_NUMBER 指定新版本；默认读取应用 Info.plist。

云端：将代码合入 main 后，在[发布 macOS 版本](https://github.com/deernova-studio/quick-snap/actions/workflows/release.yml)手动填写版本、构建号和说明。流水线固定源码提交，检查后获取凭据；随后签名、公证、验证，再创建并校验草稿 Release，最后发布到私有仓库。普通 push / PR 不触发发布。

应用与 DMG 均签名、公证、装订票据并通过 Gatekeeper 检查后，最终产物才写入 `apps/quick-snap/build/releases`。不会覆盖现有版本或移动已发布标签。

本机公证中断时，保留原候选，用相同版本/构建号执行 `one run quick-snap:notarize` 继续。不要重跑 release 覆盖候选。云端 runner 是临时机器；公证失败后重新构建应使用新构建号。只有 publish 作业失败时，可以 Re-run failed jobs 继续原有草稿。

签名包装器每次建立独立临时钥匙串，通过显式参数选择它，不修改默认钥匙串。执行构建期间将临时钥匙串加入用户搜索列表，以便 codesign 解析证书链；结束时移除该项并保留其他钥匙串。原始 P12 导入后立即删除，原始密码不传给构建子进程；成功、失败及 SIGINT/SIGTERM 退出都会清理钥匙串。断电或 SIGKILL 无法执行进程清理；如出现此情况，可删除系统临时目录中该次 `one-macos-signing-*` 残留。流水线日志由官方 Action 屏蔽注入的值，脚本不回显密钥或 Apple 认证命令输出。

`signing-setup` 的终端交互标记由根 mise.toml 中对应任务的 `interactive = true` 保留；当前 One 的 Taskfile 发现器不传递这个字段。`one init mise` 会保留该手动扩展项。

`one run quick-snap:pack` 仍只生成本地临时签名、未公证的 DMG，不读取共享凭据。源码 bootstrap 仅用于 CI 准备尚未正式发版的 Swift 支持；本地安装方式见 README。
