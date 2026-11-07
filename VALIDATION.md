## 2026-11-07 随取 / handypick 0.4.30 build 52

- 整体审查自 0.4.23 以来的快捷键、终端路由、截图编辑、菜单栏外观与发布配置。修复历史图片选字时撤销导致选字状态丢失；工具栏撤销与 Command+Z 均恢复实况文本。
- 截图移动增加 3 点起拖阈值：普通单击与微小抖动不再隐藏工具栏或移动选区。终端复制等待后重新检查 AX 目标期间，如果剪贴板已变化，取消后续粘贴，避免迟到的复制或其他写入被误粘贴。
- One check 通过：67 项 Swift 测试、26 项 Python 测试和 arm64 Release 编译；回归覆盖撤销后恢复选字、单击及微小位移不隐藏工具栏，既有移动、双击确认、组合键与终端区域边界测试继续通过。
- 真实 Codex 内嵌终端实体中键端到端、macOS 14 实机兼容性仍未完成验证。本次不将独立测试窗口或单元测试视为上述场景已修复的证据。
- One release 完成 Developer ID 签名、应用及 DMG 的 Apple 公证与附票、Gatekeeper 验证。本机已安装启动 0.4.30 build 52，单实例且事件 tap 为 enabled；Downloads 中 DMG 与 SHA256SUMS 一致。

# 验证记录

## 2026-11-07 随取 / handypick 0.4.29 build 51

- One release 签名、公证、附票及 Gatekeeper 检查通过；本机已安装启动 0.4.29，事件监听启用。DMG 已复制到 Downloads 并核对 SHA-256，尚未发布。
- 截图框选完成默认无标注工具，内部拖动移动整个选区，八个手柄仍调整大小；标注工具显式选中后绘制，再次点击退出标注回到移动。历史图片继续默认实况文本。
- 以起始矩形与拖动差量计算移动，保持尺寸、夹紧到当前屏幕边界；已有标注按实际偏移同步移动，拖动时隐藏工具栏，松开重排工具栏。中间双击确认保持。
- One check：67 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。新增双轴移动／越界夹紧、默认移动无误标注、标注随选区移动后像素对比、退出标注与工具栏跟随的回归；更新原来默认划线的测试以显式选工具。
- 独立原生窗口使用实际 SelectionView 实测：300×200 选区向右 100、向下 40 点移动，工具栏跟随；随后双击确认返回 300×200 图片。

## 2026-11-07 随取 / handypick 0.4.28 build 50

- One release 签名、公证、附票及 Gatekeeper 验证通过；本机已安装启动 0.4.28，单实例事件监听启用。DMG 已放入 Downloads 并核对 SHA-256，尚未发布。
- 用户反馈 Shift+P 仍常无法使用。发现双击模式下仅带 Shift 的绑定仍进入 TypingFocus，编辑焦点或未知／超时会放行打字并取消快捷操作；组合键模式已有直接绕过规则。
- needsTypingProtection 改为只对无修饰键的普通键启用；所有明确绑定的 Shift/Command/Control/Option 组合在两种模式下均不查询输入框焦点。不修改用户的模式或已录入按键。
- One check：65 项 Swift、26 项 Python 测试与 arm64 Release 编译通过。新增 Shift+P 经过按下、松开与触发识别器的回归：输入区查询不可用时仍不调用该查询，组合键模式每次触发、双击模式两次触发一次；普通键打字保护仍保留。
- 当前 Mac 读取到的配置是双击中键、另存组合键为 Option+V，不能据此断言用户报告的 Shift+P 问题全部源于上述分支。用户随后确认是完全没反应；尚未确认故障机器和当时的触发模式。触发后的复制、粘贴、截图路由与终端真实验收保持独立。

## 2026-11-07 随取 / handypick 0.4.27 build 49

- One release 签名、公证、附票及 Gatekeeper 检查通过；本机已安装启动 0.4.27，单实例事件监听启用。签名 DMG 已放入 Downloads 并核对 SHA-256，尚未发布。
- 菜单栏图标原先使用固定白色且 isTemplate=false，浅色背景易丢失对比。改为黑色 alpha 模板并启用 isTemplate，由 NSStatusButton/AppKit 处理实际菜单栏外观与高亮；22×18 画布、圆角底和内部镂空尺寸均保持。
- One check：64 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。此项为显示属性修正，未新增镜像实现的测试。
- 独立原生窗口使用同一 MenuBarIcon，在 aqua/darkAqua 两种 NSButton 外观及白／深灰背景下检查，图标与镂空均可辨认。未更改用户全局外观设置；macOS 14 实机菜单栏效果尚未验证。

## 2026-11-07 随取 / handypick 0.4.26 build 48

- One release 签名、公证、附票和 Gatekeeper 验证通过；本机已安装启动 0.4.26，单实例事件监听启用。签名 DMG 已放入 Downloads 并校验 SHA-256，尚未发布。
- 截图编辑阶段在选区内部双击左键，执行与勾号相同的确认回调；清除未提交的零长度标注，保留已完成的划线、画圈、文字。单击不确认，选区外与缩放手柄不确认，文字工具、OCR 和历史图片预览保留原交互。
- One check：64 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。新增完整双击序列与勾号输出像素一致性、只触发一次、边缘／外部／文字／OCR 不误确认的回归测试。
- 独立原生窗口实测拖动框选后双击中间，完成回调返回 520×260 截图。复用了应用实际 SelectionView；不是模拟直接调用完成方法。
- Codex 内嵌终端的真实中键验收仍待确认，不将本次截图交互验证视为终端问题已解决。

## 2026-11-05 随取 / handypick 0.4.25 build 47（待真实 Codex 复测）

- One release 签名、公证、附票及 Gatekeeper 检查通过；本机已安装启动 0.4.25，单实例且事件监听启用；DMG 已复制至 Downloads 并校验 SHA-256，尚未发布。
- 用户实测 0.4.24 选字后仍截图。运行日志确认 terminal helper 与两层 terminal surface 已找到，但关系／坐标检查未通过；同一时段其他触发已走到粘贴。
- 对画布文字的 hit-test 返回外层 AXGroup/AXWebArea/AXScrollArea，允许命中节点是终端 surface 的祖先；仍必须处于明确的 xterm 区域坐标内，保持前台、命中与焦点进程一致，拒绝不相关覆盖层、侧栏和聊天区。增加对应回归测试与固定结构计数日志。
- 纠正 0.4.24 的复制快捷键错误：本机 Codex 代码中 Ctrl+Shift+C clipboard handler 受非 macOS 条件限制；macOS 应使用原生 Cmd+C copy 事件。已改为 Cmd+C，并避免再次聚焦已聚焦的终端输入控件。
- One check：62 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。测试后仅补充无内容的诊断计数；最终 Release 构建再次编译验证。
- 移除独立 Electron/xterm fixture 中人为添加的 Ctrl+Shift+C 处理器，以原生 macOS 行为实测：选中自建测试行后 Cmd+C 得到该测试行；无选区 Cmd+C 不改变剪贴板 changeCount；Cmd+V 收到相同文本字节，未发送回车或连接 shell。真实 Codex 中键路径尚待用户验证。

