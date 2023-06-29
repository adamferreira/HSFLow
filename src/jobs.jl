mutable struct Job
    # Unique Id of the job
    jid::Int
    # Name of the job
    name::String
    # Function to be executed by the job
    f
    # Arguments of `f`
    fargs
    # Keywords arguments of `f`
    fkwargs
    # Unique Id of the Job that created this Job
    pjid::Int
    # Unique Id of the Thread that created this Job
    ptid::Int
    # Unique Id of the Node that created this Job
    pnid::Int
    # Number of CPU this job reserves
    # -- ncpu::Int
    # Quantity of MEMORY this job reserves
    # -- nmem::Int
    # Job priority
    priority::Int
    # Job State (RUNNING, DONE, KILLED, ...)
    state::Symbol
    # Periodicity of the job
    cron::Union{Cron, Nothing}
    # Time when this job was created
    creation_time::DateTime
    # Time when this job was scheduled (set by the scheduler)
    schedule_time::Union{DateTime, Nothing}
    # Time when this job started (set by the scheduler)
    start_time::Union{DateTime, Nothing}
    # Time when this job ended (set by the scheduler)
    end_time::Union{DateTime, Nothing}
    # Maximum amount of time this job can spend in queue
    max_runtime::Period
     # Maximum amount of time this job can spend running
    max_scheduletime::Period
    # Vector of jids, this job will start after all depends are done
    # TODO: Use dict to as depends per states ?
    depends::Vector{Int}
    # TODO: error and output logfiles ?

    function Job(;
        jid = next_job_id(),
        name = string(jid),
        f = x -> nothing,
        fargs = (),
        fkwargs = (),
        pjid = 999,
        ptid = threadid(),
        pnid = nodeid(),
        priority = 1,
        state = :NEW,
        cron = nothing,
        creation_time = Dates.now(),
        schedule_time = nothing,
        start_time = nothing,
        end_time = nothing,
        max_runtime = Dates.Year(1),
        max_scheduletime = Dates.Month(1),
        depends = []
        )
        return new(jid,name,f,fargs,fkwargs,pjid,ptid,pnid,priority,state,cron,creation_time,schedule_time,start_time,end_time,max_runtime,max_scheduletime,depends)
    end
end

Base.run(j::Job) = j.f(j.fargs...;j.fkwargs...)