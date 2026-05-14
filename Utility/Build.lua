return {
    __version = "3.8",
      __log = {
        "[/] Fixed actor being nil inside FunctionInfo actor resolver.",
        "[+] Added safe Config fallback in GenSS to prevent nil indexing.",
        "[/] Fixed FFICopy calls using wrong argument order.",
        "[/] Fixed CollectedTables stacking and returned collectedTables properly.",
        "[+] Added safer debug.getinfo/constants/upvalues handling.",
        "[+] Added protected hookfunction wrapping with coroutine support.",
        "[/] Fixed Function Debug crashing from restricted thread UI access.",
        "[+] Added queued debug logging system for safe console flushing.",
        "[+] Added RenderStepped console flusher for thread-safe UI updates.",
        "[/] Fixed appendDebug being missing/nil in Function Debug.",
        "[+] Added safer Instance/function/table debug serialization.",
        "[/] Fixed hook cleanup/unhook reliability.",
        "[+] Added force unhook button support.",
        "[/] Fixed debug console memory stacking from uncontrolled lines.",
        "[+] Added safer old function execution using coroutine wrapping.",
        "[+] Added additional pcall protections without changing behavior."
    }
}