## 2026-11-05 随取 / handypick 0.4.24 build 46（实测失败，见 0.4.25 修正）

- One release 签名、公证、附票和 Gatekeeper 检查通过，本机已安装启动 0.4.24，确认单实例与一条启用的事件监听；DMG 已复制到 Downloads，SHA-256 校验通过。尚未发布 GitHub。
- 用户明确出问题的是 Codex 内嵌终端；0.4.22 的 com.apple.Terminal 规则未覆盖此场景。
- 新增 Codex xterm 路径：要求聚焦 xterm-helper-textarea、启用且非安全输入，鼠标命中与焦点共享明确的 xterm/xterm-screen 祖先，坐标在该区域内且前台进程一致。不会用整个 Codex 窗口或 Web 文档代替终端范围。
- xterm 的 helper 可能保留上次粘贴的值，因此先走终端自身选区处理，避免把 helper 的 AXSelectedText 当作真实选区。仅针对该终端发送其 Ctrl+Shift+C 复制选区快捷键；观察剪贴板变化，无变化时重新确认同一个焦点及终端区域后粘贴。不会发送 Ctrl+C，也不读取终端全文。
- One check：61 项 Swift、26 项 Python 测试与 arm64 Release 编译通过。覆盖精确 xterm 标记、拒绝普通控件／近似类名／安全或禁用输入；既有前台与坐标边界测试保持通过。
- 独立 Electron 40 + xterm 5.5 测试窗口复现 Codex 的复制选区快捷键语义，实际拖选自建测试行后复制、清除选区后粘贴成功，未发送回车，也未连接 shell。此测试验证复制流程，不等同于真实 Codex 的 AX 祖先匹配与实体中键端到端验收。
- 当前桌面工具禁止直接操作 Codex，真实内嵌终端需用户复测。诊断只记录固定结构状态和计数，不记录终端内容、选区、标题或剪贴板值。

## 2026-11-05 随取 / handypick 0.4.23 build 45

- One release 签名、公证、附票及 Gatekeeper 检查通过。本机已安装启动 0.4.23，单实例事件监听启用；签名 DMG 已放入 Downloads 并核对 SHA-256。以上为发布前验证。
- 历史图片预览自动启用本机实况文本，隐藏 OCR 工具按钮和识别状态文案；标注工具可切换，取消标注后恢复选字。未选中文字时勾号仍复制图片，选中文字时复制选区。
- 设置键位按钮改为原生 NSButton，与原生触发菜单和分类分段控件统一 regular 尺寸，通过 AppKit alignment rect 对齐可见边框，避免不同系统的边框／阴影偏移。
- One check：60 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。覆盖预览打开自动识别、取消／恢复选字、无选区复制图片、移除 OCR 按钮与三种控件对齐矩形。
- 原生测试窗口验证无需点击 OCR 即可选中英文测试词与拖选中文；⌘C 后仅检查剪贴板是否等于自建测试词 HandyPick，结果通过。设置行与筛选自适应高度已检查。未在 macOS 14 实机验证。

## 2026-11-05 随取 / handypick 0.4.22 build 44

- One release 签名、公证、附票及 Gatekeeper 检查通过。本机已安装启动 0.4.22，单实例事件监听启用；签名 DMG 已放入 Downloads 并核对 SHA-256。以上为发布前验证。
- 用户反馈终端中双击中键进入截图，本机固定状态日志确认 selected-text-copied 后两次 no-input-capture。用户随后确认是 macOS 自带 Terminal；已实现专用规则，尚未测得真实 Terminal AX 属性。
- 仅 com.apple.Terminal 当前聚焦的 AXTextArea、启用且非安全控件、鼠标在其边界内、命中进程／焦点进程／前台进程一致时，允许粘贴。一般只读文本框仍拒绝；既有选区复制优先级及粘贴前焦点确认保留。
- One check：60 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。回归覆盖终端控件分类、非终端／非文本区拒绝、禁用／安全控件拒绝、鼠标在标题或边界外、前台／焦点／命中进程不一致时拒绝。
- 桌面工具明确禁止操作 com.apple.Terminal，未通过其他工具读取其 UI 或输入测试命令；真实终端的实体中键粘贴待用户复测。

## 2026-11-05 随取 / handypick 0.4.21 build 43

- One release 签名、公证、附票及 Gatekeeper 检查通过。本机已安装启动 0.4.21，单实例事件监听启用；签名 DMG 已放入 Downloads 并核对 SHA-256。本次尚未发布 GitHub Release。
- 设置右侧分类改为原生 NSSegmentedControl 图标分段切换，共用圆角底座，选中段高亮。控件高度由 28 改为 24 点，与键位按钮共享 y=16 和中线；保留竖分隔线、悬停名称与系统无障碍单选语义。
- One check：59 项 Swift、26 项 Python 测试及 arm64 Release 编译通过；更新既有分类交互测试。原生测试窗口实际切换图片分类并检查截图，确认连体外观、第一行视觉对齐与筛选正常。

## 2026-11-05 随取 / handypick 0.4.20 build 42

- One release 签名、公证、附票及 Gatekeeper 检查通过。本机已安装启动 0.4.20，单实例事件监听启用；签名 DMG 已放入 Downloads 并核对 SHA-256。本次尚未发布 GitHub Release。
- 有历史时，分类图标移动至设置行右侧，键位与图标之间增加 20 点高的竖分隔线；无历史时两者隐藏。保持 360 点面板宽度，键位区域为 120 点，网格上移 32 点恢复原单行／双行／三行高度。
- One check：59 项 Swift、26 项 Python 测试及 arm64 Release 编译通过；更新既有自适应高度断言。原生测试窗口确认同一行设置、竖线、图标及图片分类正常，无额外分类行。

## 2026-11-04 随取 / handypick 0.4.19 build 41

- One release 签名、公证、附票及 Gatekeeper 检查通过。本机已安装启动 0.4.19，单实例事件监听启用；签名 DMG 已放入 Downloads 并核对 SHA-256。本次尚未发布 GitHub Release。
- 分类切换改为靠左的三个独立 SF Symbols 图标，使用现有 PaperlightButton；选中项圆角浅底，未选项透明底，悬停提示与无障碍名称保留「全部／图片／文字」。筛选、高度与空分类行为保持。
- One check：59 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。更新既有分类交互测试以使用独立图标按钮，无新增镜像测试。
- 原生测试窗口实际点击图片、文字分类并检查截图，确认选中态与单行网格正常。

## 2026-11-04 随取 / handypick 0.4.18 build 40

