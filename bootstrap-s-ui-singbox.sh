#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/sui-singbox-bootstrap.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

SUI_INSTALL_DIRECT_CMD='bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)'
SUI_DOCKER_COMPOSE_URL='https://raw.githubusercontent.com/alireza0/s-ui/master/docker-compose.yml'

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

prompt_yes_no_default() {
  local prompt="$1"
  local default_val="$2"
  local var

  while true; do
    read -r -p "$prompt [默认: ${default_val}] (y/n): " var
    var="${var:-$default_val}"
    var="${var,,}"

    if [[ "$var" == "y" || "$var" == "yes" ]]; then
      echo "y"
      return 0
    fi
    if [[ "$var" == "n" || "$var" == "no" ]]; then
      echo "n"
      return 0
    fi

    echo "请输入 y 或 n。"
  done
}

prompt_install_mode() {
  local var
  while true; do
    read -r -p "S-ui 安装模式 (direct/docker) [默认: direct]: " var
    var="${var:-direct}"
    var="${var,,}"
    if [[ "$var" == "direct" || "$var" == "docker" ]]; then
      echo "$var"
      return 0
    fi
    echo "安装模式仅支持 direct 或 docker。"
  done
}

validate_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= 65535))
}

confirm_continue() {
  local ans
  read -r -p "确认以上参数无误并开始执行？(y/N): " ans
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

install_sui_direct() {
  msg "按官方 direct 安装方式执行 S-ui 安装..."
  bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
}

install_docker_engine() {
  msg "安装 Docker（官方方式）..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  docker --version
}

install_sui_docker_compose() {
  local docker_dir="$1"

  msg "按官方 docker-compose 方式安装 S-ui..."
  mkdir -p "$docker_dir"
  cd "$docker_dir"
  wget -q "$SUI_DOCKER_COMPOSE_URL" -O docker-compose.yml
  docker compose up -d
  docker ps --filter name=s-ui
}

show_post_install_info() {
  local install_mode="$1"

  msg "=== 安装完成，关键信息 ==="
  echo "默认面板端口: 2095"
  echo "默认面板路径: /app/"
  echo "默认订阅端口: 2096"
  echo "默认订阅路径: /sub/"
  echo "默认账号密码: admin / admin"
  echo ""

  if [[ "$install_mode" == "direct" ]]; then
    command -v s-ui >/dev/null 2>&1 && s-ui status || true
    systemctl status s-ui --no-pager | sed -n '1,10p' || true
    systemctl status sing-box --no-pager | sed -n '1,10p' || true
  else
    docker ps --filter name=s-ui || true
  fi

  curl -I --max-time 5 http://127.0.0.1:2095/app/ || true

  msg "首次登录后请立即修改默认管理员密码。"
}

main() {
  require_root
  require_debian12

  msg "=== S-ui + sing-box 首装脚本（Debian 12）==="
  msg "日志文件: ${LOG_FILE}"
  msg "该脚本基于官方 README 的安装方式实现（direct/docker，默认 direct）。"

  local do_upgrade
  local harden_ssh
  local ssh_port
  local panel_port_plan
  local install_mode
  local docker_dir

  do_upgrade=$(prompt_yes_no_default "是否执行 full-upgrade？" "y")
  harden_ssh=$(prompt_yes_no_default "是否执行 SSH 加固（禁密登录）？" "y")
  ssh_port=$(prompt_default "SSH 端口" "22")
  panel_port_plan=$(prompt_default "计划使用的 S-ui 面板端口（仅用于占用检查与规划）" "2095")
  install_mode=$(prompt_install_mode)
  docker_dir=$(prompt_default "Docker 安装目录（docker 模式时使用）" "/opt/s-ui")

  if ! validate_port "$ssh_port"; then
    echo "SSH 端口非法: ${ssh_port}" >&2
    exit 1
  fi

  if ! validate_port "$panel_port_plan"; then
    echo "面板端口非法: ${panel_port_plan}" >&2
    exit 1
  fi

  msg "===== 参数总览（执行前确认）====="
  echo "系统要求          : Debian 12"
  echo "full-upgrade       : ${do_upgrade}"
  echo "SSH 加固           : ${harden_ssh}"
  echo "SSH 端口           : ${ssh_port}"
  echo "安装模式           : ${install_mode}"
  echo "面板端口规划       : ${panel_port_plan}"
  echo "Docker 安装目录    : ${docker_dir}"
  echo "Direct 官方命令    : ${SUI_INSTALL_DIRECT_CMD}"
  echo "Docker compose URL : ${SUI_DOCKER_COMPOSE_URL}"

  if port_in_use "$panel_port_plan"; then
    warn "检测到端口 ${panel_port_plan} 已被占用，后续请在 S-ui 中改端口或释放占用。"
  fi

  if [[ "$install_mode" == "docker" ]]; then
    for p in 80 443 2095 2096; do
      if port_in_use "$p"; then
        warn "docker 模式默认会占用端口 ${p}，当前检测到已占用。"
      fi
    done
  fi

  confirm_continue

  install_base_packages "$do_upgrade"
  configure_ssh "$ssh_port" "$harden_ssh"
  configure_ufw "$ssh_port"

  if [[ "$install_mode" == "direct" ]]; then
    install_sui_direct
  else
    install_docker_engine
    install_sui_docker_compose "$docker_dir"
  fi

  show_post_install_info "$install_mode"

  msg "=== 脚本执行完成 ==="
  msg "你现在可以按习惯继续手动完成域名与网页侧配置。"
}

main "$@"
