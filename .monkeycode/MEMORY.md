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
- Context: Discovered by Agent while performing iOS 18.5 kernelcache 反汇编验证 XPF namecache 解析
- Category: Troubleshooting & Debugging
- Instructions:
  - iOS 18.5 kernelcache 获取：用户设备上传解密版到 /workspace/uploads/kernelcache（19,424,905B，IMG4 DER+LZFSE bvx2@57），用 pip lzfse 从 offset 57 解压得 /tmp/opencode/kernel_macho.bin（60,424,192B，arm64e MH_FILESET）。TEXT_VM=18446744005123129344，TEXT_OFF=15597568，__TEXT_EXEC size 38,649,856。
  - crcFlag 模式（MOVZ W9,#0x1db7 + MOVK W9,#0x4c1,LSL#16）在 iOS 18.5 内核**唯一匹配** nchinit（0x1c1f70/0x1c1f74）；XPF patch 的 namecache 解析流程（crcFlag→BL hashinit 0x1c2048→adrp+str 对）完整模拟通过：nchashtbl=0xfffffff009746948，nchashmask=0xfffffff009746950，相邻校验（diff=8）通过。即 **XPF-roothide.patch 的 namecache 解析在 iOS 18.5 上正确，不会因此重启**。
  - iOS 18.5 struct namecache（xnu-11215.81.4 bsd/sys/namei.h 224-237）与 unsandbox2.m 的 namecache_v2 逐字段一致（smrq_link，iOS 16.4+）。AMFI oid 字符串（launch environment logging / developer mode status）在 kernelcache 中存在。
  - XPF set 解析失败只报错不重启：DOJailbreaker.m 150-158 行 `if (!_systemInfoXdict) return [NSError ... JBErrorCodeFailedKernelPatchfinding ...]`。用户报的 "Failed to find set namecache" 是未打 patch 的构建。
  - b258199 ipa（Release 3.0.5，Dopamine_hiddenroot_3.0.5.ipa 与 Dopamine_blacklist_3.0.5_802_1786642937_b258199.ipa，均 55,657,448B）libxpf.dylib 含 xpf_find_namecache/namecache set——确认含 patch。
  - 判断 XPF 是否真正生效：`strings libxpf.dylib | grep namecache` 查 xpf_find_namecache 存在。
  - 手工 STR imm12 解码易错（f904a928 imm12=0x12A→#0x950，非 0xA48）；应直接用脚本模拟 patch 的 pfsec 匹配逻辑，勿手算。

[Project Knowledge Summary]
- Date: 2026-08-13
- Context: Discovered by Agent while performing DOBootstrapper/DOEnvironmentManager 移植决策
- Category: Troubleshooting & Debugging
- Instructions:
  - DOBootstrapper.m 整体替换为参考仓库 1423 行版（主类 prepareBootstrapWithCompletion/finalizeBootstrap/deleteBootstrap 与 DOBootstrapper(roothide) category 内重复定义，category 覆盖主类是参考仓库原样，能编译）。
  - DOEnvironmentManager 用 `#if 0` 注释主类 locateJailbreakRoot/ensureJailbreakRootExists（100-214 行）+ 末尾 DOEnvironmentManager(roothide) category 覆盖；isJailbroken 改为动态 `jbclient_roothide_jailbroken()` 检查。
  - 工作区 3.0.5 的 `setJailbroken:withVersion:`（含 /var/jb 符号链接管理）与 `fake_mount()`（newFakePath.plist 挂载）是 3.0.5 特有，随机根模式保留 /var/jb 兼容逻辑（与参考仓库一致）。
  - DOJailbreaker.m 保留 3.0.5 版，增量移植 roothide 关键逻辑：xpf sets 加 namecache/amfi_oids、platformize 加 CS_INSTALLER+otherJailbreakActived、randomizeAndLoadBasebinTrustcache、roothide Stage（basebin_generate+ensure_dyld_trustcache+exec_set_patch(true)+DYLD_INSERT_LIBRARIES=JBROOT_PATH 路径）、PATH 用 /rootfs 前缀（pathhook.x 重定向 /rootfs→jbroot）。