- One release 签名、公证、附票及 Gatekeeper 检查通过。本机已安装启动 0.4.18，单实例事件监听启用；签名 DMG 已放入 Downloads 并核对 SHA-256。本次尚未发布 GitHub Release。
- 历史面板增加原生「全部 / 图片 / 文字」筛选，保留三列网格、最多三行滚动和自适应高度。无记录时隐藏筛选栏，空类别禁用；删除当前类别最后一条时回到全部。本次运行保留筛选，新记录到来仍按当前类别显示。
- One check：59 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。新增分类后复制和预览仍指向原记录、切换回顶部、分类自适应高度、筛选保持、空分类回退、清空后折叠回归。
- 原生测试窗口实际切换图片与文字分类，确认单张图片和三张文字均为单行高度，筛选和卡片布局正常。未读取用户剪贴板作为样例。

## 2026-11-04 随取 / handypick 0.4.17 build 39

- One release 签名、公证、附票及 Gatekeeper 检查通过。本机已安装启动 0.4.17，单实例事件监听启用；签名 DMG 已放入 Downloads 并核对 SHA-256。本次尚未发布 GitHub Release。
- 截图与历史图片工具栏新增「识别并选取文字」，使用 VisionKit ImageAnalyzer 与 ImageAnalysisOverlayView，在当前裁切结果上本地识别并直接拖选文字；保持原图显示，仅选中文字高亮。工具栏沿用 Paperlight 组件，七项控件统一使用 306 点宽度。
- ⌘C、右键复制所选文字，勾号复制所选／无选区时复制全部，右键另有复制全部；复制后保持识别模式，反馈使用现有指针旁提示。Esc、再次点识别、切换标注或调整边缘退出选字；调整后重新识别最新裁切内容。关闭或退出时取消待处理任务，空结果不覆盖剪贴板。
- One check：58 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。含真实 VisionKit 中英文识别、部分范围复制、空白图片不覆盖剪贴板、退出识别与历史预览调整尺寸回归；独立 pasteboard 不触及用户剪贴板。
- 独立原生测试窗口实测中英文测试图：在图上拖选 HandyPick 后 ⌘C，剪贴板仅为该测试词；拖选中文部分并右键复制，剪贴板为选中的“随取图片文字识别”。观察原图只高亮选择部分，确认 Esc 恢复编辑、拖动截图右边缘自动退出识别。未在 macOS 14 实机验证。

## 2026-11-04 随取 / handypick 0.4.16 build 38

- 原生测试窗口实际完成初始框选、划线、拖动右边与左上角，确认控制点、标注位置和工具栏跟随；调整后的导出尺寸确认为 620 × 300。自动化未单独验证实体鼠标悬停时的光标显示。
- One release 签名、公证、附票及 Gatekeeper 验证通过；本机已更新启动 0.4.16，单实例且事件 tap 已启用。签名 DMG 已复制至 Downloads 并核对 SHA-256；以上为发布前验证。
- 框选后支持拖动四边与四角调整截图范围，边缘显示对应方向的缩放光标和小控制点；不改变历史图片编辑器的整图编辑模式。
- 边缘拖动优先于标注，保留按下位置相对边缘的偏移，限制在当前屏幕范围内且不允许选区反转或小于 3 点。拖动期间隐藏工具栏，结束后复用原工具栏并重新定位，保留当前标注工具。
- 标注固定在原图坐标，收缩时仅裁切显示，扩大时恢复原标注；调整范围不会被误记成新线条，撤销仍作用于标注。
- One check：55 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。新增八方向边界、屏幕限制、最小尺寸，以及带标注缩小再扩大后像素一致、文字工具下优先缩放、工具栏复用与导出尺寸回归测试。

## 2026-11-03 随取 / handypick 0.4.15 build 37

- One release 签名、公证、附票及 Gatekeeper 检查通过；本机已安装启动 0.4.15，单实例且事件 tap 已启用。DMG 已复制到 Downloads 并核对 SHA-256，尚未发布 GitHub Release。
- 用户截图标出 API Key 密码输入框，日志确认中键触发后进入 no-input-capture。代码存在两处密码框拒绝：命中遍历提前返回 nil、canPaste 拒绝 secure，导致密码框被按截图区域处理。
- 允许向未禁用、未明确只读的 AXSecureTextField（AXTextField 角色）发送已有剪贴板的粘贴；仍先验证焦点。选区复制对 secure 的拒绝保持，不读取或记录密码值，也不放宽未知容器的粘贴资格。
- One check：52 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。覆盖密码框没有值／选区 setter 时仍可粘贴、禁止复制密码内容、禁用／只读框拒绝，以及鼠标中键和侧键不查询打字保护。
- 未操作用户 API Key 或使用真实凭据实测；用户应用输入框的端到端结果待验证。

## 2026-11-03 随取 / handypick 0.4.14 build 36

- One release 签名、公证、附票及 Gatekeeper 检查通过；本机已安装启动 0.4.14，单实例监听正常。DMG 已放入 Downloads 并校验 SHA-256，尚未发布 GitHub Release。

- 截图文字工具使用明确的 T 字符，不再显示会随系统语言本地化的 textformat 符号；保留「文字」无障碍名称与提示。
- 历史图片放大后复用 SelectionView 的划线、画圈、文字、撤销、取消和确认工具，直接编辑整张图片。确认后复制新图并加入会话历史，原图保留；取消／关闭不写入剪贴板。
- 图片按比例适配窗口，标注使用固定逻辑坐标，工具栏独立放在图片下方；初始字号匹配实际显示点数，调整窗口大小不改变标注位置或导出分辨率。
- One check：50 项 Swift、26 项 Python 测试与 Release 编译通过。新增整图编辑、原始分辨率输出、缩放前后像素一致、撤销恢复原图回归；截图既有文字／椭圆／线条流程通过。
- 独立原生窗口实际查看 T 与全部工具栏按钮，并点击 T 在预览图上输入、提交文字标注。未读取用户剪贴板或截图内容作为样例。

## 2026-11-03 随取 / handypick 0.4.13 build 35

- One release 签名、公证、附票及 Gatekeeper 检查通过；本机已安装启动 0.4.13，单实例监听正常。DMG 已放入 Downloads 并校验 SHA-256，尚未发布 GitHub Release。

- 按用户明确规则，组合键模式按下即触发，不以输入焦点作为拦截条件，包括 Shift + Z。只有双击模式下的普通输入键保留输入保护；动作触发后的复制／粘贴／截图路由仍按原规则执行。
- 两处触发检查共用按模式判定逻辑，组合模式短路执行，不调用 TypingFocus，避免焦点查询超时或处于编辑器时阻止组合快捷键。
- One check：49 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。测试覆盖 Shift + Z 在编辑／焦点不可查询条件下不查询焦点仍触发、长按去重、双击模式继续保护正常输入。

## 2026-11-03 随取 / handypick 0.4.12 build 34

- One release 签名、公证、附票及 Gatekeeper 检查通过；本机已安装启动 0.4.12，单实例监听正常。DMG 已放入 Downloads 并校验 SHA-256，尚未发布 GitHub Release。

