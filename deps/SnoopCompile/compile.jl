using SnoopCompile

@snoopi_bot BotConfig(
    "Atom",
    blacklist = [
        "realpath′",
        "restart_copyto_nonleaf!",
        "allocatedinline"
    ]
)