[Project Knowledge Summary]
- Date: 2026-08-14
- Context: Discovered by Agent while analyzing 2 user-uploaded panic-full-*.ips logs (iPhone12,1/A13, iOS 18.5 22F76, xnu-11417.122.4) at /workspace/panic-full-2026-08-14-021212.0002.ips and -025143.0002.ips
- Category: Troubleshooting & Debugging
- Instructions:
  - 两个 panic 的 panicString 都是 `initproc exited`（内核因 pid 1 launchd 退出而 panic），roots_installed: 0；内核崩溃**不是直接原因**，launchd 用户态被信号杀死才是根因。第一个：exit reason namespace 2 subcode 0xa = SIGBUS(signal 10)，boot 后 55s；第二个：namespace 23 subcode 0x2000000600000000 = signal 6(SIGABRT)，boot 后 2348s（手动打开 Dopamine 越狱场景）。
  - 两个 panic 中崩溃线程（launchd）的 userFrames 都执行在同一个注入 dylib（UUID 86d5253d-4fd1-36f3-b4ab-25982c90cbf4，第二个 panic 中镜像21 base 0x104630000，第一个中镜像20 base 0x10303c000）→ 这是 launchdhook.dylib 注入 launchd 后的实例。launchd 在 launchdhook constructor initializer() 执行期间被杀死。
  - 进程列表均含 Dopamine(pid 838/332)、opainject×2(847/848/354/355)、SpringBoard(pid 34)——系统已完全启动，崩溃在"用户打开 Dopamine 点越狱→opainject 注入 launchdhook 到运行中 launchd"路径（firstLoad=true → roothide_launchd_postinit 调用 hideDeveloperMode()）。
  - 崩溃**不是** launchd_panic 路径（launchd_panic 会 reboot_np(RB_PANIC) 使 panicString 含 reason，实测不含），是 launchd 真正用户态 SIGBUS/SIGABRT。
  - launchdhook crashreporter.m 整体被 #if 0 禁用（crashreporter_start 实际链接 libjailbreak/src/roothider/crashreporter.m:583 版本，无链接问题）。
  - 排查顺序建议：launchdhook initializer() 的执行顺序为 crashreporter_start → roothide_launchd_preinit → boomerang_recoverPrimitives(firstLoad,true)（失败 abort_with_reason(7,1)）→ cs_allow_invalid → initXPCHooks/initDaemonHooks/initSpawnHooks/initIPCHooks/initJetsamHook → roothide_launchd_postinit(firstLoad)（firstLoad 时 exec_set_patch(true)+hideDeveloperMode()）。SIGBUS/SIGABRT 最可疑在 hideDeveloperMode() 的 kreadbuf/kwrite 与 boomerang_recoverPrimitives，需在 iOS 18.5 验证。
  - panic ips 内 kernelFrames/用户栈帧被 stackshot 重采样/截断（notes 标注 truncated backtraces），不可直接当真实调用栈；binaryImages 的 UUID 与 base 是可靠的。

[Project Knowledge Summary]
- Date: 2026-08-14
- Context: Discovered by Agent while pinpointing launchdhook constructor crash root cause on iOS 18.5 (panic log binaryImages/符号表交叉分析)
- Category: Troubleshooting & Debugging
- Instructions:
  - 崩溃线程 tid=35549 状态 TH_RUN/kThreadOnCore，内核栈顶帧 fileoff=0xf2d9a4（与第一个 panic 崩溃点相同），其下 0x13b2c24/0x13b20b0 = proc_exit/initproc 检查（panic 调用点）。确认 launchd 通过 exit() 系统调用退出 → 内核 initproc exited panic。
  - launchdhook 崩溃栈锚点：img20+0x4b40 = `_initializer` 内 `bl roothide_launchd_preinit`(0x5294) 调用点。initializer 执行顺序：crashreporter_start(0x4b3c, GOT导入) → preinit(0x4b40) → boomerang_recoverPrimitives(0x4d5c) → initXPCHooks/initDaemonHooks/initSpawnHooks/initIPCHooks/initJetsamHook(0x4e28-0x4e38) → roothide_launchd_postinit(0x4fa8)。
  - P013onEr 参考仓库 main.m 把 `abort_with_reason(...)` 宏替换为 `launchd_panic("%s",reason)`（reboot_np(RB_PANIC)）；工作区 main.m 保留 3.0.5 版（hookd_provider/litehook/bootlogo drawctx 等）未做该替换。
  - crashreporter(libjailbreak 版) ABORT 宏 = reboot_np(RB_PANIC|RB_QUICK,msg) 失败后 `_exit(0)`；launchd_panic 同样 reboot_np 失败后 `_exit(0)`。两个 panic panicString 均无 ABORT/launchd_panic message → reboot_np 在 iOS 18.5 launchd 中失败，launchd 走 _exit(0) → initproc exited。这解释了"无 message 的 initproc exited panic"。
  - 崩溃 dylib 身份（UUID 交叉验证）：img19=7eba0ae1=libjailbreak.dylib、img20=0de6c0dc=launchdhook.dylib，两者均与工作区 ipa_x/basebin/basebin 的 arm64e slice 字节级一致 → 崩溃的实为 workspace 构建（非 P013OnEr 3.0.4）。img21=86d5253d 身份未定（不影响主根因）。
  - 崩溃调用链（crashreporter 精确符号化，3 份 launchd-*.ips 一致）：launchdhook initializer() → main.m:173 `litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, sysctlbyname, ...)` → `_litehook_rebind_symbol_in_section`(libjailbreak 0x3dd24) 写回 slot 时 SIGBUS。ESR=0x9200004F（bit6 WnR=1=写, DFSC=0xF=synchronous external abort）→ iOS 18.5 上 launchd 的 `__auth_got` 受 PPL/硬件写保护，`mach_vm_protect`(litehook.c:433 前一步 unprotect) 实际失败但 litehook 忽略返回值继续写 → SIGBUS → launchd 退出 → initproc exited panic。
  - 修复（commit 355f226，对齐 P013OnEr 3.0.4）：main.m:172-173 的 sysctlbyname、ipc_hook.c:37 sandbox_check_by_audit_token、jetsam_hook.c:26 memorystatus_control、daemon_hook.m:75 xpc_dictionary_get_value 共 4 处 `litehook_rebind_symbol(GLOBAL)` 改为 `MSHookFunction`（函数入口 patch，不写 launchd __auth_got）；xpc_hook.c:67 xpc_receive_mach_msg 保留 rebind（P013OnEr 同）。launchdhook 已链接 ellekit 且各文件已 include substrate.h，可直接用 MSHookFunction。
  - 官方 Dopamine 3.0.5（2026-08-13 发布）与 workspace 同样用 litehook_rebind_symbol；官方 basebin.tar 内 launchdhook arm64e UUID=4d5aeb65（与崩溃版 0de6c0dc 不同）。用户明确不需要对比官方（官方非隐根）。
  - 本地 Linux devbox 无法编译 iOS，构建验证走 CI：git push a13dp hiddenroot-release 后 curl POST `/repos/3834434756-svg/a13dp/actions/workflows/build.yml/dispatches`（ref=hiddenroot-release，token 从 git credential fill 取），产物为 Dopamine_blacklist_*.ipa 发布到 Release。