- 用户确认 macOS 14 录入的是 Shift + Z。此前组合模式只接受 Command／Control／Option，Shift-only 被静默拒绝，定位为跨系统共用的绑定校验问题。
- 组合模式接受含 Shift 的有效主键组合；Shift-only 沿用普通输入键焦点保护，输入框内仍放行大写字母。无效录入显示「请按修饰键 + 主键」，避免只显示等待提示。
- One check：48 项 Swift、26 项 Python 测试及 arm64 Release 构建通过。新增 Shift + Z 接受、序列化、单次触发及编辑时按下／重复／松开放行回归；未在用户 macOS 14 实机验证。

## 2026-11-03 随取 / handypick 0.4.11 build 33

- One release 签名、公证、附票及 Gatekeeper 检查通过；已安装启动本机 0.4.11，单实例事件监听正常。DMG 已放入 Downloads 并校验 SHA-256，尚未上传 GitHub Release。

- 触发方式控件从选中项覆盖按钮的 pop-up 改为向按钮下缘展开的 pull-down；隐藏标题项显示当前模式，实际两个选项独立维护勾选状态。
- 原生样例窗口中验证：双击模式展开、切换到组合键、组合键模式再次展开；菜单均位于控件下方，右侧键位按钮完整可见，模式标题和勾选状态正确。
- One check：47 项 Swift、26 项 Python 测试与 arm64 Release 编译通过；更新模式控件测试的索引、隐藏标题与 pull-down 状态断言。

## 2026-11-02 随取 / handypick 0.4.10 build 32

- One release 完成签名、公证、附票及 Gatekeeper 检查；已安装启动本机 0.4.10，单实例监听正常。签名 DMG 已复制到 Downloads 并核对 SHA-256；以上为发布前本地验证。

- 修正旧版 macOS 上应用图标呈现过大、不带圆角的资源问题：原渲染脚本将 1024 画布全部填白，现改为透明画布，内嵌 824 方形白底、184 圆角和 100 外边距；原始 BrandMark 与菜单栏图标保持不变。
- 重建全部 iconset 尺寸与 QuickSnap.icns，并从最终 icns 反向导出核对 16–1024 像素的透明边缘、圆角与不透明中心；资源预览已检查。未在 macOS 14 实机验收，不将当前系统的资源检查视作旧系统实测。

## 2026-11-02 随取 / handypick 0.4.9 build 31

- 第一行支持选择双击或组合键。双击沿用既有绑定，组合键独立保存，默认 ⌃⌥P；组合键需包含 Command、Control 或 Option，单次主键按下即触发。KeyPressGate 仍成对消费按下／重复／松开，普通输入键的焦点保护保持原行为。
- 历史卡片右上角悬停显示放大按钮，点击或右键菜单可预览图片和完整文字。图片保持比例，文字只读、可选择和滚动；预览可调整窗口大小，Esc 关闭。预览期间暂停全局快捷动作，删除／淘汰当前记录或清空历史时关闭预览并释放内容。
- One check：47 项 Swift、26 项 Python 测试与 arm64 Release 编译通过。新测试覆盖组合键有效性、按一次触发及长按去重、双击保留、模式切换、卡片预览不复制、按钮命中区域、完整文字／图片和清空后释放预览。
- 检查紧凑模式选择、悬停按钮、图片与长文字预览的原生渲染。独立样例窗口中实际操作验证触发方式切换、右键预览和 Esc 关闭；没有读取用户剪贴板内容。未将自动化样例操作当作实体键盘快捷键验收。
- One release 完成 Developer ID 签名、应用和 DMG 公证、附票及 Gatekeeper 校验。已更新 /Applications/HandyPick.app 为 0.4.9，确认单实例、单个启用的事件监听；保留原快捷键配置，0.4.8 安装备份位于 build/previous-installed-0.4.8.app。

## 2026-11-01 随取 / handypick 0.4.8 build 30

- 中文显示名称为「随取」，英文为「handypick」。通过 InfoPlist.strings 本地化，保留既有 Bundle ID、签名身份、可执行文件与安装路径；菜单提示和退出项使用同一本地化名称。
- 用独立测试应用的主 Bundle 分别指定 zh-Hans / en，确认 CFBundleDisplayName 与 Finder displayName 为「随取」/「handypick」；正式包中的两种语言资源与源码逐字节一致。
- One check：41 项 Swift、26 项 Python 测试及 arm64 Release 编译通过；git diff 空白检查通过。
- One release 完成 Developer ID 签名、应用与 DMG 的 Apple 公证、附票及 Gatekeeper 验证；正式文件名为 handypick-0.4.8-macOS-arm64.dmg。
- 已更新本机安装副本并启动 0.4.8，确认仅一个应用进程、一个已启用的快捷键事件监听；旧版保留于 build/previous-installed-0.4.7.app。

## 2026-11-01 HandyPick 0.4.7 build 29

- 用户实测确认焦点修复已正常，并授权提交、打包和发布。

- 修复 0.4.6 将所有网页／普通容器都放行的回归。已识别且不可编辑的 AXWebArea、AXGroup、AXScrollArea、AXWindow 恢复普通键快捷操作；可编辑、可设置文本值或选中文字的容器仍保留正常输入，真正未知角色和查询失败仍放行。
- 将 AX 控件读取与前台应用路由分离，使用独立 WKWebView 测试应用验证真实控件：页面背景 AXWebArea 返回允许快捷键；textarea 和 contenteditable 返回正常输入；再次点击背景恢复允许。查询只读取角色／可编辑性等元数据，不读取用户输入。
- One check 的 41 项 Swift、26 项 Python 测试及 arm64 Release 编译通过；增加可编辑与不可编辑容器对照回归。
- One release 完成签名、公证、附票及 Gatekeeper 验证。已安装启动 0.4.7，单实例快捷键监听启用，既有按键绑定保留；旧版位于 build/previous-installed-0.4.6.app。未上传 GitHub Release。

## 2026-11-01 HandyPick 0.4.6 build 28

- 按用户选择采用输入优先规则：普通键及仅带 Shift 的输入键，在输入焦点、通用／未知编辑器、AX 查询失败或超时时整次放行，不进入双击识别。仅明确的非编辑控件允许此类按键触发；鼠标、修饰键、F1–F20 和 Command／Control／Option 组合绑定保持原有行为。
- 焦点检查只读取角色、子角色与可编辑性元数据，不读取输入内容，也不缓存或重放键入字符。查询使用短超时；异步派发快捷动作前再次检查焦点。
- 按物理按下／松开周期固定放行或拦截决定，避免长按重复、按住时切换焦点或松开修饰键导致吞字或泄漏；输入期间取消待完成的普通键双击。
- One check：40 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。新增测试覆盖输入键与组合键分类、未知编辑器保护、正常字符及重复按键放行、焦点／修饰键变化时的成对处理、监控启动前已长按的按键放行。
- 原生焦点只读探针在前台 AXGroup 上返回放行；未读取控件内容。用户随后反馈回归：非输入网页背景也被放行；0.4.7 修正该分类。
- One release 完成签名、公证、附票及 Gatekeeper 验证；已安装启动 0.4.6，单实例事件监听启用，旧版保留于 build/previous-installed-0.4.5.app。既有快捷键设置未改动，未发布新 GitHub Release。

