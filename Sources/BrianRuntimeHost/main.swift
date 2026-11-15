import Darwin

// Isolate the model and its native helper in a process group that the app can
// cancel together. This executable runs only the supplied bundled runtime.
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { exit(64) }
if setsid() == -1 && getpgrp() != getpid() { exit(71) }
let pointers = arguments.dropFirst().map { strdup($0) } + [nil]
execv(arguments[1], pointers)
perror("Unable to start the local model runtime")
exit(71)
