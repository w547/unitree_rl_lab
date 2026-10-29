# unitree_rl_lab 变更日志

记录 `unitree_rl_lab` 工程的代码、脚本与配置改动。构建运行日志保存在 `logs/`，不写入本文件。`unitree_rl_mjlab` 工程见 `unitree_rl_mjlab/CHANGELOG.md`。

## 写日志规则

1. 每条记录以 `## YYYY-MM-DD` 开头，日期下先写 1–2 句总结，句式：`因为 <需求/问题>，从 <原状态> 修改为 <新状态>。`
2. 总结之后依次写：背景、改动表、验证、已知限制（无内容可省略）。
3. 改动表固定四列：`类型 | 文件 | 说明`；类型只用 新增 / 修改 / 删除 / 生成。
4. 只记事实：改了什么、为什么改、怎么验证的；不写过程叙述，不重复背景。
5. `logs/` 下的构建运行日志属于产物，不写入本文件；配置项若只是运行期临时修改，需注明是否恢复。

## 2026-10-29

因为要用官方 `unitree_mujoco` 给 lab 工程做无手柄 sim2sim，从“官方仿真器不支持键盘、缺少 MuJoCo 引擎、lab 只能借 mjlab 的入口手动分步启动”修改为“官方仿真器支持键盘手柄，双击 `unitree_rl_lab_编译并运行.desktop` 即完成编译并启动 G1 仿真闭环”。

### 背景

lab 的 `deploy` 只提供控制器，不含仿真器。官方 `unitree_mujoco` 原状：`simulate/mujoco` 引擎目录缺失；`physics_joystick.h` 只有 `XBoxJoystick` / `SwitchJoystick`，`main.cc` 无键盘映射；`config.yaml` 为 `robot: go2`、`domain_id: 1`、`use_joystick: 0`、`enable_elastic_band: 0`。当前环境没有 `/dev/input/js*`，无键盘映射时 FSM 只能停在 Passive。

依赖仍复用根目录 `env.sh` 的 `~/.local/deps/usr` 前缀（`unitree_sdk2`、ddscxx、yaml-cpp 等），本次未改 `env.sh`。lab 的 `deploy` 源码、FSM 配置与策略文件均未改动，改动集中在仿真器输入层与启动脚本。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 新增 | `unitree_mujoco/simulate/mujoco/` | 补入 MuJoCo 3.3.6 引擎（`include/`、`lib/`、`bin/`），与 mjlab 的 `simulate/mujoco` 同版本，`mjVERSION_HEADER 336` |
| 修改 | `unitree_mujoco/simulate/src/physics_joystick.h` | 新增 `KeyboardJoystick`：从 GLFW 按键状态生成 `lx/ly/rx`、A/B/X/Y、十字键、LB/RB、LT/RT；键盘模式把 LT/RT 的 `smooth` 设为 1，按下即生效 |
| 修改 | `unitree_mujoco/simulate/src/main.cc` | `user_key_cb` 把按键按下/松开写入 `KeyboardJoystick`；新增 `glfwSetWindowFocusCallback`，窗口失焦时清空按键状态 |
| 修改 | `unitree_mujoco/simulate/src/unitree_sdk2_bridge.h` | `joystick_type` 增加 `keyboard` 分支，错误提示列出 `xbox` / `switch` / `keyboard` |
| 修改 | `unitree_mujoco/simulate/config.yaml` | `robot: g1`、`robot_scene: scene.xml`、`domain_id: 0`、`use_joystick: 1`、`joystick_type: keyboard`、`print_scene_information: 0`、`enable_elastic_band: 1` |
| 新增 | `scripts/run_lab.sh` | lab 一键编译（`unitree_mujoco` + `unitree_rl_lab/deploy/robots/g1_29dof`）并启动仿真闭环；支持 `--no-build`、`-j N`；日志写入 `logs/lab_run_YYYYmmdd_HHMMSS/` 的 `sim.log` / `ctrl.log` |
| 新增 | `scripts/run_lab_click.sh` | 双击入口；调用 `run_lab.sh`，结束后保留终端窗口 |
| 新增 | `unitree_rl_lab_编译并运行.desktop` | GNOME 桌面启动器；`Terminal=true`；`Exec` 指向 `scripts/run_lab_click.sh` |
| 修改 | `scripts/run_all.sh` → `scripts/run_mjlab.sh`、`scripts/run_all_click.sh` → `scripts/run_mjlab_click.sh`、`编译并运行.desktop` → `unitree_rl_mjlab_编译并运行.desktop` | mjlab 侧入口加工程前缀，避免与 lab 入口同名；详见 `CHANGELOG_unitree_rl_mjlab.md` |

`run_lab.sh` 复用 mjlab 脚本的健壮逻辑：`config.yaml` 先备份、退出时恢复；无手柄且非 keyboard 模式时临时 `use_joystick: 0`；`DISPLAY` 不含冒号时从 `/tmp/.X11-unix/X*` 校正；仿真器 3 次启动重试；`trap` 清理仿真器、控制器与 `tail` 进程。

### 键位（lab 的 `g1_29dof/config/config.yaml`）

