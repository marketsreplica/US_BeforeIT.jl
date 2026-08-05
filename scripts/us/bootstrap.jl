import Pkg

const US_SCRIPT_DIR = @__DIR__
const US_REPO_ROOT = normpath(joinpath(US_SCRIPT_DIR, "..", ".."))

Pkg.activate(US_SCRIPT_DIR)
Pkg.develop(path = US_REPO_ROOT)
Pkg.instantiate()
