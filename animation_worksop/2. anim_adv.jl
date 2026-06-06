using Pkg; Pkg.activate(@__DIR__)

#Pkg.add(["CairoMakie", "GLMakie", "Animations", "Observables", "Pluto"])
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


#4. ET-EGG animation


using Random
Random.seed!(1)

# ------------------------------------------------------------
# Fake data
# ------------------------------------------------------------

begin
    time = range(0, 2, length = 300)

    # fake gaze path in normalized image coordinates
    gaze_x = @. 0.5 + 0.30sin(2π * time)
    gaze_y = @. 0.5 + 0.22cos(2π * time * 0.7)

    # fake EEG channels
    eeg1 = sin.(8 .* time) .+ 0.15 .* randn(length(time))
    eeg2 = 0.7 .* sin.(10 .* time .+ 1.0) .+ 0.10 .* randn(length(time))
    eeg3 = 0.5 .* sin.(12 .* time .+ 2.0) .+ 0.10 .* randn(length(time))
end

function cat_stimulus(n = 180)
    img = fill(RGBf(0.96, 0.95, 0.90), n, n)

    for row in 1:n, col in 1:n
        x = (col - 0.5) / n
        y = (row - 0.5) / n

        face = ((x - 0.5) / 0.32)^2 + ((y - 0.47) / 0.28)^2 < 1
        left_ear = y > 0.63 && y < 0.92 && abs(x - 0.32) < 0.55 * (y - 0.63)
        right_ear = y > 0.63 && y < 0.92 && abs(x - 0.68) < 0.55 * (y - 0.63)
        left_eye = ((x - 0.39) / 0.045)^2 + ((y - 0.52) / 0.06)^2 < 1
        right_eye = ((x - 0.61) / 0.045)^2 + ((y - 0.52) / 0.06)^2 < 1
        nose = abs(x - 0.5) + 1.6abs(y - 0.42) < 0.05
        mouth = abs((y - 0.34) - 0.45abs(x - 0.5)) < 0.012 && abs(x - 0.5) < 0.12
        whiskers = abs(y - 0.43) < 0.006 && 0.17 < x < 0.38 ||
                   abs(y - 0.38 - 0.16(x - 0.28)) < 0.006 && 0.17 < x < 0.38 ||
                   abs(y - 0.48 + 0.16(x - 0.28)) < 0.006 && 0.17 < x < 0.38 ||
                   abs(y - 0.43) < 0.006 && 0.62 < x < 0.83 ||
                   abs(y - 0.38 + 0.16(x - 0.72)) < 0.006 && 0.62 < x < 0.83 ||
                   abs(y - 0.48 - 0.16(x - 0.72)) < 0.006 && 0.62 < x < 0.83

        if face || left_ear || right_ear
            img[row, col] = RGBf(0.98, 0.72, 0.38)
        end
        if left_eye || right_eye || mouth || whiskers
            img[row, col] = RGBf(0.08, 0.07, 0.06)
        end
        if nose
            img[row, col] = RGBf(0.95, 0.30, 0.42)
        end
    end

    img
end

stimulus_img = permutedims(cat_stimulus())

# ------------------------------------------------------------
# Figure
# ------------------------------------------------------------

begin
    fig = Figure(size = (900, 700))

    ax_img = Axis(
        fig[1, 1],
        title = "Stimulus + gaze",
        aspect = DataAspect(),
        tellwidth = false
    )

    hidedecorations!(ax_img)
    hidespines!(ax_img)

    ax_eeg = Axis(
        fig[2, 1],
        xlabel = "Time [s]",
        ylabel = "EEG channels",
        title = "EEG signal"
    )
end

# ------------------------------------------------------------
# Slider and reactive values
# ------------------------------------------------------------

begin
    slider = Slider(
        fig[3, 1],
        range = 1:1:length(time),
        startvalue = 1,
        linewidth = 22,
        height = 34
    )

    idx = @lift(round(Int, $(slider.value)))

    current_time = @lift(time[$idx])

    current_gaze_x = @lift(gaze_x[$idx])
    current_gaze_y = @lift(gaze_y[$idx])

    path_x = @lift(gaze_x[1:$idx])
    path_y = @lift(gaze_y[1:$idx])

    eeg_time = @lift(time[1:$idx])
    eeg1_path = @lift(eeg1[1:$idx] .+ 2)
    eeg2_path = @lift(eeg2[1:$idx] .+ 0)
    eeg3_path = @lift(eeg3[1:$idx] .- 2)
end

# ------------------------------------------------------------
# Linked plots
# ------------------------------------------------------------

