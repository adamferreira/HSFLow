
JOB_STATES = [
    :NEW,
    :WAITING,
    :QUEUED,
    :RUNNING,
    :ERROR,
    :KILLED,
    :CANCELED,
    :DONE
]

struct Job
    # Unique Id of the job
    jid::Int
    # Name of the job
    name::String
    # Function to be executed by the job
    f
    # Arguments of `f`
    fargs::Tuple
    # Keywords arguments of `f`
    fkwargs::NamedTuple
    # Returned value of `f` (will hold Exception if `f` failed)
    freturn::Any
    # Unique Id of the Job that created this Job
    pjid::Int
    # Unique Id of the Thread that created this Job
    ptid::Int
    # Unique Id of the Node that created this Job
    pnid::Int
    # Unique Id of the Thread that ran this Job
    rtid::Int
    # Unique Id of the Node that ran this Job
    rnid::Int
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
    # Time when this job should be available for running
    start_after::DateTime
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
        fkwargs = NamedTuple(),
        freturn = nothing,
        pjid = 1,
        ptid = threadid(),
        pnid = nodeid(),
        rtid = 0,
        rnid = 0,
        priority = 1,
        state = :NEW,
        cron = nothing,
        creation_time = Dates.now(),
        schedule_time = nothing,
        start_time = nothing,
        end_time = nothing,
        start_after = Dates.now(),
        max_runtime = Dates.Year(1),
        max_scheduletime = Dates.Month(1),
        depends = []
        )
        # Sanitize single arguments
        fargs = isa(fargs, Tuple) ? fargs : (fargs,)
        fkwargs = isa(fkwargs, NamedTuple) ? fkwargs : NamedTuple()
        return new(
            jid,
            name,
            f,
            fargs,
            fkwargs,
            freturn,
            pjid,
            ptid,
            pnid,
            rtid,
            rnid,
            priority,
            state,
            cron,
            creation_time,
            schedule_time,
            start_time,
            end_time,
            start_after,
            max_runtime,
            max_scheduletime,
            depends
        )
    end

    function Job(f, @nospecialize args...; kwargs...)
        return Job(;
            f = f,
            fargs = Tuple(args),
            fkwargs = Base.merge(NamedTuple(), kwargs)
        )
    end
end