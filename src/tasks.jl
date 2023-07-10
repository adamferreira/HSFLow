function AdvancedTask(f; onthread=nothing, at=Dates.now(), holds = [])
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
        # TODO, schedule on specific thread
        schedule(it)
        # Wait for all internal task (start time and dependencies) events
        wait(it)
        # Call `f`
        return f()
    end
    return ot
end