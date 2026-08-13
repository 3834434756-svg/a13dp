# User Instruction Memory

This file records user instructions, preferences, and teachings for reference in future interactions.

## Format

### User Instruction Entry
User instruction entries should follow this format:

[User Instruction Summary]
- Date: [YYYY-MM-DD]
- Context: [Mentioned scenario or time]
- Instructions:
  - [Content of user teaching or instruction, described line by line]

### Project Knowledge Entry
Entries discovered by the Agent during task execution should follow this format:

[Project Knowledge Summary]
- Date: [YYYY-MM-DD]
- Context: Discovered by Agent while performing [specific task description]
- Category: [Operations & Deployment|Build Methods|Testing Methods|Troubleshooting & Debugging|Workflow & Collaboration|Environment Configuration]
- Instructions:
  - [Specific knowledge points, described line by line]

## Deduplication Strategy
- Before adding a new entry, check for similar or identical instructions.
- If a duplicate is found, skip the new entry or merge it with the existing one.
- When merging, update the context or date information.
- This helps avoid redundant entries and keeps the memory file tidy.

## Entries

[User Instruction Summary]
- Date: 2026-08-13
- Context: 将工作区 Dopamine 3.0.5 工程重构为适配 A13 iPhone11 / iOS 18.5 / Dopamine3 无根越狱的完整隐根工具
- Instructions:
  - 禁止只做 UI 面板，必须完整复刻 RootHide 全套底层劫持（界面只是配套开关）。
  - 随机根模式：主目录 `/var/containers/Bundle/Application/.jbroot-%016llX`，二次可写目录 `/var/mobile/Containers/Shared/AppGroup/.jbroot-%016llX`，`@loader_path/.jbroot` 符号链接动态指向随机根。
  - OC 层 Hook 用 ElleKit（工作区已集成 `_external/lib/libellekit.tbd`，导出 `_MSHookFunction` 等，flat_namespace）。
  - 增量移植到 3.0.5 基座（保留工作区 Dopamine 3.0.5 实现与 3.0.5 特有修复，非整体替换参考仓库 3.0.4 版）。
  - 黑名单机制切换为 RootHideConfig.plist（`jbclient_blacklist_check_pid/path/bundle` XPC 查询），黑名单进程在 spawn 时不注入 systemhook。
  - 用户设备无 TrollStore；产物必须走 Dopamine 无根自动注入链（launchdhook posix_spawn 注入）。

[Project Knowledge Summary]
- Date: 2026-08-13
- Context: Discovered by Agent while performing Dopamine 3.0.5 → RootHide 随机根隐根重构
- Category: Build Methods
- Instructions:
  - 参考仓库 `/tmp/opencode/RootHide`（P013onEr/RootHide，Dopamine 3.0.4 base，仅验证 iPhone14PM/iOS16.6）。其 `BaseBin/bootstrapper` 是空壳无需移植。
  - jbrand：`jbrand_new() = ((uint64_t)arc4random()) | ((uint64_t)arc4random())<<32`，低字节为高 7 字节 XOR 校验和；`JB_ROOT_PREFIX=".jbroot-"`（16 位十六进制，总长 24 字符）。
  - roothider.h 是薄兼容层：`#define jbroot(path) JBROOT_PATH(path)`，`#define rootfs(path) JBROOT_PATH(path)`，include libjailbreak/jbroot.h。参考仓库将其放 `BaseBin/_external/include/roothide.h`（复制到 .include 顶层，roothidehooks 用 `<roothide.h>`）。
  - 工作区 util.h 是 3.0.5 版（含 spawn.h/persona 宏/spawn_config_* 实现），参考仓库 util.h 是 3.0.4 窄版（`#include "roothider.h"`），不要整体替换；缺 roothide 符号声明用文件级 extern 补。
  - libjailbreak 无导出符号过滤，所有非 static 符号（otherJailbreakActived/randomizeAndLoadBasebinTrustcache 等）App 链接可解析。
  - JBS_DOMAIN_ROOTHIDE 在参考仓库为 5（无 Dopamine domain），工作区保留 JBS_DOMAIN_DOPAMINE 5 且 ROOTHIDE 设为 6（launchdhook gGlobalServer 数组 gDopamineDomain 后追加 gRootHideDomain）。
  - 编译拓扑：各 .dylib 相互独立编译但都链 libjailbreak.dylib；clang 对 ObjC 隐式函数声明是 warning 不是 error。roothidehooks/jailbreakd 用 -Werror，依赖符号必须经头文件声明。
  - App 用 Xcode 工程（Dopamine.xcodeproj）+ xcodebuild，链接 .build/libjailbreak.dylib。CI 在 `.github/workflows/build.yml`（macos-latest，`gmake NIGHTLY=1`），本地 Linux devbox 无法编译 iOS。

[Project Knowledge Summary]
- Date: 2026-08-13
- Context: Discovered by Agent while performing DOBootstrapper/DOEnvironmentManager 移植决策
- Category: Troubleshooting & Debugging
- Instructions:
  - DOBootstrapper.m 整体替换为参考仓库 1423 行版（主类 prepareBootstrapWithCompletion/finalizeBootstrap/deleteBootstrap 与 DOBootstrapper(roothide) category 内重复定义，category 覆盖主类是参考仓库原样，能编译）。
  - DOEnvironmentManager 用 `#if 0` 注释主类 locateJailbreakRoot/ensureJailbreakRootExists（100-214 行）+ 末尾 DOEnvironmentManager(roothide) category 覆盖；isJailbroken 改为动态 `jbclient_roothide_jailbroken()` 检查。
  - 工作区 3.0.5 的 `setJailbroken:withVersion:`（含 /var/jb 符号链接管理）与 `fake_mount()`（newFakePath.plist 挂载）是 3.0.5 特有，随机根模式保留 /var/jb 兼容逻辑（与参考仓库一致）。
  - DOJailbreaker.m 保留 3.0.5 版，增量移植 roothide 关键逻辑：xpf sets 加 namecache/amfi_oids、platformize 加 CS_INSTALLER+otherJailbreakActived、randomizeAndLoadBasebinTrustcache、roothide Stage（basebin_generate+ensure_dyld_trustcache+exec_set_patch(true)+DYLD_INSERT_LIBRARIES=JBROOT_PATH 路径）、PATH 用 /rootfs 前缀（pathhook.x 重定向 /rootfs→jbroot）。
