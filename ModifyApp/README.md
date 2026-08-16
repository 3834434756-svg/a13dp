# 修改App (ModifyApp)

云端 AI 越狱控制台。列出桌面全部 App，勾选目标，云端 AI 通过本地 HTTP 服务读取/修改 App 的本地存档或包本体。

## 适配
- iOS 15.0+（含 iOS 18.5）
- arm64 / arm64e（A13 iPhone 11 等）
- 需越狱（Dopamine / palera1n / rootless）

## 安装
- deb：Sileo / Zebra / dpkg 安装
- ipa：TrollStore 安装

## 使用
1. 打开"修改App"，勾选要操作的 App
2. 局域网内让云端 AI 连接 `http://<手机IP>:8765`
3. 本地 HTTP API：
   - `GET /api/context` - 获取选中 App 及可用工具说明
   - `POST /api/exec` - 执行工具（list/read/write/plist/sqlq/sqle）

## 本地 API
| cmd | 说明 |
|-----|------|
| list <path> | 列目录 |
| read <path> [maxBytes] | 读文件（自动识别 plist/文本/二进制hex） |
| write <path> <text> | 写文本文件 |
| plist <path> <keypath> <value> <type> | 修改 plist 数值 |
| sqlq <dbPath> <query> | SQLite 查询 |
| sqle <dbPath> <query> | SQLite 执行 |
