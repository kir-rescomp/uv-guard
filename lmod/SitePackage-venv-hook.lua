-- Lmod load hook: warn when an EasyBuild Python module is loaded while a
-- virtual environment is active. Merge into the site's SitePackage.lua; if a
-- "load" hook is already registered there, call venv_python_guard(t) from it
-- rather than registering a second function, which would replace the first.

local hook = require("Hook")

local PYTHON_MODULE_PATTERNS = {
   "^Python/",
   "^Python%-bundle%-PyPI/",
   "^SciPy%-bundle/",
}

function venv_python_guard(t)
   local venv = os.getenv("VIRTUAL_ENV")
   if not venv or mode() ~= "load" then return end
   local name = t.modFullName or ""
   for _, pattern in ipairs(PYTHON_MODULE_PATTERNS) do
      if name:find(pattern) then
         LmodMessage(
            "WARNING: " .. name .. " is being loaded while the virtual environment "
            .. venv .. " is active.\n"
            .. "It places another Python and its packages on PATH/PYTHONPATH, which can "
            .. "shadow the environment's packages.\n"
            .. "Load modules before activating the environment, or use 'uvactivate'.")
         return
      end
   end
end

hook.register("load", venv_python_guard)
