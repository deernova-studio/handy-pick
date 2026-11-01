# HandyPick application

Native macOS menu-bar app using SwiftPM. Sources, resources, tests and packaging
scripts stay together here. The bundle identifier is `studio.deernova.quick-snap`.

原生 macOS 菜单栏应用，保留 SwiftPM 工程与现有应用身份。
使用方法见[仓库说明](../../README.md)，签名与 CI 见[发布说明](../../docs/github-actions.md)。

From the workspace root / 在仓库根目录运行：

```sh
one run handy-pick:check
one run handy-pick:build
one run handy-pick:dev
one run handy-pick:pack
```

After editing Taskfile.yml, run `one init mise` at the workspace root.
修改 Taskfile 后，在仓库根目录运行 `one init mise` 同步任务。
`dev` runs in the foreground; stop the One task to stop that development instance.
开发实例由 One 管理进程，停止任务即可退出；请先退出其他 HandyPick 实例，避免重复监听。
