module HSFlow
using Dates
using DataFrames
using Distributed: myid
using DataStructures: PriorityQueue, enqueue!, dequeue!

include("cron.jl")
export  CronSlice, Cron,
        yearly,
        annually,
        monthly,
        weekly,
        daily,
        midnight,
        hourly,
        once,
        nnext

        # Job counter (atomic and local to node)
const JOB_ID = Threads.Atomic{Int}(2)
next_job_id() = Threads.atomic_add!(JOB_ID, 1)
include("jobs.jl")
export  Job,
        nodeid,
        threadid

nodeid() = myid()
threadid() = Base.Threads.threadid()

include("schedulers.jl")
export JobScheduler, scheduler, schedule_job!

# Forward calls with node's scheduler
scheduler() = SCHEDULER
for fct in Symbol[
        :enqueue_waiting!,
        :schedule_job!
    ]
    @eval $(fct)(args...; kwargs...) = $(fct)(scheduler(), args...; kwargs...)
end

function __init__()
    global SCHEDULER = JobScheduler(3)
    # Add job that queue all waiting jobs (starting now)
    queuing = Job(;
        name = "Queuing job",
        f = s -> enqueue_waiting!(s),
        fargs = SCHEDULER,
        start_after = Dates.now(),
        # Master job = 1
        pjid = 1,
        # This will run every 2 seconds (Use Threads.Condition.notify instead ? So that put in queue in bloquing and not consuming resources)
        cron = Cron("*/2","*","*",'*','*','*')
    )

    running = Job(;
        name = "Running job",
        f = s -> launch_queued!(s),
        fargs = SCHEDULER,
        start_after = Dates.now(),
        # Master job = 1
        pjid = 1,
        # This will run every 2 seconds (Use Threads.Condition.notify instead ? So that put in queue in bloquing and not consuming resources)
        cron = Cron("*/2","*","*",'*','*','*')
    )

    # Schedule first jobs
    #schedule_job!(scheduler(), queuing)
    #schedule_job!(scheduler(), running)

    launch_runners!(SCHEDULER)
    #enqueue_waiting!(SCHEDULER)
end

"""
@show j = Job()
s = JobScheduler()

j1 = Job()
j2 = Job()
j3 = Job(; depends = [2,3])

schedule_job!(s, j1)
schedule_job!(s, j2)
schedule_job!(s, j3)

#j.f = x -> x + 10
#j.fargs = 5
#@show j.f(j.fargs...; j.fkwargs...)
#@show Base.invoke(j.f, Tuple{Int}, j.fargs...; j.fkwargs...)

println(s.datatable)

enqueue_waiting!(s)
println(s.queue)
"""
end