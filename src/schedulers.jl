abstract type AsbtractJobScheduler end
abstract type AsbtractRunner end

mutable struct JobScheduler
    # Number of runners (Thread) that will be launched
    nrunners::Int
    # Holding job data
    datatable::DataFrame
    # Lock for datatable
    datatable_lock::Threads.ReentrantLock
    # Priority queue for jobs that are available for running
    queue::PriorityQueue{Int,Int}
    # For locking the queue
    queue_lock::Threads.ReentrantLock
    # Channels (blocking) to send jobs to local runners
    channels::Vector{Channel{Int}}
    # Inner loop (thread) that will affect job to runners
    inner_loop
    runners
    test::Bool

    function JobScheduler(nrunners::Int)
        # Create the datatable with the same column as Job's attributes
        datatable = DataFrame([
            (n => t[]) 
            for (n, t) in zip(fieldnames(Job), fieldtypes(Job))
        ])
        return new(
            nrunners,
            datatable,
            Threads.ReentrantLock(),
            PriorityQueue{Int,Int}(),
            Threads.ReentrantLock(),
            [Channel{Int}(10) for i ∈ 1:nrunners],
            nothing,
            nothing,
            true
        )
    end
end

#const RUNNER_POOL = Base.RefValue{Channel{Int}}()

mutable struct Runner <: AsbtractRunner
    scheduler::JobScheduler
    # Channel (from scheduler) where this runner will take jobs
    channel::Channel{Int}
    # Underlying Task of this runner
    task::Task
    # On which thread this Runner is running
    function Runner(s::JobScheduler, c::Channel{Int})
        t = Threads.@spawn begin
            while s.test
                jid = take!(c)
                println("Launching job $jid on thread $(threadid())")
                job = from_id(s, jid)
                # Update job runtine informations
                update!(s, jid, :state, :RUNNING)
                update!(s, jid, :rtid, threadid())
                update!(s, jid, :rnid, nodeid())
                update!(s, jid, :start_time, Dates.now())
                # Blocking call to the job's core function
                try
                    # Use invokelatest to avoid the error; method too new to be called from this world context.
                    res = Base.invokelatest(job.f, job.fargs...; job.fkwargs...)
                    update!(s, jid, :state, :DONE)
                    update!(s, jid, :freturn, res)
                catch e
                    error(e)
                    update!(s, jid, :state, :ERROR)
                    update!(s, jid, :freturn, e)
                finally
                    update!(s, jid, :end_time, Dates.now())
                end
            end
        end
        return new(s, c, t)
    end
end

function unsafe_from_id(s::JobScheduler, jid::Int)::DataFrameRow
    # No view to not alter datatable
    df = filter(row -> row.jid == jid, s.datatable; view=true)
    #TODO: Throw JobNotFound Exception if length(df) != 1?
    return df[1,:]
end

function from_id(s::JobScheduler, jid::Int)::DataFrameRow
    row = nothing
    @lock s.datatable_lock begin
        row = unsafe_from_id(s, jid)
    end
    return row
end

function update!(s::JobScheduler, jid::Int, col::Symbol, val)
    @lock s.datatable_lock begin
        j = unsafe_from_id(s, jid)
        j[col] = val
    end
end

function launch_runners!(s::JobScheduler)
    # Launch main inner loop that will queue jobs
    s.inner_loop = Threads.@spawn begin
        while s.test
            enqueue_waiting!(s)
            sleep(2)
        end
    end
    # Launch runners, each on a different threads
    s.runners = [Runner(s, s.channels[i]) for i ∈ 1:length(s.channels)]
end

"""
    Queue all elligible jobs (to be used in a permanent job)
"""
function enqueue_waiting!(s::JobScheduler)
    # Wait for all threads to take their jobs from the queue before queuing new ones
    @lock s.datatable_lock begin
        # Queue only waiting jobs with with correct dates
        datenow = Dates.now()
        waiting = filter(
            row -> row.state == :WAITING && datenow >= row.start_after, 
            s.datatable; view=true
        )
        @lock s.queue_lock begin
            for j in eachrow(waiting)
                j.state = :QUEUED
                enqueue!(s.queue, Pair(j.jid, j.priority))
            end
        end
    end
    # Also submit last job
    # Blocking (only if runner channel is full) send to runners
    if length(s.queue) > 0
        @lock s.queue_lock begin
            put!(s.runners[next_runner_id()].channel, dequeue!(s.queue))
        end
    end
end

function schedule_job!(s::JobScheduler, j::Job)
    # Add job as a row in the data table
    @lock s.datatable_lock begin
        #lenght(unsafe_from_id(s, j.jid)) || error("Job with id $(j.jid) already exists.")
        drows = size(s.datatable)[1]
        push!(
            s.datatable,
            map(f -> getfield(j, f), fieldnames(Job))
        )
        # Change Job's status and schedule time
        # Check if the job has any dependencies
        newj = s.datatable[drows+1,:]
        deps = filter(row -> row.jid ∈ newj.depends, s.datatable; view=true)
        # Check that all dependencies ended correctly, otherwise put the job on hold
        if size(deps)[1] > 0
            newj.state = all([s == :DONE for s in deps.state]) ? :WAITING : :HOLD
        else
            newj.state = :WAITING
        end
        newj.schedule_time = Dates.now()
    end
end
