module HSFlow

include("cron.jl")
println("Hello")


export CronSlice, Cron,
        yearly,
        annually,
        monthly,
        weekly,
        daily,
        midnight,
        hourly,
        once

c = CronSlice{UInt8,0,7}(UInt8(32))
@show next_slice(c, 3)

@show TCronSlice

end