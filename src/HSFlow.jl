module HSFlow
using Dates

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
        once,
        nnext
dt = now()
c = daily()
@show dt
@show c
"""
@show Dates.month(dt)
@show yearly().month
@show collect(yearly().month)
#@show iterate(yearly().dayofweek)
@show next_slice(yearly().month, Dates.month(dt))
@show next_slice(yearly().month, min(yearly().month))
@show tonext_month(dt, yearly())
#@show Dates.tonext(now(), weekly())
"""



dump(c)
@show next_slice(c.minute, min(c.minute))
@show tonext_second(dt, c)
@show tonext_hour(dt, c)
@show Dates.tonext(dt, c)
end