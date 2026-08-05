using BeforeITWeb

if length(ARGS) != 1
    error("Usage: run.jl <run_dir>")
end

BeforeITWeb.run_worker(ARGS[1])
