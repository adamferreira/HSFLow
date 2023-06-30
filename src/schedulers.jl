abstract type AsbtractJobScheduler end

mutable struct JobScheduler
    # Holding job data
    datatable::DataFrame
    # Lock for datatable
    datatable_lock::Threads.ReentrantLock
    # Priority queue for jobs that are available for running
    queue::PriorityQueue{Int,Int}
    # For locking the queue
    queue_lock::Threads.ReentrantLock
    # Condition to notify threads that new job are being queud
    queue_event::Threads.Condition

    function JobScheduler()
        # Create the datatable with the same column as Job's attributes
        datatable = DataFrame([
            (n => t[]) 
            for (n, t) in zip(fieldnames(Job), fieldtypes(Job))
        ])
        return new(
            datatable,
            Threads.ReentrantLock(),
            PriorityQueue{Int,Int}(),
            Threads.ReentrantLock(),
            Threads.Condition()
        )
    end
end

function unsafe_from_id(s::JobScheduler, jid::Int)::DataFrameRow
    # No view to not alter datatable
    df = filter(row -> row.jid == jid, s.datatable; view=false)
    #TODO: Throw JobNotFound Exception if length(df) != 1?
    return df[1,:]
end

"""
    Queue all elligible jobs (to be sued in a permanent job)
"""
function enqueue_waiting!(s::JobScheduler)
    # Wait for all threads to take their jobs from the queue before queuing new ones
    wait(s.queue_event)
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
    # Notify threads that queue was feed with jobs
    notify(s.queue_event; all=true)
end


function launch_queued!(s::JobScheduler)
    # Wait for job to be QUEUED by enqueue_waiting!
    wait(s.queue_event)
    # Safely take first job of the queue
    jid = 0
    @lock s.queue_lock begin
        jid = dequeue!(s.queue)
    end
    # Notify that job as been taken from queue
    notify(s.queue_event; all=true)
    # Flag job as running
    j = nothing
    @lock s.datatable_lock begin
        j = unsafe_from_id(s, jid)
    end
    j.state = :RUNNING
    # Launch job in a Thread
    Threads.@spawn begin
        # To be used is this job spawns offpsring jobs
        local curr_jid() = jid 
        @show j.f(j.fargs...;j.fkwargs...)
    end
end

function schedule_job!(s::JobScheduler, j::Job)
    # Add job as a row in the data table
    @lock s.datatable_lock begin
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
