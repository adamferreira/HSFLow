using HSFlow
using Dates

s = scheduler()

function myfct(x,y)
    sleep(60)
    return x + y
end

@show s.datatable
for i=1:10
    schedule_job!(s, Job(myfct, 10, i))
end