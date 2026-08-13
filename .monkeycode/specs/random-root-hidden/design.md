# 随机根隐根技术设计文档

## 架构总览

参考仓库 P013onEr/RootHide（Dopamine 3.0.4 + RootHide）随机根机制由以下模块构成。本工程在 Dopamine 3.0.5 基座上增量移植，黑名单机制切换为 RootHideConfig.plist。

```
┌─────────────────────────────────────────────────────────────┐
│ Application (Dopamine.app / BlackApple.app)                  │
│  DOBootstrapper.m: jbrand_new/current/find_jbroot/ReRandomize │
│  创建 .jbroot-%016llX、二次目录、.jbroot 符号链接               │
│  管理 RootHideConfig.plist（appconfig 黑名单）                 │
├─────────────────────────────────────────────────────────────┤
│ launchd (launchdhook.dylib)                                  │
│  roothider.m: spawn 预处理（黑名单判定/扩展拦截/注入准备）        │
│  jbserver/jbdomain_roothide.c: XPC 域（blacklist/trust/jbd）  │
│  注入 DYLD_INSERT_LIBRARIES = /usr/lib/systemhook-%016llX.dylib│
├─────────────────────────────────────────────────────────────┤
│ dyld (dyldhook.dylib)                                        │
│  roothider.c/S: hook Loader::expandAtLoaderPath 重定向        │
│   @loader_path/.jbroot → 实际随机根路径                        │
├─────────────────────────────────────────────────────────────┤
│ 进程内 (systemhook-%016llX.dylib)                            │
│  roothider_main.c: 隐藏 sysctl/路径/env/进程遍历 + spawn 处理  │
│  roothider_common.c: __sysctl/__sysctlbyname AMFI 伪造        │
│  旧黑名单(access/stat/open/opendir)→扩展 readdir/getattrlist  │
├─────────────────────────────────────────────────────────────┤
│ lsd/SpringBoard/cfprefsd (roothidehooks.dylib via ElleKit)   │
│  lsd.x: LSApplicationWorkspace/canOpenURL/openURL 过滤        │
│  springboard.x: 快照/保护类 fcntl 处理                         │
│  cfprefsd.x: 越狱偏好伪装                                     │
├─────────────────────────────────────────────────────────────┤
│ jailbreakd (独立 daemon, libjailbreak roothider/jailbreakd)  │
│  unsandbox / dyld_patch / exec_patch / recdhash / mach_exc   │
└─────────────────────────────────────────────────────────────┘
```

## 关键机制

### 1. jbrand 随机根命名
- `jbrand_new()`: 64 位随机值，低 8 位替换为高 7 字节的 XOR 校验和，保证 `is_jbrand_value()` 可校验。
- 主目录: `/var/containers/Bundle/Application/.jbroot-%016llX`
- 二次目录(可写): `/var/mobile/Containers/Shared/AppGroup/.jbroot-%016llX`
- `@loader_path/.jbroot` 符号链接指向实际随机根（每层目录内动态维护）。
- 引导时 `find_jbroot()` 扫描主目录下 `.jbroot-*` 命名目录。

### 2. 注入链
- launchdhook 在 `roothide_launchd_postinit` 中将 `basebin/systemhook.dylib` 改名为 `systemhook-%016llX.dylib` 并 `unsandbox` 到 `/usr/lib`，HOOK_DYLIB_PATH 记为 `/usr/lib/systemhook-%016llX.dylib`。
- spawn 黑名单进程时：跳过 DYLD_INSERT_LIBRARIES 注入（`__posix_spawn_orig_wrapper`），使黑名单进程完全不加载 systemhook（进程内无钩子痕迹）。
- 非黑名单进程：`__posix_spawn_hook` 正常注入随机名 systemhook。

