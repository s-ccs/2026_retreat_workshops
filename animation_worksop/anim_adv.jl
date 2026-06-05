using Pkg; Pkg.activate(".")

#Pkg.add(["CairoMakie", "GLMakie", "Plots", "Animations", "Observables"])
using Observables
using GLMakie
using Animations
using CairoMakie


# 1. play around with easing functions

function easing_dot_demo(;
    easing = sineio(),
    x_start = -3.0, x_end = 3.0,
    t_start = 0.0, t_end = 1.0,
    fps = 30, nframes = 120,
    markersize = 30,
    title = "Easing demo"
)
    # Animation rule:
    # at t_start -> x_start
    # at t_end   -> x_end
    x_anim = Animation(
        [t_start, t_end],
        [x_start, x_end],
        [easing]
    )

    t = Observable(t_start)
    x_pos = @lift(at(x_anim, $t))

    fig = Figure(size = (700, 300))

    ax = Axis(
        fig[1, 1],
        limits = (x_start - 1, x_end + 1, -1, 1),
        title = title,
        xlabel = "x position",
        ylabel = "y position"
    )

    scatter!(ax, x_pos, Observable(0.0), markersize = markersize)

    display(fig)

    for τ in range(t_start, t_end, length = nframes)
        t[] = τ
        sleep(1 / fps)
    end

    return fig
end
easing_dot_demo()
easing_dot_demo(
    easing = linear(),
    title = "Linear motion"
)

easing_dot_demo(
    easing = saccadic(2),
    title = "Saccadic motion"
)

# 2. line into P300

time = range(-0.2, 0.8, length = 600)

# Start: simple flat line
y_start = zeros(length(time))

# End: P300-like waveform
# small N100 + large positive P300 around 300 ms
n100 = @. -1.2 * exp(-((time - 0.10)^2) / (2 * 0.035^2))
p300 = @.  4.0 * exp(-((time - 0.32)^2) / (2 * 0.080^2))

y_p300 = n100 .+ p300

function smooth_ease(x)
    x = clamp(x, 0, 1)
    return x^2 * (3 - 2x)   # smoothstep
end

progress_raw = Observable(0.0)
progress = @lift(smooth_ease($progress_raw))

# Morph line:
# progress = 0 → flat line
# progress = 1 → P300
y_anim = @lift((1 - $progress) .* y_start .+ $progress .* y_p300)


fig = Figure(size = (850, 450))

ax = Axis(
    fig[1, 1],
    xlabel = "Time from stimulus onset (s)",
    ylabel = "Amplitude",
    title = "A line transforms into a P300"
)

xlims!(ax, minimum(time), maximum(time))
ylims!(ax, -2, 5)

hlines!(ax, [0], linestyle = :dash)
vlines!(ax, [0], linestyle = :dot)

lines!(
    ax,
    time,
    y_anim;
    linewidth = 5
)

display(fig)

for p in range(0, 1, length = 140)
    progress_raw[] = p
    sleep(1 / 30)
end

# 3. Effect plot

time = range(-0.2, 0.8, length = 700)

function gaussian(t, μ, σ)
    @. exp(-((t - μ)^2) / (2σ^2))
end

# More ERP-like than pure P300:
# small early negativity + late positivity
function erp_waveform(time; amp = 1.0, latency_shift = 0.0)
    n100 = @. -1.0 * gaussian(time, 0.10 + latency_shift, 0.035)
    p200 = @.  0.8 * gaussian(time, 0.20 + latency_shift, 0.050)
    p300 = @.  3.0 * amp * gaussian(time, 0.34 + latency_shift, 0.090)

    return n100 .+ p200 .+ p300
end

# Predictor levels: fixation latency in ms
fix_latency_levels = [100, 200, 300, 400, 500]

# Convert fixation latency into amplitude and latency effects
amps = range(0.65, 1.35, length = length(fix_latency_levels))
latency_shifts = range(-0.025, 0.025, length = length(fix_latency_levels))

ys_levels = [
    erp_waveform(time; amp = amp, latency_shift = shift)
    for (amp, shift) in zip(amps, latency_shifts)
]

y_average = reduce(+, ys_levels) ./ length(ys_levels)

# Animation logic
phase = Observable(0.0)

# smooth in-out loop:
# 0   -> one average line
# 0.5 -> fully separated levels
# 1   -> back to one average line
function loop_ease(x)
    # x goes from 0 to 1
    # returns 0 -> 1 -> 0
    s = sinpi(x)^2
    return s
end

separation = @lift(loop_ease($phase))

# Make the separation more dramatic
function sharp_transition(x; p = 3)
    x = clamp(x, 0, 1)
    return x^p / (x^p + (1 - x)^p)
end

sep = @lift(sharp_transition($separation; p = 4))

# For each pair of amp and latency_shift: create one ERP waveform
ys_anim = [
    @lift((1 - $sep) .* y_average .+ $sep .* y_level)
    for y_level in ys_levels
]

avg_alpha = @lift(1 - $sep)
level_alpha = @lift(0.25 + 0.75 * $sep)

# Figure
begin 
    fig = Figure(size = (900, 500))

    ax = Axis(
        fig[1, 1],
        xlabel = "Time from event onset (s)",
        ylabel = "Amplitude",
        title = "Effect of fixation latency on ERP magnitude"
    )

    xlims!(ax, minimum(time), maximum(time))
    ylims!(ax, -1.8, 4.5)

    hlines!(ax, [0], linestyle = :dash)
    vlines!(ax, [0], linestyle = :dot)

    # Average line, visible when collapsed
    lines!(
        ax,
        time,
        y_average;
        linewidth = 5,
        color = @lift(RGBAf(0, 0, 0, $avg_alpha)), #RGBAf(red, green, blue, alpha)
        label = "average"
    )

    # Level lines
    for (i, y_anim) in enumerate(ys_anim)
        lines!(
            ax,
            time,
            y_anim;
            linewidth = 3,
            color = @lift(RGBAf(0.1 + 0.15i, 0.2, 0.9 - 0.12i, $level_alpha)),
            label = "$(fix_latency_levels[i]) ms"
        )
    end

    axislegend(ax, position = :rt)

    display(fig)
end 
while true
    for p in range(0, 1, length = 180)
        phase[] = p
        sleep(1 / 30)
    end
end