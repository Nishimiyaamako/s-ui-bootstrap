# s-ui-bootstrap

Debian 12 新机首装脚本：基于 S-ui 官方 README 的安装方式，支持 `direct` 与 `docker` 两种模式（默认 `direct`）。

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

## 参数收集项

- 是否执行 `full-upgrade`
- 是否 SSH 加固（禁用密码登录）
- SSH 端口
- 计划面板端口（用于检查和规划）
- 安装模式（`direct` / `docker`）
- Docker 安装目录（docker 模式）

## 功能范围

- root / Debian 12 环境检查
- 可选系统升级与基础依赖安装
- SSH 加固（可选，禁用密码登录）
- UFW 最小化放行（SSH + 443）
- S-ui 官方 direct 安装
- 或 S-ui 官方 docker-compose 安装
- 安装后状态与默认入口验证


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

