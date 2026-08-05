using Pkg
using TOML

const SCRIPT_DIR = @__DIR__
const PROJECT_FILE = joinpath(SCRIPT_DIR, "Project.toml")
const SOURCES_FILE = joinpath(SCRIPT_DIR, "sources.toml")

Pkg.activate(SCRIPT_DIR)

sources = TOML.parsefile(SOURCES_FILE)
calibration_code = sources["calibration_code"]

Pkg.add(
    PackageSpec(
        url = calibration_code["url"],
        rev = calibration_code["revision"],
    ),
)
cd(SCRIPT_DIR) do
    Pkg.develop(PackageSpec(path = joinpath("..", "..")))
end
Pkg.instantiate()

println("Austria pipeline environment is ready: $PROJECT_FILE")