## 2026-11-01 HandyPick 0.4.5 build 27

- 按用户反馈移除剪贴板卡片中的「图片」「文字」类型标签，预览使用完整内容区域，保持 12pt 内边距。保留无障碍操作名称。
- One check 的 34 项 Swift、26 项 Python 测试与 Release 编译通过，检查卡片渲染无标签。One release 签名、公证、附票与 Gatekeeper 验证通过。
- 已安装启动 0.4.5，单实例快捷键监听启用，旧版保留于 build/previous-installed-0.4.4.app。未上传 GitHub Release。

## 2026-11-01 HandyPick 0.4.4 build 26

- 剪贴板网格高度按实际行数适配：每行三项，最多完整显示三行，更多内容垂直滚动。删除后同步缩小高度并约束滚动位置，空记录仍仅显示设置行。
- One check 的 34 项 Swift、26 项 Python 测试和 Release 编译通过；已有面板测试覆盖 1、3、4、6、7、9、10 条记录的高度、溢出滚动，以及删到一条时滚动位置归零；检查一行内容的实际视图渲染。
- One release 签名、公证、附票和 Gatekeeper 检查通过。已安装启动 0.4.4，单实例快捷键监听启用，旧版保留于 build/previous-installed-0.4.3.app。未上传 GitHub Release。

## 2026-11-01 HandyPick 0.4.3 build 25

- 收紧面板宽度：空记录设置行从 400pt 改为 240pt，有记录网格改为 360pt。设置按钮随宽度对齐，展开和收起时保持菜单栏图标下方居中，并约束到屏幕边界。
- One check 的 34 项 Swift、26 项 Python 测试及 Release 编译通过；更新已有面板尺寸断言并检查紧凑设置行渲染。
- One release 完成签名、公证、附票与 Gatekeeper 检查；已安装启动 0.4.3，单实例监听启用，旧版保留于 build/previous-installed-0.4.2.app。未上传 GitHub Release。

## 2026-11-01 HandyPick 0.4.2 build 24

- 按用户反馈移除无剪贴板记录时的图标、标题、说明和占位区域。空记录时面板仅保留 56pt 设置行，有记录时恢复网格；清空或删除最后一条时收起，保持面板顶部位置不变。
- One check 的 34 项 Swift、26 项 Python 测试和 Release 编译通过；原有面板测试补充空／有内容切换验证，检查空状态渲染只有设置行。
- One release 签名、公证、附票与 Gatekeeper 检查通过；已安装启动 0.4.2，单实例快捷键监听启用，旧版保留于 build/previous-installed-0.4.1.app。未上传 GitHub Release。

## 2026-11-01 HandyPick 0.4.1 build 23 — Paperlight

- 依据用户提供的 Paperlight v2 token、Card、GlassControls、Button、EmptyState 规范统一菜单栏面板、剪贴板卡片、标注工具条和复制反馈。保留品牌图标、无箭头面板、双击操作和截图定位修复。
- 引入集中管理的语义颜色和字体；内容使用不透明纸面、细描边、8pt 卡片圆角、13pt 正文，设置位于首行。卡片支持悬停描边和键盘焦点，空状态采用衬线标题，跟随系统浅色和深色主题。
- macOS 26 使用 NSGlassEffectView 承载操作工具条和复制提示；主操作黑白高对比，成功反馈使用规范青绿色。降低透明度时使用实色纸面；保留 macOS 14/15 的系统材质回退。剪贴板图片和截图标注颜色不变。
- One check：34 项 Swift、26 项 Python 测试及 arm64 Release 编译通过。渲染检查浅色／深色卡片、空状态及操作按钮；原生预览窗口确认系统玻璃上的六个按钮可见，划线／画圈切换正常，取消可退出。普通离屏位图不能完整捕获系统玻璃层，因此使用真实窗口补充检查。
- One release 完成应用与 DMG 的 Developer ID 签名、Apple 公证、附票和 Gatekeeper 验证。已更新 /Applications/HandyPick.app 为 0.4.1 build 23，旧版保留于 build/previous-installed-0.4.0.app；单实例快捷键监听启用。
- 本次 DMG：apps/handy-pick/build/releases/HandyPick-0.4.1-build23/HandyPick-0.4.1-macOS-arm64.dmg。仅本地提交，未上传新的 GitHub Release。

## 2026-11-01 HandyPick 0.4.0 build 22

- 截图保留桌面窗口阴影；全屏遮罩禁用窗口动画和工作区边界约束，所有屏幕先准备绘制再显示。用户使用实体鼠标确认进入截图已不抖动。
- 框选后原地显示划线、椭圆、文字、撤销、取消、复制工具条。回车确认复制、⌘Z 撤销；文字输入时回车结束编辑。标注按原截图像素比例合成，不包含遮罩、选框和工具条。
- 菜单栏面板第一行为快捷键设置，下方三列图片／文字网格。运行期间轮询系统剪贴板，点击卡片重新复制；右键删除单条或清空。只保存在内存，启动不导入旧剪贴板，重启清空；最多 60 项／64 MiB，忽略敏感和临时粘贴板标记。
- One check 通过 34 项 Swift 测试、26 项 Python 测试及 arm64 Release 编译。新增覆盖历史去重与淘汰、删除和清空、独立剪贴板回选与隐私标记、Retina 标注位置、文字与椭圆渲染、选区等待确认、卡片选择回调；使用非敏感测试图检查实际视图渲染。
- One release 已通过应用与 DMG 的 Developer ID 签名、Apple 公证、附票、Gatekeeper 与镜像验证。已更新 /Applications/HandyPick.app 并启动 0.4.0，单实例事件监听启用；旧版保留于 build/previous-installed-0.3.5.app。
- 用户实测确认：截图不再抖动，标注和剪贴板网格均正常。
- 本次 DMG：apps/handy-pick/build/releases/HandyPick-0.4.0-build22/HandyPick-0.4.0-macOS-arm64.dmg。没有上传新的 GitHub Release。

## 2026-11-01 handy-pick 仓库与工作区更名

- 本地根目录改为 /Users/srx/projects/handy-pick，应用目录改为 apps/handy-pick；GitHub 改为 deernova-studio/handy-pick，保留私有状态、仓库 ID 与 v0.3.5 的已发布附件。
- 更新 Git origin、One 工作区／项目名称、任务命令、签名包装器、CI 路径、文档链接和更名后的 GitHub OIDC subject。应用 Bundle ID、偏好设置域、签名身份及已安装应用保持不变。
- 新路径下 one run handy-pick:check 的 24 项 Swift、26 项 Python 测试与 arm64 Release 编译全部通过；生成任务配置无漂移。迁移前 Swift 缓存保留于忽略的 build/swift-cache-before-rename。

