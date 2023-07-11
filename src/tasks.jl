function AdvancedTask(f; at=Dates.now(), holds = [])
    # Outer task, the actual code that will be launched
    ot = @task begin
        it = @task
            # Wait for dependency tasks
            wait.(holds)
            # Wait for start time
            Δ = at - Dates.now()
            sleep(Δ)
        end
        # Schedule internal task to "statt" immediatly
        schedule(it)
        # Wait for all internal task (start time and dependencies) events
        wait(it)
        # Call `f`
        return f()
    end
    return ot
end

#TODO: support Cron
function schedule(f; onthread=nothing, at=Dates.now(), holds = [])
    ot = AdvancedTask(f; at=at, holds=holds)
    # TODO, schedule `ot` on specific thread
    schedule(ot)
end