begin
    # in-memory stimulus image
    image!(ax_img, 0..1, 0..1, stimulus_img; interpolate = false)

    # gaze path so far
    lines!(ax_img, path_x, path_y, linewidth = 3)

    # current gaze position
    scatter!(ax_img, current_gaze_x, current_gaze_y, markersize = 20)

    xlims!(ax_img, 0, 1)
    ylims!(ax_img, 0, 1)

    # EEG traces revealed synchronously with the gaze path
    lines!(ax_eeg, eeg_time, eeg1_path, label = "HEOGR")
    lines!(ax_eeg, eeg_time, eeg2_path, label = "Cz")
    lines!(ax_eeg, eeg_time, eeg3_path, label = "Iz")

    # current EEG time cursor
    vlines!(ax_eeg, current_time, linewidth = 3)

    xlims!(ax_eeg, first(time), last(time))
    ylims!(ax_eeg, -3, 3.5)

    axislegend(ax_eeg, position = :rt)

    Label(
        fig[4, 1],
        @lift("Current time = $(round($current_time, digits = 3)) s")
    )
end

# ------------------------------------------------------------
# Layout
# ------------------------------------------------------------

begin
    colsize!(fig.layout, 1, Relative(1))
    rowsize!(fig.layout, 1, Relative(0.42))
    rowsize!(fig.layout, 2, Relative(0.45))
    rowsize!(fig.layout, 3, Fixed(64))
    rowsize!(fig.layout, 4, Fixed(30))
end

display(fig)

# ------------------------------------------------------------
# GIF without slider
# ------------------------------------------------------------

function record_et_eeg_gif(filename = joinpath(@__DIR__, "output", "et_eeg_cat.gif"); framerate = 30)
    mkpath(dirname(filename))

    gif_fig = Figure(size = (900, 660))

    gif_ax_img = Axis(
        gif_fig[1, 1],
        title = "Stimulus + gaze",
        aspect = DataAspect(),
        tellwidth = false
    )

    hidedecorations!(gif_ax_img)
    hidespines!(gif_ax_img)

    gif_ax_eeg = Axis(
        gif_fig[2, 1],
        xlabel = "Time [s]",
        ylabel = "EEG channels",
        title = "EEG signal"
    )

    frame_idx = Observable(1)

    gif_current_time = @lift(time[$frame_idx])
    gif_current_gaze_x = @lift(gaze_x[$frame_idx])
    gif_current_gaze_y = @lift(gaze_y[$frame_idx])

    gif_path_x = @lift(gaze_x[1:$frame_idx])
    gif_path_y = @lift(gaze_y[1:$frame_idx])

    gif_eeg_time = @lift(time[1:$frame_idx])
    gif_eeg1_path = @lift(eeg1[1:$frame_idx] .+ 2)
    gif_eeg2_path = @lift(eeg2[1:$frame_idx] .+ 0)
    gif_eeg3_path = @lift(eeg3[1:$frame_idx] .- 2)

    image!(gif_ax_img, 0..1, 0..1, stimulus_img; interpolate = false)
    lines!(gif_ax_img, gif_path_x, gif_path_y, linewidth = 3)
    scatter!(gif_ax_img, gif_current_gaze_x, gif_current_gaze_y, markersize = 20)

    xlims!(gif_ax_img, 0, 1)
    ylims!(gif_ax_img, 0, 1)

    lines!(gif_ax_eeg, gif_eeg_time, gif_eeg1_path, label = "HEOGR")
    lines!(gif_ax_eeg, gif_eeg_time, gif_eeg2_path, label = "Cz")
    lines!(gif_ax_eeg, gif_eeg_time, gif_eeg3_path, label = "Iz")
    vlines!(gif_ax_eeg, gif_current_time, linewidth = 3)

    xlims!(gif_ax_eeg, first(time), last(time))
    ylims!(gif_ax_eeg, -3, 3.5)

    axislegend(gif_ax_eeg, position = :rt)

    Label(
        gif_fig[3, 1],
        @lift("Current time = $(round($gif_current_time, digits = 3)) s")
    )

    colsize!(gif_fig.layout, 1, Relative(1))
    rowsize!(gif_fig.layout, 1, Relative(0.48))
    rowsize!(gif_fig.layout, 2, Relative(0.47))
    rowsize!(gif_fig.layout, 3, Fixed(30))

    record(gif_fig, filename, 1:length(time); framerate = framerate) do i
        frame_idx[] = i
    end
end

# Run this line when you want to create the GIF:
# record_et_eeg_gif()