## 2026-11-01 HandyPick 0.3.5 build 21

- 复制反馈回到鼠标右下方，改为 96×32 点的系统磨砂胶囊、绿色细勾号、12 点文字和轻描边；适配系统明暗外观，保持 0.9 秒消失、点击穿透、不抢焦点与屏幕边缘约束。
- 已渲染检查实际视图布局，确认禁止成为 key window、忽略鼠标事件。One release 完成正式签名、公证、附票、Gatekeeper 和镜像验证；本机已升级启动 0.3.5，旧版 0.3.4 已备份，快捷键监听启用。

## 2026-11-01 HandyPick 0.3.4 build 20

- 按用户澄清恢复菜单栏白色底块到 20×16 点，仅内部镂空叠卡片居中缩小为 80%；外部画布保持 22×18 点。同步导出资源并检查预览。
- One release 完成编译、应用及 DMG 正式签名、公证、附票、Gatekeeper 和完整性验证；已安装启动 0.3.4，保留 0.3.3 备份，快捷键监听启用。

## 2026-11-01 HandyPick 0.3.3 build 19

- 菜单栏白色底块与叠卡片图形整体居中缩小为 80%，可见区域从 20×16 点改为约 16×13 点；22×18 点画布与点击区域不变。同步导出 MenuIcon 和预览，已检查渲染结果。
- Release 编译、应用及 DMG 的 Developer ID 签名、Apple 公证、附票、Gatekeeper、镜像完整性验证全部通过。已替换本机应用并启动，旧版 0.3.2 保留备份，单实例快捷键监听正常。

## 2026-11-01 HandyPick 0.3.2 build 18

- 复制反馈改为当前屏幕顶部居中的深色半透明胶囊浮层，使用独立 SF Symbols 勾号和白色文字；提升到屏幕顶层，仍不抢焦点、鼠标穿透、0.9 秒自动消失。已渲染检查实际 NSView 样式，并确认面板不能成为 key window、忽略鼠标事件。
- 应用及 DMG 的正式签名、公证、附票、Gatekeeper 和镜像完整性验证通过。Apple 票据服务经系统代理连续 TLS 失败，按此前 Apple 下载直连授权，仅向 Wi-Fi 代理例外追加 api.apple-cloudkit.com 后，沿用原公证申请完成。
- 已更新安装并启动 0.3.2，旧版 0.3.1 已备份；单实例事件监听启用，权限沿用。

## 2026-11-01 HandyPick 0.3.1 build 17

- 文字复制、截图复制与菜单中的复制最近截图共用「✓ 已复制」短暂反馈；在指针附近显示 0.9 秒，不激活、不接收鼠标点击，并限制在当前屏幕可见区域内。开始截图前主动隐藏反馈。
- 移除截图遮罩左上角的操作文字，保留选区尺寸。
- One release 的 arm64 Release 编译、应用及 DMG 的 Developer ID 签名、Apple 公证、附票及 Gatekeeper 验证通过，最终 DMG SHA-256 校验通过。
- 已更新 /Applications/HandyPick.app 为 0.3.1，保留 0.3.0 安装备份。重启后单实例事件监听已启用。反馈视觉及消失时机仍需实体鼠标使用时确认。

## 2026-11-01 HandyPick 0.3.0 build 16

- 应用显示名称改为 HandyPick，沿用 studio.deernova.quick-snap 的 Bundle ID、设置域、可执行文件名和 Developer ID 团队。原安装保留在 build/previous-installed-0.2.1.app，新版已安装到 /Applications/HandyPick.app，单实例事件监听已启用，未重新申请权限。
- 使用用户选定的第一版 image_gen 叠卡片原图（Resources/BrandMark.png），等比生成应用图标；菜单栏用对应的 22×18 白底透明镂空简化图案。已检查应用图标和菜单栏预览。
- 双击先检测前台应用指针所在文字区域的显式选区，复制为纯文本；无选区时输入区粘贴当前剪贴板，不再用最近截图覆盖；其他位置截图。不读取密码框，不对未知编辑器发送试探性 Cmd-C，不记录选区内容。
- check 通过 23 项既有 Swift 测试、26 项 Python 测试及 arm64 Release 编译；新增空选区、空白选区和密码框的 Swift 测试单独通过。One 任务配置无漂移。
- 通过真实 TextEdit 测试文档验证 InputTarget.resolve 返回 copy 且内容匹配测试选区。自动化中键未可靠进入全局监听；用户随后使用实体鼠标确认双击复制选中文字、在输入区双击粘贴均成功。
- One release 成功生成 HandyPick-0.3.0-macOS-arm64.dmg：应用及 DMG 公证 Accepted，附票、Gatekeeper、磁盘镜像完整性验证通过；最终交付文件的签名、票据及 SHA-256 再次校验通过。

## 2026-11-01 One CLI 正式签名 DMG 实测

- `one run handy-pick:check --ui stream`：23 项 Swift 测试与 25 项 Python 测试、Release 编译通过；补充搜索列表清理回归后，签名相关 12 项 Python 测试全部通过。
- 修复 macOS codesign 无法直接使用搜索列表外临时钥匙串的问题：构建时加入，结束时移除；按规范化路径匹配，并保留同时加入的其他钥匙串。不修改默认钥匙串。
- `one run handy-pick:release --ui stream` 成功生成 `apps/handy-pick/build/releases/QuickSnap-0.2.1-build15/QuickSnap-0.2.1-macOS-arm64.dmg`，大小 1,854,379 字节。
- 应用和 DMG 均采用 Developer ID Application（团队 LVWWAF3DBK）签名；Apple 公证均为 Accepted，公证票据附加及验证、Gatekeeper、磁盘镜像完整性检查全部通过。最终文件签名、公证票据和 SHA-256 校验再次通过。
- 退出后用户钥匙串列表仅保留原 login.keychain-db，临时签名目录为零。未替换已安装应用，未上传 GitHub Release。

## 2026-11-01 首次凭据写入修复

- 用户已在本机通过 P12 私钥导入、签名身份匹配和 Apple 公证凭据校验；写入失败定位为 `INFISICAL_FOLDER_NOT_FOUND`，并非密码错误。
- 已在 shared-credentials 的 prod 环境创建 /apple/macos。使用无敏感内容的临时测试项通过 One 完成写入、读取及删除，验证真实云端读写链路。
- 导入向导增加收集密码前的目录检查、仅显示白名单错误码和失败后原地重试；不记录原始 API 错误或密码。新增回归覆盖缺失目录提前失败、错误脱敏及无需重输密码的重试。
- 签名材料尚需用户重新运行导入，验证成功不等于已存入云端。

## 2026-11-01 One 共享签名接入（凭据配置中）

