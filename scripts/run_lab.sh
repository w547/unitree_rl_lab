#!/usr/bin/env bash
# 一键运行 unitree_rl_lab sim2sim：编译 unitree_mujoco（官方仿真器）+ lab 的 g1_ctrl
# 用法：./scripts/run_lab.sh [--no-build] [-j N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$WS_ROOT/env.sh"

SIM_DIR="$WS_ROOT/unitree_mujoco/simulate"
SIM_BIN="$SIM_DIR/build/unitree_mujoco"
CTRL_DIR="$LAB_ROOT/deploy/robots/g1_29dof"
CTRL_BIN="$CTRL_DIR/build/g1_ctrl"
CONFIG="$SIM_DIR/config.yaml"
LOG_DIR="$LAB_ROOT/logs"
JOBS="$(nproc 2>/dev/null || echo 4)"
BUILD=1

usage() {
    cat <<'EOF'
用法: ./scripts/run_lab.sh [选项]

默认行为:
  先编译 unitree_mujoco 和 unitree_rl_lab 的 g1_29dof 控制器，然后启动仿真闭环

选项:
  --no-build    跳过编译，直接运行已有产物
  -j, --jobs N  指定并行编译线程数，默认使用 nproc
  -h, --help    显示帮助

键位（先点击 MuJoCo 窗口）:
  F + ↑         Passive -> FixStand
  T + U         FixStand/Velocity 互切
  按住 F 2 秒 + ↓ / ←   Velocity -> Mimic_Dance_102 / Mimic_Gangnam_Style
  F + K         回到 Passive
  W/S A/D Q/E   前后 / 横移 / 转向
  8 / 7         下放 / 收紧吊带；9 松开吊带

说明:
  - 机器人初始由吊带吊起，先按 F+↑ 进 FixStand，再按 8 逐次下放到脚刚触地
  - 退出时会自动恢复 config.yaml 并关闭仿真器和控制器
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)
            BUILD=0
            shift
            ;;
        -j|--jobs)
            JOBS="${2:-}"
            if [[ ! "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
                echo "[错误] --jobs 需要一个正整数" >&2
                exit 2
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[错误] 未知参数: $1" >&2
            usage
            exit 2
            ;;
    esac
done

for d in "$SIM_DIR" "$CTRL_DIR"; do
    if [[ ! -d "$d" ]]; then
        echo "[错误] 目录不存在: $d"
        exit 1
    fi
done

build() {
    echo
    echo "==> [1/2] 编译 unitree_mujoco"
    cmake -S "$SIM_DIR" -B "$SIM_DIR/build" -DCMAKE_PREFIX_PATH="$HOME/.local/deps/usr"
    cmake --build "$SIM_DIR/build" --parallel "$JOBS"

    echo
    echo "==> [2/2] 编译 unitree_rl_lab g1_29dof 控制器"
    cmake -S "$CTRL_DIR" -B "$CTRL_DIR/build" -DCMAKE_PREFIX_PATH="$HOME/.local/deps/usr"
    cmake --build "$CTRL_DIR/build" --parallel "$JOBS"
}

if [[ "$BUILD" -eq 1 ]]; then
    build
fi

for f in "$SIM_BIN" "$CTRL_BIN" "$CONFIG"; do
    if [[ ! -e "$f" ]]; then
        echo "[错误] 缺少文件: $f"
        echo "请先运行 ./scripts/run_lab.sh（不带 --no-build）"
        exit 1
    fi
done

RUN_LOG_DIR="$LOG_DIR/lab_run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_LOG_DIR"
SIM_LOG="$RUN_LOG_DIR/sim.log"
CTRL_LOG="$RUN_LOG_DIR/ctrl.log"

HAS_JOY=0
JOY_DEV=""
for dev in /dev/input/js*; do
    if [[ -e "$dev" ]]; then
        HAS_JOY=1
        JOY_DEV="$dev"
        break
    fi
done

JOY_TYPE="$(sed -nE 's/^[[:space:]]*joystick_type[[:space:]]*:[[:space:]]*"?([A-Za-z_]+)"?.*/\1/p' "$CONFIG" | head -1)"

CONFIG_BAK="$(mktemp /tmp/unitree_lab_sim_config.XXXXXX)"
cp "$CONFIG" "$CONFIG_BAK"

SIM_PID=""
CTRL_PID=""
TAIL_PID=""

cleanup() {
    local code="$1"
    trap - EXIT INT TERM HUP
    set +e

    if [[ -n "$TAIL_PID" ]]; then
        kill "$TAIL_PID" 2>/dev/null
    fi
    if [[ -n "$CTRL_PID" ]]; then
        kill "$CTRL_PID" 2>/dev/null
    fi
    if [[ -n "$SIM_PID" ]]; then
        kill "$SIM_PID" 2>/dev/null
    fi
    for pid in "$TAIL_PID" "$CTRL_PID" "$SIM_PID"; do
        if [[ -n "$pid" ]]; then
            wait "$pid" 2>/dev/null
        fi
    done

    if [[ -f "$CONFIG_BAK" ]]; then
        cp "$CONFIG_BAK" "$CONFIG"
        rm -f "$CONFIG_BAK"
    fi

    echo
    echo "运行结束。日志目录: $RUN_LOG_DIR"
    exit "$code"
}

trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup 129' HUP

if [[ "$JOY_TYPE" == "keyboard" ]]; then
    echo "[提示] 使用键盘手柄 (joystick_type: keyboard)，操作前先点击 MuJoCo 窗口"
elif [[ "$HAS_JOY" -eq 1 ]]; then
    echo "[提示] 检测到手柄: $JOY_DEV"
else
    echo "[提示] 未检测到手柄，临时使用 use_joystick: 0"
    echo "       仿真器和控制器可以连接，但 FSM 只能停在 Passive。"
    if grep -qE '^[[:space:]]*use_joystick[[:space:]]*:' "$CONFIG"; then
        sed -i -E 's/^([[:space:]]*)use_joystick[[:space:]]*:.*/\1use_joystick: 0/' "$CONFIG"
    else
        printf '\nuse_joystick: 0\n' >> "$CONFIG"
    fi
fi

# MuJoCo 的 GLFW 是 X11 后端，DISPLAY 必须形如 ":N" 或 "host:N"。
# 桌面启动的终端偶尔把 WAYLAND_DISPLAY 的值误当成 DISPLAY，这里统一校正。
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${DISPLAY:-}" || "$DISPLAY" != *:* ]]; then
    for sock in /tmp/.X11-unix/X*; do
        [[ -S "$sock" ]] || continue
        export DISPLAY=":${sock##*X}"
        break
    done
fi

echo
echo "==> 启动 MuJoCo 仿真器（官方 unitree_mujoco）"
echo "    配置: robot=g1  domain_id=0  interface=lo  joystick=keyboard"
echo "    显示: DISPLAY=${DISPLAY:-<未设置>}"
echo "    日志: $SIM_LOG"

SIM_ATTEMPTS=3
for ((attempt = 1; attempt <= SIM_ATTEMPTS; attempt++)); do
    : > "$SIM_LOG"
    "$SIM_BIN" >> "$SIM_LOG" 2>&1 &
    SIM_PID=$!

    sleep 3
    if kill -0 "$SIM_PID" 2>/dev/null; then
        break
    fi

    wait "$SIM_PID" 2>/dev/null || true
    SIM_PID=""

    if grep -q "could not initialize GLFW" "$SIM_LOG" && [[ "$attempt" -lt "$SIM_ATTEMPTS" ]]; then
        echo "[提示] MuJoCo 显示初始化失败 (第 $attempt/$SIM_ATTEMPTS 次)，2 秒后重试"
        echo "       DISPLAY=${DISPLAY:-<未设置>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<未设置>} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<未设置>}"
        sleep 2
        continue
    fi

    echo "[错误] 仿真器启动失败，最近日志："
    echo "       DISPLAY=${DISPLAY:-<未设置>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<未设置>} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<未设置>}"
    tail -n 20 "$SIM_LOG" || true
    exit 1
done

echo
echo "==> 启动 unitree_rl_lab g1_ctrl --network=lo"
echo "    日志: $CTRL_LOG"
echo "    按 Ctrl+C 结束"
( cd "$CTRL_DIR/build" && exec "$CTRL_BIN" --network=lo ) > "$CTRL_LOG" 2>&1 &
CTRL_PID=$!

tail -n +1 -F "$CTRL_LOG" &
TAIL_PID=$!

CTRL_STATUS=0
while kill -0 "$SIM_PID" 2>/dev/null && kill -0 "$CTRL_PID" 2>/dev/null; do
    sleep 1
done

if ! kill -0 "$CTRL_PID" 2>/dev/null; then
    wait "$CTRL_PID" || CTRL_STATUS=$?
    echo
    echo "[提示] g1_ctrl 已退出，最近日志："
    tail -n 20 "$CTRL_LOG" || true
fi

if ! kill -0 "$SIM_PID" 2>/dev/null; then
    echo
    echo "[提示] 仿真器已退出，最近日志："
    tail -n 20 "$SIM_LOG" || true
fi

exit "$CTRL_STATUS"