### 3. 黑名单（RootHideConfig.plist）
- 路径: `{jbroot}/var/mobile/Library/RootHide/RootHideConfig.plist`
- `appconfig`: `{bundleId: bool}`，true=隐藏。
- `jbclient_blacklist_check_pid/path/bundle` 经 jbserver XPC `JBS_ROOTHIDE_BLACKLIST_CHECK` 查询。
- jbserver 侧 `roothide_blacklist_check` 用 `isBlacklistedPid/Path/App` 判定（blacklist.cpp 维护 pid 集合）。

### 4. 三层隐藏（黑名单进程内，随机根模式下因不注入 systemhook 而天然缺失 → 由 dyldhook/lsd 兜底）
- syscall 层: 参考仓库在 systemhook 内 hook __sysctl/__sysctlbyname（AMFI developer_mode_status=1）。
- OC 层 (lsd.x): `_LSCanOpenURLManager`、`_LSDOpenClient`、`_LSQueryContext`、LSGetInboxURLForBundleIdentifier 过滤。

### 5. iOS 18.5 适配点
- `roothide_is_ios16_or_newer()`: uname release>=22，iOS18.5=24 满足。
- `hideDeveloperMode()`: 内核 sysctl_oid 交换（依赖 kernel slide + kread/kwrite，需确认 iOS 18.5 偏移）。
- dyld `gDyld`/`gAPIs` symbol 与 PAC salt（0xBF31/0xB1B6/0xD48C/0xD2A5）需在 iOS 18.5 验证。
- lsd.x 的 `_LSQueryContext _resolveQueries:...` 方法签名随版本变化，需适配。

## 移植文件清单

### libjailbreak (新增/修改)
| 文件 | 说明 |
|------|------|
| `src/roothider.h` | 汇总头 |
| `src/roothider/{common,blacklist,crashreporter,dyld_patch,exec_patch,exec_trace,recdhash,signatures,unsandbox,unsandbox1,unsandbox2,xpc_hook,jailbreakd,log}.{h,m,c}` | 核心 |
| `src/roothider/mach_exc.defs/h` | MIG |
| `src/jbclient_roothide.c` | client XPC |
| `src/jbroot.c/h` | jbroot 路径转换 |
| `Makefile` | 增加 roothider 编译 |

### launchdhook (新增/修改)
| 文件 | 说明 |
|------|------|
| `src/roothider.m` | spawn 预处理/注入 |
| `src/jbserver/jbdomain_roothide.c` | XPC 域 |
| `src/main.m` | 接入 preinit/postinit |
| `Makefile` | 集成 |

### dyldhook (新增/修改)
| 文件 | 说明 |
|------|------|
| `src/roothider.c` | expandAtLoaderPath hook |
| `src/roothider.S` | trampoline |
| `src/dyld_jbinfo.h` | jbrand 字段 |
| `Makefile` | 集成 + ios16 generated |

### systemhook (新增/修改)
| 文件 | 说明 |
|------|------|
| `src/roothider_main.c` | 隐藏核心 |
| `src/roothider_common.c` | sysctl 伪造 |
| `src/main.c` | 集成 |
| `Makefile` | 集成 |

### roothidehooks (Theos 新增，substrate→ElleKit)
- `lsd.x / springboard.x / cfprefsd.x / installd.x / palera1n.x / pathhook.x / main.x / common.{h,m}`
- ElleKit 提供 substrate 兼容层（libellekit.a + `%hook`/`%orig`/MSHookFunction）。

### jailbreakd (新增)
- `src/main.m / server.m`

### Application (修改)
- `DOBootstrapper.m`: 随机根创建/重随机化 + RootHideConfig.plist 管理。
- 设置 UI: RootHideConfig 黑名单管理（复用/替换现有 DOHiddenRootListController/BlackApple）。

## 风险
- 3.0.4→3.0.5 基座差异需逐一适配（diffless ~100 文件）。
- iOS 18.5 dyld/launchd/lsd 私有符号与偏移未验证。
- ElleKit 对 `%hook` logos 语法兼容性需实测。
