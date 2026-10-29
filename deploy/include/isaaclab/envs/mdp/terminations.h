#pragma once

#include <chrono>

#include <spdlog/spdlog.h>

#include "isaaclab/envs/manager_based_rl_env.h"

namespace isaaclab
{
namespace mdp
{

// 诊断用：以 4 Hz 限频打印倾角与根四元数，便于区分“瞬间跳变”和“逐渐增长”
inline void log_orientation(ManagerBasedRLEnv* env, float tilt)
{
    static auto last = std::chrono::steady_clock::now();
    const auto now = std::chrono::steady_clock::now();
    if (std::chrono::duration<double>(now - last).count() < 0.25) {
        return;
    }
    last = now;

    const auto q = env->robot->data.root_quat_w;
    spdlog::info("[diag] t={:.2f}s tilt={:.3f}rad({:.0f}deg) quat=({:.3f},{:.3f},{:.3f},{:.3f}) |q|={:.3f} gz={:.3f}",
                 env->episode_length * env->step_dt,
                 tilt, tilt * 57.2958f,
                 q.x(), q.y(), q.z(), q.w(), q.norm(),
                 env->robot->data.projected_gravity_b[2]);
}

inline bool bad_orientation(ManagerBasedRLEnv* env, float limit_angle = 1.0)
{
    auto & asset = env->robot;
    auto & data = asset->data.projected_gravity_b;
    const float tilt = std::fabs(std::acos(-data[2]));
    log_orientation(env, tilt);
    return tilt > limit_angle;
}

} 
} 