[Project Knowledge Summary]
- Date: 2026-08-14
- Context: Discovered by Agent while analyzing 2nd round of user panic logs (panic-full-2026-08-14-142619/-142928, iOS 18.5) after the litehook-rebind fix
- Category: Troubleshooting & Debugging
- Instructions:
  - 355f226 修复（litehook rebind → MSHookFunction）后用户实测仍自动重启。新 panic 与旧崩溃栈已不同：崩溃线程不再在 litehook_rebind 写 __auth_got，而是 launchdhook initializer(+0x4b34) → libjailbreak _crashreporter_start(+0x2f828) → _crashreporter_resume(+0x2eb58) → bl stub[_ptrace](+0x2eb54, 实为 task_set_exception_ports) → 崩溃。panicString 仍是 initproc exited namespace 23(SIGABRT)。
  - 根因：workspace 移植的 libjailbreak/src/roothider/crashreporter.m 在 iOS 17+ 上仍执行 task_set_exception_ports 注册 mach exception ports，iOS 18.5 launchd 不允许第三方抢占 exception ports → launchd abort。官方 Dopamine 的 launchdhook crashreporter.m 有 `@available(iOS 17.0, *)` guard 完全跳过（官方 libjailbreak 无 crashreporter）；RootHide 移植版缺失该 guard。
  - 修复（commit 59ce04f）：给 libjailbreak/src/roothider/crashreporter.m 的 crashreporter_start/pause/resume 三个函数包上 `if (@available(iOS 17.0, *)) {} else { ... }`，对齐官方 Dopamine 的 iOS 17+ 禁用行为。已反汇编新 ipa 验证：三个函数在版本检查非 0 时直接跳函数尾返回，不再执行 task_set_exception_ports。
  - crashreporter_pause 在 iOS 17+ 分支返回 key=0；spawn_hook.c:62 调用 pause()/resume(key)，resume(0) 时 key==gCrashReporterStateKey(0) 但 state 为 NotActive 非 Paused，不执行 task_set_exception_ports，安全。
  - 新 Release 资产命名：Dopamine_blacklist_3.0.5__1786690325_59ce04f.ipa（两次下划线，timestamp_commit）。
  - 经验：panic ips 的 binaryImages 用 [uuid, base, tag]，img 索引按加载顺序；launchdhook/libjailbreak 的 UUID 前缀可快速比对工作区产物（launchdhook=43636a6b 修复版/0de6c0dc 旧版，libjailbreak=7eba0ae1）。la_symbol_ptr/__auth_got 项符号用 indirect symtab 索引映射，stub 目标符号名可能与实际 MIG 函数不同（_ptrace 实际是 task_set_exception_ports），判参数布局（5 参 w0-w4、behavior=0x80000001、flavor=6）更可靠。