- 本机 One 已登录官方 Infisical，并初始化 shared-credentials。准备使用 prod 的 /apple/macos；用户尚在确认 P12 导出密码，未宣称证书私钥与公证密码已上传或通过真实验证。
- 签名任务通过 `one exec --global --keys` 获取五项凭据；新增隐藏输入导入向导、临时钥匙串包装器和签名验证任务。凭据通过 stdin 写入 One；生成物不保存 P12 或原始密码。
- 9 项新测试覆盖导入失败、公证授权失败、身份不匹配、缺失配置、退出码、终止清理、stdin 上传及日志不含原始密码；原有 14 项 Python 测试和 23 项 Swift 测试继续通过。
- 实际创建并删除空临时钥匙串验证：默认用户钥匙串搜索列表不变。导入向导在真实 PTY 中到达确认提示并取消，没有输入或上传凭据。
- Apple 官方公开 Developer ID G2 中间证书 SHA-256 与用户提供的公开副本一致，随脚本导入临时钥匙串；没有修改系统信任设置。
- CI 已编写同源 Infisical OIDC 取用配置，但当前账户自定义 RBAC 受套餐限制。未授予 CI 整个共享库的读取权限，未创建机器身份或填写 GitHub Variables；云端链路未验证。

## 2026-11-01 One CLI 接入

- 应用整体迁移到 `apps/handy-pick`，保留 SwiftPM；原有 Sources、Tests、Resources 文件逐字节一致，Bundle ID 仍为 `studio.deernova.quick-snap`。
- 新增 One manifest、项目 Taskfile，通过 `one init mise` 生成工作区任务；再次 dry-run 无配置漂移。
- One 固定为上游已合并提交 `bc73b921d85e1896044167c0be96a2b8936edf54`，源码归档 SHA-256 校验后本地编译。v0.1.24 正式包未包含 Swift 模板。
- `one run handy-pick:check --ui stream` 通过：14 项 Python 发布脚本测试、23 项 Swift 核心测试、arm64 Release 编译。
- `one run handy-pick:build --ui stream` 与 `one run handy-pick:pack --ui stream` 通过；应用严格签名校验、菜单栏属性、Bundle ID、arm64 架构与本地 DMG 完整性验证通过。
- 发布工作流更新应用路径，并复用 One 的 check/sign/notarize 任务；actionlint v1.7.7 校验通过。脚本语法与 git diff 空白检查通过。
- 本次未替换 `/Applications/Quick Snap.app`，未启动新 GUI 实例或重新申请权限。正式 Developer ID 签名、Apple 公证及云端发布仍待凭据就绪后验证。
- 下方历史记录中的根目录 `Scripts`、`Sources`、`Resources` 等路径均指迁移前的位置。

## 2026-11-01 发布流程

- 参照同一组织 linse 的手动发布流程，增加 Developer ID 打包、临时 CI 钥匙串、应用及 DMG 公证/附票、Gatekeeper 检查、SHA-256 和草稿 Release 验证后发布。保留本机开发构建，不新增 push / PR 自动任务。
- `Scripts/check-ci.sh` 通过：14 项发布脚本测试、23 项 Swift 核心测试、arm64 Release 编译；工作流经 actionlint 校验通过。开发打包通过，bundle ID、菜单栏属性与 arm64 架构保持正确，严格签名校验通过。
- 这里只验证了临时签名的开发包。当前 Mac 无 Developer ID Application 私钥，新仓库的三个签名 Secrets 尚未配置，因此尚未生成正式签名/公证的 DMG，也未运行正式发布。
- 已将 linse 的 APPLE_ID / APPLE_TEAM_ID 两项 Variables 配置到 Quick Snap；没有读取或导出 GitHub Secrets，签名私钥没有进入 Git 历史。

2026-10-31，macOS 26.2 / Apple Silicon，Xcode 26.6，Swift 6.3.3。

## 已通过

