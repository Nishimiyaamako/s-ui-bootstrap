# s-ui-bootstrap

Debian 12 新机首装脚本：基于 S-ui 官方 README 的安装方式，支持 `direct` 与 `docker` 两种模式（默认 `direct`），并可在首轮安装后可选接续 cloudflared Docker 配置。

## 一键下载并启动

```bash
apt update && apt install -y curl && bash <(curl -fsSL https://raw.githubusercontent.com/Nishimiyaamako/s-ui-bootstrap/main/bootstrap-s-ui-singbox.sh)
```

## 安装来源（与官方 README 对齐）

- direct（默认）
  - `bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)`
- docker
  - 使用官方 `docker-compose.yml`：
  - `https://raw.githubusercontent.com/alireza0/s-ui/master/docker-compose.yml`

## 脚本特点

- 执行前先收集所有参数，再展示“参数总览”
- 你确认后才开始执行，避免脚本跑到一半回退困难
- 首轮完成后可选继续 cloudflared 配置：支持粘贴 Cloudflare 网页给的 `docker run ... --token` 命令并自动转后台 + 开机自启
- cloudflared 默认使用 `host` 网络模式，避免容器内 `localhost` 回源到自身引发 502

## 参数收集项

- 是否执行 `full-upgrade`
- 是否 SSH 加固（禁用密码登录）
- SSH 端口
- 计划面板端口（用于检查和规划）
- 安装模式（`direct` / `docker`）
- Docker 安装目录（docker 模式）
- 首轮结束后是否继续 cloudflared 配置（可选）

## 功能范围

- root / Debian 12 环境检查
- 可选系统升级与基础依赖安装
- SSH 加固（可选，禁用密码登录）
- UFW 最小化放行（SSH + 443）
- S-ui 官方 direct 安装
- 或 S-ui 官方 docker-compose 安装
- 自动配置开机自启（direct: `s-ui` + `sing-box`，docker: `docker` + 容器重启策略）
- 可选 cloudflared Docker 部署（自动后台运行、`restart=unless-stopped`、默认 host 网络）
- 安装后状态与默认入口验证

## 不包含内容

- Cloudflare 域名绑定与 DNS 配置（网页端）
- Cloudflare Access 策略创建（网页端）
- Reality 入站与用户创建

## Cloudflared 可选后续（脚本内交互）

脚本首轮安装完成后会询问是否继续 cloudflared 配置：

1. 选择继续
2. 粘贴 Cloudflare 网页给的命令，例如：

```bash
docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token <xxx>
```

脚本会自动：
- 提取 `--token`
- 以后台模式重建容器
- 固定容器名 `cloudflared`
- 设置 `--restart unless-stopped`
- 使用 `--network host` 降低回源兼容问题

即使关闭 shell，容器也会继续运行并随系统启动。

Zero Trust 里建议把 Service URL 配为：`http://127.0.0.1:2095`（不要写 `https://`）。

## 使用方式

```bash
chmod +x ./bootstrap-s-ui-singbox.sh
bash ./bootstrap-s-ui-singbox.sh
```

## 默认安装信息（S-ui 官方）

- Panel Port: `2095`
- Panel Path: `/app/`
- Subscription Port: `2096`
- Subscription Path: `/sub/`
- User/Password: `admin`

> 首次登录后请立即修改默认密码。

## 日志位置

```text
/var/log/sui-singbox-bootstrap.log
```
