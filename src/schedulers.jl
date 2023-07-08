abstract type AsbtractJobScheduler end
abstract type AsbtractRunner end


#const RUNNER_POOL = Base.RefValue{Channel{Int}}()
"""
Rewrite of [`Threads.@spawn`](@ref) without scheduling the task.
And forcing task to stick to their original thread (Runner)
"""
macro sticky_spawn2(expr)
    letargs = Base._lift_one_interp!(expr)

    thunk = esc(:(()->($expr)))
    var = esc(Base.sync_varname)
    quote
        let $(letargs...)
            local task = Task($thunk)
            # Disallow task migration, we want those task to always run on their threads
            task.sticky = true
            if $(Expr(:islocal, var))
                put!($var, task)
            end
            task
        end
    end
end

macro sticky_spawn(expr)
    :(Task(()->$(esc(expr))))
end


mutable struct Runner <: AsbtractRunner
    scheduler::AsbtractJobScheduler
    # Channel (from scheduler) where this runner will take jobs
    channel::Channel{Int}
    # Underlying Task of this runner
    task::Task
    # On which thread this Runner is running
    function Runner(s::AsbtractJobScheduler, c::Channel{Int}, target_tid::Int)
        t = @sticky_spawn begin
            println("Launching Runner on thread $(threadid())")
            while s.test
                jid = take!(c)
                println("Launching job $jid on thread $(threadid())")
                job = from_id(s, jid)
                # TODO: view = false ?
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
                    error(e) #debug
                    update!(s, jid, :state, :ERROR)
                    update!(s, jid, :freturn, e)
                finally
                    update!(s, jid, :end_time, Dates.now())
                    # Notify that current's Job data is available
                    notify(j.fdata_avail)
                    # Schedule the next job occurence if this the current job is periodic
                    # Transform `from_id(s, jid)` (DataFrameRow) into a Job object, now its a copy of whats in the scheduler
                    nextj = nextjob(Job(; Dict(pairs(job))...))
                    if !isnothing(nextj)
                        schedule_job!(s, nextj)
                    end
                end
            end
        end
        # The Runner's task is created but not scheduled, affect it to a specific thread
        ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, target_tid-1)
        # The Runner can be started
        schedule(t)
        return new(s, c, t)
    end
end

mutable struct JobScheduler <: AsbtractJobScheduler
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
    inner_loop::Union{Nothing, Task}
    # Runners
    runners::Vector{AsbtractRunner}
    # Round-robin runner id generator
    next_runner::Threads.Atomic{Int}
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
            [],
            Threads.Atomic{Int}(1),
            true
        )
    end
end

function next_runner_id!(s::JobScheduler)::Int
    return Base.max(1, Threads.atomic_add!(s.next_runner, 1) % (s.nrunners+1))
end

function unsafe_from_id(s::JobScheduler, jid::Int)::DataFrameRow
    # No view to not alter datatable
    df = filter(row -> row.jid == jid, s.datatable; view=true)
    #TODO: Throw JobNotFound Exception if length(df) != 1?
    return df[1,:]
end

function from_id(s::JobScheduler, jid::Int)::DataFrameRow
    row = @lock s.datatable_lock begin
        return unsafe_from_id(s, jid)
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
    s.inner_loop = @sticky_spawn begin 
        println("Launching Inner Loop on thread ", threadid())
        sleepy = 0.05
        while s.test
            enqueue_waiting!(s)
            sleepy = Base.max(0.05, sleepy)
            sleep(0.05)
        end
    end
    # The inner loop is sticked to the main thread (1 (0 in the ccal))
    ccall(:jl_set_task_tid, Cvoid, (Any, Cint), s.inner_loop, 0)
    schedule(s.inner_loop)
    sleep(0.05)

    # Launch runners, each on a different threads
    s.runners = [Runner(s, s.channels[i], i) for i ∈ 1:s.nrunners]
end

"""
    Queue all elligible jobs (to be used in the inner loop)
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
            put!(s.runners[next_runner_id!(s)].channel, dequeue!(s.queue))
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

function fetch_job(s::JobScheduler, jid::Int)
    j = from_id(s, jid)
    test = j.fdata_avail
    #sleep(0.05)
    @show current_task() == s.runners[1].task
    if j.freturn === nothing
        # If j.f runs on the same runner as the inner_loop, this will blonk BEFORE notify can ever be called
        println("Now waiting on thread ", threadid())
        wait(test)
    end
    return j.freturn
end
