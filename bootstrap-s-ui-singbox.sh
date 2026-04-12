#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/sui-singbox-bootstrap.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

on_error() {
  local line="$1"
  echo "[ERROR] 脚本在第 ${line} 行失败。请查看日志: ${LOG_FILE}" >&2
}
trap 'on_error $LINENO' ERR

msg() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "请使用 root 运行此脚本。" >&2
    exit 1
  fi
}

require_debian12() {
  if [[ ! -f /etc/os-release ]]; then
    echo "无法识别系统，缺少 /etc/os-release。" >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "debian" ]]; then
    echo "仅支持 Debian 系统，当前: ${ID:-unknown}" >&2
    exit 1
  fi

  if [[ "${VERSION_ID:-}" != "12" ]]; then
    echo "推荐 Debian 12，当前版本: ${VERSION_ID:-unknown}。为避免兼容问题，脚本退出。" >&2
    exit 1
  fi
}

port_in_use() {
  local port="$1"
  ss -lnt "( sport = :${port} )" | tail -n +2 | grep -q .
}

prompt_required() {
  local prompt="$1"
  local var
  while true; do
    read -r -p "$prompt" var
    if [[ -n "$var" ]]; then
      echo "$var"
      return 0
    fi
    echo "输入不能为空，请重试。"
  done
}

prompt_default() {
  local prompt="$1"
  local default_val="$2"
  local var
  read -r -p "$prompt [默认: ${default_val}]: " var
  if [[ -z "$var" ]]; then
    echo "$default_val"
  else
    echo "$var"
  fi
}

confirm_continue() {
  local ans
  read -r -p "确认继续执行？(y/N): " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 0
  fi
}

configure_ssh() {
  local ssh_port="$1"
  local harden_ssh="$2"

  if [[ "$harden_ssh" != "y" ]]; then
    warn "已跳过 SSH 加固。"
    return 0
  fi

  msg "开始 SSH 加固..."
  cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%F-%H%M%S)"

  sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -ri 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  sed -ri 's/^#?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

  if grep -q '^PermitRootLogin' /etc/ssh/sshd_config; then
    sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  else
    echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
  fi

  if grep -qE '^#?Port ' /etc/ssh/sshd_config; then
    sed -ri "s|^#?Port .*|Port ${ssh_port}|" /etc/ssh/sshd_config
  else
    echo "Port ${ssh_port}" >> /etc/ssh/sshd_config
  fi

  systemctl restart ssh
  systemctl status ssh --no-pager | sed -n '1,8p'
}

configure_ufw() {
  local ssh_port="$1"

  msg "配置 UFW 防火墙..."
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${ssh_port}/tcp"
  ufw allow 443/tcp
  ufw --force enable
  ufw status verbose
}

install_base_packages() {
  local do_upgrade="$1"

  msg "更新软件源..."
  apt update

  if [[ "$do_upgrade" == "y" ]]; then
    msg "执行系统升级..."
    DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
  else
    warn "你选择跳过 full-upgrade。"
  fi

  msg "安装基础依赖..."
  DEBIAN_FRONTEND=noninteractive apt -y install \
    curl wget ca-certificates gnupg lsb-release jq ufw unzip openssl vim
}

install_sui() {
  local sui_install_url="$1"

  msg "下载并执行 S-ui 安装脚本: ${sui_install_url}"
  local tmp_file="/tmp/s-ui-install.sh"
  curl -fsSL "$sui_install_url" -o "$tmp_file"
  bash "$tmp_file"
}

manual_sui_init_guide() {
  local panel_port="$1"

  local panel_cli=""
  if command -v s-ui >/dev/null 2>&1; then
    panel_cli="s-ui"
  elif command -v x-ui >/dev/null 2>&1; then
    panel_cli="x-ui"
  fi

  msg "===== S-ui 初始化（手动）====="
  echo "请在菜单中至少完成以下项目："
  echo "1) 重置管理员用户名和密码"
  echo "2) 修改面板端口为: ${panel_port}"
  echo "3) 设置随机 Web Base Path"
  echo ""

  if [[ -n "$panel_cli" ]]; then
    read -r -p "按回车打开 ${panel_cli} 菜单进行手动初始化..."
    "$panel_cli" || true
  else
    warn "未检测到 s-ui/x-ui 命令，请按 S-ui 文档手动完成初始化。"
  fi

  read -r -p "完成 S-ui 初始化后，按回车继续..."
}

validate_panel_port() {
  local panel_port="$1"

  msg "验证 S-ui 本机连通性..."

  if ! port_in_use "$panel_port"; then
    warn "端口 ${panel_port} 当前未监听，请检查 S-ui 是否已启动。"
  else
    msg "检测到端口 ${panel_port} 已监听。"
  fi

  curl -I --max-time 5 "http://127.0.0.1:${panel_port}" || true
}

main() {
  require_root
  require_debian12

  msg "=== S-ui + sing-box 首装脚本（Debian 12）==="
  msg "日志文件: ${LOG_FILE}"

  local do_upgrade
  local timezone
  local harden_ssh
  local ssh_port
  local panel_port
  local sui_install_url

  do_upgrade=$(prompt_default "是否执行 full-upgrade？(y/n)" "y")
  timezone=$(prompt_default "时区" "Asia/Shanghai")
  harden_ssh=$(prompt_default "是否执行 SSH 加固（禁密登录）？(y/n)" "y")
  ssh_port=$(prompt_default "SSH 端口" "22")
  panel_port=$(prompt_default "S-ui 面板端口" "2053")
  sui_install_url=$(prompt_required "S-ui 官方安装脚本 URL（raw 链接）: ")

  if port_in_use "$panel_port"; then
    warn "端口 ${panel_port} 已被占用，请更换后重试。"
    exit 1
  fi

  msg "===== 参数确认 ====="
  echo "full-upgrade: ${do_upgrade}"
  echo "timezone: ${timezone}"
  echo "harden_ssh: ${harden_ssh}"
  echo "ssh_port: ${ssh_port}"
  echo "panel_port: ${panel_port}"
  echo "s-ui url : ${sui_install_url}"
  confirm_continue

  install_base_packages "$do_upgrade"

  msg "设置时区: ${timezone}"
  timedatectl set-timezone "$timezone"

  configure_ssh "$ssh_port" "$harden_ssh"
  configure_ufw "$ssh_port"

  install_sui "$sui_install_url"
  manual_sui_init_guide "$panel_port"
  validate_panel_port "$panel_port"

  msg "=== 脚本执行完成 ==="
  msg "Cloudflare 相关自动化步骤已移除。"
  msg "后续域名入口与网页侧配置请按你的习惯手动完成。"
}

main "$@"
