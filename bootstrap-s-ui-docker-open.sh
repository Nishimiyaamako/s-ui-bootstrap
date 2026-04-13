#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/sui-docker-open-bootstrap.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

SUI_DOCKER_COMPOSE_URL='https://raw.githubusercontent.com/alireza0/s-ui/master/docker-compose.yml'
DEFAULT_INSTALL_DIR='/opt/s-ui'

on_error() {
  local line="$1"
  echo "[ERROR] 脚本在第 ${line} 行失败，请查看日志: ${LOG_FILE}" >&2
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

prompt_default() {
  local prompt="$1"
  local default_val="$2"
  local var
  read -r -p "$prompt [默认: ${default_val}]: " var
  echo "${var:-$default_val}"
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

confirm_continue() {
  local ans
  read -r -p "确认开始执行？(y/N): " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 0
  fi
}

port_in_use() {
  local port="$1"
  ss -lnt "( sport = :${port} )" | tail -n +2 | grep -q .
}

install_base_packages() {
  local do_upgrade="$1"

  msg "更新软件源..."
  apt update

  if [[ "$do_upgrade" == "y" ]]; then
    msg "执行系统升级..."
    DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
  else
    warn "已跳过 full-upgrade。"
  fi

  msg "安装基础依赖..."
  DEBIAN_FRONTEND=noninteractive apt -y install \
    curl wget ca-certificates gnupg lsb-release unzip
}

install_docker_engine() {
  if command -v docker >/dev/null 2>&1; then
    warn "检测到 Docker 已安装，跳过安装步骤。"
  else
    msg "安装 Docker（官方脚本）..."
    curl -fsSL https://get.docker.com | sh
  fi

  systemctl enable --now docker
  docker --version

  if docker compose version >/dev/null 2>&1; then
    docker compose version
  else
    warn "未检测到 docker compose 插件，请手动检查 Docker 安装。"
  fi
}

install_sui_docker() {
  local docker_dir="$1"

  msg "下载官方 docker-compose.yml 并启动 S-ui..."
  mkdir -p "$docker_dir"
  cd "$docker_dir"
  wget -q "$SUI_DOCKER_COMPOSE_URL" -O docker-compose.yml
  docker compose up -d
  docker ps --filter name=s-ui
}

show_post_install_info() {
  msg "=== 安装完成，关键信息 ==="
  echo "默认面板端口: 2095"
  echo "默认面板路径: /app/"
  echo "默认订阅端口: 2096"
  echo "默认订阅路径: /sub/"
  echo "默认账号密码: admin / admin"
  echo ""

  docker ps --filter name=s-ui || true
  curl -I --max-time 5 http://127.0.0.1:2095/app/ || true

  warn "当前脚本未做 SSH/UFW/端口收敛，保持开放状态仅用于快速跑通。"
  warn "首次登录后请立即修改默认管理员密码。"
}

main() {
  require_root

  msg "=== S-ui Docker 快速安装（不做安全收敛）==="
  msg "日志文件: ${LOG_FILE}"

  local do_upgrade docker_dir
  do_upgrade=$(prompt_yes_no_default "是否执行 full-upgrade？" "n")
  docker_dir=$(prompt_default "S-ui Docker 安装目录" "$DEFAULT_INSTALL_DIR")

  msg "===== 参数总览（执行前确认）====="
  echo "安装模式           : docker（固定）"
  echo "full-upgrade       : ${do_upgrade}"
  echo "安装目录           : ${docker_dir}"
  echo "Docker compose URL : ${SUI_DOCKER_COMPOSE_URL}"
  echo "安全策略           : 不做 SSH/UFW 收敛，保持端口开放"

  for p in 80 443 2095 2096; do
    if port_in_use "$p"; then
      warn "检测到端口 ${p} 已被占用，docker 启动可能冲突。"
    fi
  done

  confirm_continue
  install_base_packages "$do_upgrade"
  install_docker_engine
  install_sui_docker "$docker_dir"
  show_post_install_info

  msg "=== 脚本执行完成 ==="
}

main "$@"