- `swift test`：19 项 XCTest，0 失败。覆盖单击无动作、双击准确位置、三连击不重复、四次点击两组手势、不同前台应用、点击距离、暂停/拖动取消、慢速/乱序点击；覆盖可编辑控件、只读/禁用/密码控件分类，以及反向框选、边界裁切、Retina / 非 Retina 坐标与最小选区。新增鼠标 / 键盘 / 修饰键绑定序列化、无效键位拒绝、组合键匹配、长按不重复触发、按键释放配对和暂停清理的回归测试。
- `zsh Scripts/build.sh`：Release 编译、`.app` 打包和本机 ad-hoc 签名通过。
- 应用实际启动，设置窗口和菜单栏入口显示正常。
- 屏幕录制和辅助功能权限在系统设置中均已开启；应用的全局事件监听启动成功。
- 示例画布实际框选得到 460 × 130 图片，复制后通过 ⌘V 粘贴至文本编辑，文字方向与选区内容正确。
- 新版使用已有 Apple Development 身份签名，严格签名验证通过；移除旧权限条目后重新添加新版，应用确认授权有效，全局监听成功开启。
- 真实屏幕捕获：从文本编辑中的三行测试文字框选 240 × 46 区域，随后通过 ⌘V 粘贴回文档，三行内容和上下方向正确。
- 新版诊断已收到一次辅助鼠标按下事件，编号为 3（中键）。
- 用户已确认上一版实体鼠标截图和粘贴可以使用。
- 当前统一双击版本：Release 构建、沿用同一 Apple Development 身份签名及严格验证通过；已启动并开启监听，已有权限继续有效，设置窗口显示新规则。
- 菜单栏版本已更新到 `/Applications/Quick Snap.app`：Release 构建及严格签名验证通过。实际启动后没有前台窗口，安装目录中的进程持续运行；系统诊断确认该进程仅有一个鼠标事件 tap，且 enabled 为 true。菜单栏入口显示取景框与 QS，设置从菜单按需打开；设置提供中键 / 侧键下拉选择，按键和暂停状态写入 UserDefaults。
- 0.2.0 已改为菜单栏 NSPopover 录入面板，移除独立设置窗口和预设下拉框。新增鼠标侧键、键盘键、组合键和修饰键录入。Release 构建、应用打包、Info.plist 校验和严格签名验证通过，已更新本机安装副本。
- 最终图标根据用户反馈换为写意的「剪刀 + 图片」。应用图标及透明菜单栏资源已经生成并集成；透明源图按 8 像素步长抽样，透明样本 20,634 个、alpha 大于 0.5 的样本 3,787 个；菜单栏 PNG 为 38 × 38，包含有效透明通道。图标尺寸资源和 icns 已生成，已在访达 Quick Look 中实际看到新版剪刀与图片图标，并关闭预览恢复后台运行。
- 0.2.0 实际后台进程创建的键鼠事件 tap 显示 enabled 为 true，事件掩码包含鼠标辅助按键、keyDown / keyUp / flagsChanged。
- 用户已确认快捷键小面板能够打开。切回聊天时 transient 面板会收起；界面工具尚未取得其可读的原生窗口，未声称完成面板视觉验收或真实键盘录入验收。
- 0.2.1 图标修订：按用户要求加粗约 35%，菜单栏改用白底黑图标（non-template NSImage）。MenuIcon 为 38 × 38，不透明白色边角的 RGBA 约为 (0.997, 0.997, 0.997, 1)，安装副本的资源与构建产物一致。Release 构建和严格签名验证通过，已更新并重新启动安装版；访达 Quick Look 显示版本 0.2.1。图标变更没有修改双击与键位录入逻辑。
- 随后根据用户参考图纠正菜单栏样式：不再缩小应用图标，改由 `MenuBarIcon.swift` 独立绘制 22 × 16 点的圆角白色小底、粗黑剪刀和开放图片边框。运行时直接使用此矢量 NSImage；同源导出的 PNG 为 44 × 32，角落 alpha 为 0、内部 alpha 为 1。已查看蓝色菜单栏上的同源样式预览，确认图形和圆角白底正常显示。Release 构建与签名验证通过，安装副本已替换并重新启动。
- 最终按用户再次澄清纠正为原生菜单栏样式：完全去掉白色底板和图片轮廓，使用 SF Symbols 的单色 scissors 模板（18 × 18 点），由 AppKit 自动绘制前景色。已查看蓝色菜单栏预览，显示透明底白色剪刀。Release 构建与严格签名验证通过，已安装并重启；双击逻辑未修改。
- 用户进一步明确最终要求为品牌图标的简笔镂空版。已恢复自有倾斜图片与剪刀轮廓，使用白色圆角小底，将图标路径从 alpha 中擦除。MenuIcon.png 验证：白色像素 915，透明像素 403，涂黑像素 0；图案实际透明而非涂成背景颜色。查看同源蓝色菜单栏预览，确认背景从剪刀和图片线条中透出。提供 1× / 2× / 4× 图像表示；Release 构建、签名验证通过，已更新安装并重新启动。
- 紧凑比例修订：画布由 22 × 16 收为 18 × 18 点，白底由横向胶囊改为 16 × 16 的圆角方形，照片收为近方形，剪刀沿左下至右上方向叠放。镂空绘制方式保持一致，导出的 2× PNG 为 36 × 36。已查看同源预览，构建与严格签名验证通过，并更新重启安装版。
- 按用户后续指定，菜单栏画布改为宽 18、高 22 点，白底为 16 × 20 点；图案保持比例，仅垂直居中平移 2 点。导出的 2× PNG 确认为 36 × 44，已查看预览；构建和严格签名验证通过，安装副本已替换并重新启动。
- 用户纠正尺寸为宽 22、高 18 点后，画布调整为 22 × 18，白底为 20 × 16，图案保持比例并水平居中。2× PNG 为 44 × 36，预览已检查；构建和严格签名验证通过，安装版已更新重启。
- 快捷键编辑面板精简为 210 × 52 点的一行「双击 + 当前键位」；删除标题、操作说明、状态文字及暂停/退出按钮。录入中仅把键位按钮改为「按键…」，缺权限时同一按钮用于授权。暂停、启用、退出保留在右键菜单；原有录入逻辑不变。Release 构建、严格签名验证通过，已安装重启。离屏渲染未完整呈现原生按钮文字，不据此声称完成实际弹出面板的视觉验收。

- Build 12：将带箭头 NSPopover 替换为无边框、无箭头的圆角 NSPanel。面板不激活应用，保留原前台应用作为快捷键目标；移除面板显示时忽略双击的限制，双击先收起面板再按原规则截图或粘贴。19 项 XCTest、Release 构建、Info.plist 校验及严格签名验证通过；安装版已启动，事件 tap 为 enabled=true。用户实测确认「没有箭头，双击也能截图了」。本次未单独验收面板内键位录入、展开面板时粘贴及多屏定位。

- 用户进一步确认：Codex 中双击后重新进入截图；随后澄清尚未测试手动 ⌘V，不能记为手动粘贴已通过。Build 15 增加 Chromium 明确公布的 AXEditableAncestor 识别，并要求鼠标位于当前焦点输入框实际边界内才允许空间回退；顶层命中、焦点及前台应用必须同进程。新增无 AXValue setter 的网页编辑器、只读/密码/禁用拒绝、鼠标在焦点框外及其他应用覆盖时拒绝回退的测试；23 项 XCTest 全通过，Release 构建和严格签名验证通过，已安装启动。用户按「重新截图、左键点入 Codex 输入框、鼠标留在框内、双击中键」实测确认「图片贴进去了」；应用自身固定状态码为 paste-shortcut-posted。本次未单独验证不先点入输入框的自动聚焦。增加仅保存固定处理阶段、不含应用标识或控件内容的本机 lastGestureOutcome，便于系统日志为空时定位。

## 待完成

- Build 14：用户补充测试目标为 Codex。补齐 Electron 官方 AXManualAccessibility 初始化：仅对 bundle 中包含 Electron Framework 的当前前台应用设置该属性，异步等待最多四次命中查询；检查前台切换，避免异步结果路由至其他应用。Release 构建和严格签名验证通过，已替换并启动安装版。桌面工具禁止操作 Codex 界面，未改用其他工具读取或操纵其 UI；需由用户在 Codex 中实际截取新图并双击验证。尚无此次故障的运行日志，不能确认上述遗漏就是本次反馈的原因。

- Build 13：针对「双击输入框未粘贴」反馈，补充以可写 AXSelectedText 识别网页编辑器；通用 AXGroup 容器必须同时明确可编辑且支持内容写入。聚焦确认由固定等待 0.1 秒改为最多 10 次、每次间隔 60 毫秒；支持直接读取目标 AXFocused，并避免重复激活已在前台的应用。新增两个回归测试，21 项 XCTest 全通过；Release 构建及严格签名验证通过，已安装重启。仅增加不含控件内容的系统诊断日志，真实输入框双击粘贴仍待用户复测，尚未确认此次反馈的确切失败阶段。

- 当前统一双击版本的真实手势路由：输入框外双击截图，输入框内双击粘贴。已请求用户复测。单击计时器已经删除，单击不再触发截图。
- 输入区域的位置命中及自动聚焦在原生和网页编辑器中的兼容性。无法确认可编辑的区域按截图处理；无法确认聚焦成功时不粘贴。
- 新版快捷键录入小面板的视觉布局、实际录入和暂停后重启恢复状态的人工验收。用户确认面板能打开，实际键位录入尚未完成验收；原生界面工具未取得可操作窗口。
- PNG / TIFF 两种格式在不同目标应用的兼容性。
- 实际鼠标侧键、多屏幕、权限撤销后行为。

早期示例画布是本地程序绘制的测试内容，不能作为真实屏幕截图已通过的证据；当前精简版本已移除示例入口。应用没有启用网络或自动保存截图。
