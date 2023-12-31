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
export  Job, nextjob,
        nodeid,
        threadid

nodeid() = myid()
threadid() = Base.Threads.threadid()

include("schedulers.jl")
export JobScheduler,
        scheduler,
        schedule_job!,
        fetch_job

# Forward calls with node's scheduler
scheduler() = SCHEDULER
for fct in Symbol[
        :enqueue_waiting!,
        :schedule_job!
    ]
    @eval $(fct)(args...; kwargs...) = $(fct)(scheduler(), args...; kwargs...)
end

macro schedule(expr)
    thunk = esc(:((()->begin
                      $expr
                  end)))
    var = esc(Base.sync_varname)
    quote
        local job = Job($thunk)
        local ref = schedule_job!(scheduler(), job)
        if $(Expr(:islocal, var))
            put!($var, ref)
        end
        ref
    end
end

export @schedule

function __init__()
    global SCHEDULER = JobScheduler(Threads.nthreads())
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
    sleep(1)
    #enqueue_waiting!(SCHEDULER)
end

end