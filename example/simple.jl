using HSFlow
using Dates

s = scheduler()

function myfct(x,y)
    sleep(3)
    return x + y
end

function greet()
    println("Hello its $(Dates.now()) and we are on thread $(threadid()) of node $(nodeid()).")
    sleep(60)
end

#@show s.datatable
#for i=1:10
#    schedule_job!(s, Job(myfct, 10, i))
#end

"""
schedule_job!(s,Job(;
    f = greet,
    start_after = Dates.now() + Dates.Second(10)
))

schedule_job!(s,Job(;
    f = greet,
    start_after = Dates.now() + Dates.Second(30)
))
"""

running = Job(;
    name = "Running job",
    f = greet,
    cron = Cron("00","*/5","*","*","*","*")
)


@schedule begin
    a = 5
    return a + 10
end

sleep(2)
x = fetch_job(s, 5)
@show x

#@show s.datatable