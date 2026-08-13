# 随机根隐根（Random Root Hidden）需求文档

## 背景

Dopamine 3.0.5（A13 / iOS 18.5 无根越狱）当前实现为"黑名单隐藏 /var/jb"模式：通过 spawn 级黑名单（zp.hide.plist + DOPAMINE_HIDDEN_ROOT 环境变量）让被勾选进程隐藏 /var/jb 文件系统视图。

用户要求转向 RootHide 式**随机根模式**：越狱根目录使用随机化名称 `.jbroot-%016llX`（X 为 1 字节校验和），使检测方无法通过固定路径发现越狱环境。参考仓库为 [P013onEr/RootHide](https://github.com/P013onEr/RootHide)（Dopamine 3.0.4 + RootHide 移植，仅验证 iOS 16.6），本工程需适配 iOS 18.5。

## 需求（EARS 模式）

- WHILE 系统处于随机根越狱状态，Dopamine 越狱根目录 SHALL 使用随机化的 `.jbroot-%016llX` 目录名，X 为满足校验和约束的 8 位十六进制值。
- WHILE 系统处于随机根越狱状态，所有越狱进程 SHALL 通过 `@loader_path/.jbroot` 符号链接定位越狱根，无需硬编码路径。
- WHILE 一个进程被列入隐藏黑名单（RootHideConfig.plist 的 appconfig），该进程 SHALL 无法通过文件系统 API（access/stat/lstat/open/opendir/readdir/getattrlist 等）看到越狱根、越狱 dylib（systemhook-*.dylib）及越狱检测标记文件。
- WHILE 一个进程被列入隐藏黑名单，该进程 SHALL 在 OC 层无法通过 LSApplicationWorkspace 看到越狱 App，且 canOpenURL 对 sileo://、dopamine:// 等越狱 URL scheme 返回 NO。
- WHILE 系统处于随机根越狱状态，越狱环境变量（DYLD_INSERT_LIBRARIES、DYLD_IN_CACHE 等）SHALL 对黑名单进程不可见。
- WHILE 系统处于随机根越狱状态，security.mac.amfi.developer_mode_status sysctl SHALL 返回 1（伪造），以隐藏越狱痕迹。
- WHEN 用户重新随机化越狱根，系统 SHALL 移动现有 `.jbroot-%016llX` 到新随机名并更新符号链接。

## 非功能需求

- 完整可编译的整套工程（BaseBin 各模块 + Theos roothidehooks + Application 随机根逻辑 + 构建配置），无编译依赖缺失。
- 构建产物适配 Dopamine 无根越狱自动注入（dylib 进 basebin，经 launchdhook 注入，开机自动加载），不依赖 TrollStore。
- 保留 A13 iPhone11 / iOS 18.5 支持（参考仓库仅验证 iOS 16.6）。
- OC 层 Hook 使用 ElleKit（工作区已集成 libellekit.a）替代 CydiaSubstrate。
