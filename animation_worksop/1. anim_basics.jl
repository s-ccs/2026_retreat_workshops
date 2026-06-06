using Pkg; Pkg.activate(@__DIR__)

# To install required packages, uncomment and run the line below:
# Pkg.add(["CairoMakie", "GLMakie", "Animations", "Observables"])
using Observables
using GLMakie
using Animations
using CairoMakie


# I. Observables
# 0. Vocabulary
# Observable = changing value
# listener   = code that reacts to change
# notify     = tell listeners that value changed
# lifting     = create new observable that depends on other observables

# 1. Core actions
x = Observable(0)   # create
x[] = 1             # update
x[]                 # read
x

x = Observable(0.0) # stores Float64 values; good when you know the value type
x2 = Observable{Real}(0.0) # allows any Real number, e.g. Float64, Int, Rational
x3 = Observable{Any}(0.0) # accepts any type

points = Observable(Point2f[(0, 0)]) # a changing vector of 2D points, useful for plots that update

# 2. creating a listener (callback)
# on(x) = when x changes, run this code
on(x) do val
    println("x changed to $val. AMAZING!!!!!!!!!!!")
end

x[] = 1
x[] = 2

temperature = Observable(20)
on(temperature) do value
    if value > 30
        println("🔥 Warning: too hot! Temperature = $value")
    else
        println("Temperature is okay: $value")
    end
end

temperature[] = 22
temperature[] = 28
temperature[] = 35
temperature[] = 25

on(points) do pts
    println("Number of points: $(length(pts))")
end

points[]

points[] = [points[]..., Point2f(1, 1)]

# 3. lifting
x = Observable(2)
y = @lift($x^2)

x[] = 5
y[]   # 25


health = Observable(100)
status = @lift(
    $health <= 0  ? "💀 dead" :
    $health < 30  ? "🟥 critical" :
    $health < 70  ? "🟨 injured" :
                    "🟩 healthy"
)

x[] = 1.0
health[] = 80
status[]   # "🟩 healthy"

health[] = 50
status[]   # "🟨 injured"

health[] = 20
status[]   # "🟥 critical"

health[] = 0
status[]   # "💀 dead"

# 4. lift with several Observables

a = Observable(2)
b = Observable(3)

sum_value = @lift($a + $b)

sum_value[]   # 5

a[] = 10
sum_value[]   # 13

b[] = 100
sum_value[]   # 110
##############

# II. Simple animations

# 1. create and store animation
xs = range(0, 2π, length = 400)

phase = Observable(0.0)
ys = @lift(sin.(xs .+ $phase))

fig = Figure(size = (700, 400))
ax = Axis(fig[1, 1], xlabel = "x", ylabel = "sin(x + phase)")
lines!(ax, xs, ys)
ylims!(ax, -1.2, 1.2)

mkpath("output")

record(fig, "output/sine_wave.mp4", range(0, 2π, length = 120); framerate = 30) do φ
    phase[] = φ
end

# 2. display animation in separate window
GLMakie.activate!() # rerun figure with GLMakie backend to display animation in separate window


display(fig)

for φ in range(0, 2π, length = 120)
    phase[] = φ
    sleep(1 / 30)
end

# III. interactive animation

# 1. create slider to control animation
xs = range(0, 2π, length = 400)
fig = Figure(size = (700, 450))

ax = Axis(
    fig[1, 1],
    xlabel = "x",
    ylabel = "sin(x + phase)",
    title = "Slider-controlled sine wave"
)

slider = Slider(fig[2, 1], range = 0:0.01:2π, startvalue = 0)

phase = slider.value              # this is an Observable
ys = @lift(sin.(xs .+ $phase))    # derived Observable

lines!(ax, xs, ys)
ylims!(ax, -1.2, 1.2)

display(fig)

# 2. create toggle to control animation

fig = Figure()

ax = Axis(fig[1, 1], limits = (0, 600, -2, 2))
hidexdecorations!(ax)

t = Observable(0.0)
points = lift(t) do t
    x = range(t-1, t+1, length = 500)
    @. sin(x) * sin(2x) * sin(4x) * sin(23x)
    #@. means: put dots everywhere in this expression where broadcasting is needed.
end

lines!(ax, points, color = (1:500) .^ 2, linewidth = 2, colormap = [(:blue, 0.0), :blue])

gl = GridLayout(fig[2, 1], tellwidth = false)
Label(gl[1, 1], "Live Update")
toggle = Toggle(gl[1, 2], active = false)

on(fig.scene.events.tick) do tick
    toggle.active[] || return
    t[] += tick.delta_time
end

fig

# IV. Easing animations

# At animation time 0.0 → x position is -3.0
# At animation time 1.0 → x position is  3.0
# Move between them using sineio() easing
x_anim = Animation(
    [0.0, 1.0],
    [-3.0, 3.0],
    [sineio()]  
)
# sineio: slooow start → fast middle → slooow end
# sine = sine-shaped speed curve
# i    = ease in
# o    = ease out

t = Observable(0.0) # time of animation, from 0 to 1

# current x-position is computed from animation at time t
x_pos = @lift(at(x_anim, $t))

fig = Figure(size = (700, 250))
ax = Axis(
    fig[1, 1],
    limits = (-4, 4, -1, 1),
    title = "Eased motion",
    xlabel = "x position",
    ylabel = "y position"
)
scatter!(ax, x_pos, Observable(0.0), markersize = 30)

display(fig)

for τ in range(0, 1, length = 120)
    t[] = τ
    sleep(1 / 30)
end