| 键盘 | 手柄 | 作用 |
|---|---|---|
| `F` + `↑` | LT + up | Passive → FixStand |
| `T` + `U` | RB + X | FixStand → Velocity；Mimic → Velocity |
| 按住 `F` 2 秒 + `↓` | LT(2s) + down | Velocity → Mimic_Dance_102 |
| 按住 `F` 2 秒 + `←` | LT(2s) + left | Velocity → Mimic_Gangnam_Style |
| `F` + `K` | LT + B | 回到 Passive |
| `W` / `S`、`A` / `D`、`Q` / `E` | 左摇杆、右摇杆 | 前后 / 横移 / 转向 |
| `7` / `8` / `9` | — | 收紧 / 下放 / 松开吊带 |

操作前先点击 MuJoCo 窗口获取焦点；组合键先按住扳机键，再按动作键。

### 验证

- `bash -n` 通过（`run_lab.sh`、`run_lab_click.sh`）；三个新文件已 `chmod +x`
- 带编译模式实跑：`unitree_mujoco` 与 `g1_ctrl` 均 `Built target`；`logs/lab_run_20261029_110328/sim.log` 打印 `MuJoCo version 3.3.6`、`Mujoco data is prepared`、`Using unitree_hg DDS IDL for robot g1`；`ctrl.log` 输出 `Connected to robot.`、五个状态初始化完成、`FSM: Start Passive`
- `--no-build` 实跑（`logs/lab_run_20261029_110218`）同样启动成功；SIGINT 退出后无残留 `unitree_mujoco` / `g1_ctrl`，`config.yaml` 保持 `use_joystick: 1`、`joystick_type: "keyboard"`
- 桌面入口实跑 3 次（`logs/lab_run_20261029_110724`、`110858`、`111139`）均启动到 `FSM: Start Passive`
- 键盘联调（吊带悬空状态）触达 Passive → FixStand → Velocity → Mimic_Dance_102 → Velocity → Mimic_Gangnam_Style

### 已知限制

- G1 的 `scene.xml` 没有站立 keyframe，机器人初始由吊带吊起；下放高度需目视按 `8` 逐次调整，脚本无法自动判断脚触地
- 着地后 `bad_orientation`（倾角 > 1.0 rad）会把 Velocity 切回 Passive，着地行走的稳定性尚未解决
- 键盘摇杆只有 -1/0/+1 三档，速度指令不如物理摇杆细腻；按键只在 MuJoCo 窗口聚焦时有效
- 删除 mjlab 后，`env.sh` 里的 mjlab onnxruntime 路径、`编译全部工程.desktop` / `scripts/build_all.sh`（目前只编译 mjlab 产物）会失效，需要另行整理

## 2026-10-28

因为 lab 工程要脱离 mjlab 的 `g1` 控制器独立做 sim2sim，从“lab 只有部署源码、无构建产物”修改为“`g1_29dof` 的 `g1_ctrl` 编译完成”。

### 背景

`unitree_rl_lab/deploy/robots/g1_29dof` 自带 `config/policy`（velocity、dance_102、gangnam_style 的 `policy.onnx` 与参数），需要先确认能在本机按 `CMakeLists.txt` 编出控制器，才能接仿真器联调。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 生成 | `unitree_rl_lab/deploy/robots/g1_29dof/build/g1_ctrl` | 用 `cmake` 直接构建 `deploy/robots/g1_29dof`，产物约 5.5 MB |

未修改 lab 源码、`CMakeLists.txt` 与策略配置。

### 验证

- 产物存在且可执行；10-29 与官方 `unitree_mujoco` 联调时输出 `Connected to robot.`、五个状态初始化完成、`FSM: Start Passive`

## 2026-10-29

因为要把工程纳入 Git 版本管理、将散落在工作区根目录的文件收进对应工程，从「运行脚本、日志、.desktop 入口、变更日志放在 robot_rl 工作区根目录」修改为「全部移入 `unitree_rl_lab` 工程内，脚本按新位置自适应路径」。

### 改动

| 类型 | 文件 | 说明 |
|---|---|---|
| 移动 | `scripts/run_lab.sh` | 从工作区 `scripts/` 移入本工程 `scripts/`；`ROOT` 拆为 `LAB_ROOT`（工程根）与 `WS_ROOT`（工作区根），`env.sh` 与 `unitree_mujoco` 走 `WS_ROOT`，控制器与日志走 `LAB_ROOT` |
| 移动 | `scripts/run_lab_click.sh` | 从工作区 `scripts/` 移入本工程，内部 `./scripts/run_lab.sh` 相对调用不变 |
| 移动 | `unitree_rl_lab_编译并运行.desktop` | 移入本工程根目录，`Exec`/`Path` 更新为本工程 `scripts/run_lab_click.sh` 与工程根 |
| 移动 | `CHANGELOG_unitree_rl_lab.md` | 重命名并移入本工程根目录 `CHANGELOG.md` |
| 移动 | `logs/lab_run_*` | 工作区 `logs/` 下 10 个 lab 运行日志目录移入本工程 `logs/`（`.gitignore` 已有 `**/logs/*`，不进入版本库） |
| 移动 | `doc/QA/2026-10-29_工程文件归置与GitHub同步.md` | 工作区 `QA/` 下跨工程的 Git 同步与文件归置记录归入本工程 `doc/QA/` |

### 验证

- `bash -n` 语法检查通过；`$LAB_ROOT/logs`、`$WS_ROOT/unitree_mujoco/simulate` 路径均存在。

### 已知限制

- 未实际启动仿真闭环，仅做了路径与语法静态校验。
