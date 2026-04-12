# s-ui-bootstrap

Debian 12 新机首装脚本：自动完成系统基线与 S-ui 安装引导（不包含 Cloudflare 自动化）。

## 一键下载并启动

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Nishimiyaamako/s-ui-bootstrap/main/bootstrap-s-ui-singbox.sh)
```

## 功能范围

- root / Debian 12 环境检查
- 可选系统升级与基础依赖安装
- SSH 加固（可选，禁用密码登录）
- UFW 最小化放行（SSH + 443）
- S-ui 安装（通过你输入的官方脚本 URL）
- S-ui 初始化人工介入提示（账号密码、端口、Web Base Path）
- 本机连通性验证

## 不包含内容

- Cloudflare Tunnel 自动创建
- 域名绑定与 DNS 配置
- Cloudflare Access 策略创建
- Reality 入站与用户创建

## 使用方式

```bash
chmod +x ./bootstrap-s-ui-singbox.sh
bash ./bootstrap-s-ui-singbox.sh
```

## 日志位置

```text
/var/log/sui-singbox-bootstrap.log
```

