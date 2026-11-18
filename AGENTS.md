# AGENTS.md

pogeminilib is a library for programs that speak the Gemini protocol,
clients first, in Oberon-2, compiled with poc, the Peaseblossom Oberon
Compiler: URLs, requests and responses, a client connection in poc's
cooperative `Tasks` and a blocking one without them, trust on first
use, client certificates, and gemtext parsing and writing; later, the
server engine now in pogemini, moved here. PLAN.md is
the design and roadmap; this file is operational notes for an agent
working in this repo, not a design doc.

Its siblings are its model; read their `AGENTS.md` before designing
anything, since most of their text is confirmed behaviour of poc,
libtls and Gemini clients that applies here unchanged:

- **pogemini** (`~/Repos/Oberon/pogemini`): a Gemini server on the same
  libraries. Its `GemRequest` (URL rules), `GemServer` (the engine),
  its listing writer in `GemFiles`, and its tests' `GemClient`, `Child`
  and `Check` are where this library's modules start. Its PLAN.md
  records each decision about the protocol made so far.
- **polibtls** (`~/Repos/Oberon/polibtls`): libtls for poc. README.md,
  "Things to know", and AGENTS.md, "Confirmed facts", are what is known
  about libtls, OpenSSL and other Gemini clients. Its
  `examples/GeminiFetch.Mod` is the client's starting point.
- **posockets** (`~/Repos/Oberon/posockets`) and **pounix**
  (`~/Repos/Oberon/pounix`): their GNUmakefiles (a library built and
  installed), halt tests and valgrind setup are the ones to copy.

## Status

As of 2026-11-18, only the plan: PLAN.md and this file. Nothing is
built; Phase 0 (the skeleton) is next. Every open question in PLAN.md
has been decided with the user (struck through there, each recorded
where it applies); new ones go there as they arise. Two changes in
other repositories come first: a `poll` with a deadline in posockets
(before Phase 4) and a peer public-key hash in polibtls (before
Phase 5).

## Reference material

| What | Where |
|---|---|
| Gemini protocol | `gemini://geminiprotocol.net/docs/protocol-specification.gmi` (https mirror: https://geminiprotocol.net/docs/protocol-specification.gmi); 0.24.1 is the version pogemini follows |
| Gemtext | `gemini://geminiprotocol.net/docs/gemtext-specification.gmi` (https mirror: https://geminiprotocol.net/docs/gemtext-specification.gmi) |
| URIs | RFC 3986 (section 5 for resolving a reference; 5.4 its examples), RFC 3987 (IRIs) |
| polibtls | `~/Repos/Oberon/polibtls`: README.md, `doc/Tls.md`, `doc/TlsTasks.md`, `examples/GeminiFetch.Mod`, `examples/GeminiHello.Mod` |
| posockets | `~/Repos/Oberon/posockets`: README.md and `doc/` |
| pounix | `~/Repos/Oberon/pounix`: `doc/UnixFiles.md`, `doc/UnixProcesses.md` |
| poDateTime | `~/Repos/Oberon/poDateTime`: `Clocks`, `Instants`, `TimeStrings` |
| pogemini | `~/Repos/Oberon/pogemini`: `src/GemRequest.Mod`, `src/GemServer.Mod`, `test/` |
| poc | `/usr/bin/poc`; its source `~/Repos/Oberon/Peaseblossom` (`doc/users-guide.md`, section 12 for `Tasks`; `doc/reference-guide.md`; `rtl/llvm/Tasks.Mod`, `rtl/llvm/StopRequests.Mod`) |
| Oberon-2 report | `~/Reference/Computer/Languages/Oberon/Oberon2.pdf` |
| Clients and servers to test against | pogemini (installed, if there); `openssl s_client`; gemget (`~/go/bin/gemget`); `gnutls-cli`; OpenBSD's `nc` as `/usr/bin/netcat`. polibtls's `test/TestGemini.Mod` shows how to drive each |

## Build

To be written in Phase 0, after pounix's `GNUmakefile`: the library
`pogeminilib` built from `src/` into `build/lib` with `-library`, in
`-OC` (and `-OC -g`), the only size model its dependencies are
installed in; the tests built against that build, never an installed
copy; `make deps` checking that polibtls, posockets, poDateTime and
pounix are installed in `POCLIBDIR` (`~/.local/lib/poc`) and
were built by the poc in use; `make install` by `poc -install-library`;
`.NOTPARALLEL`, since poc writes every module's files into one
`build/`; `POC_LIBRARY_PATH` unexported. **A poc library works only
with the poc that built it**: after a poc upgrade, reinstall the
dependencies (poDateTime before polibtls and posockets) and rebuild.

## Test

As its siblings (PLAN.md, "Testing"): one main module per concern in
`test/`, run from `test/`, printing `ok   - `/`FAIL - ` through
`test/Check.Mod` and a summary; halt tests named in `HALTTESTS`; test
certificates made into `build/certs` by polibtls's `make-certs.sh`;
files a test needs made under `build/test-<name>`, afresh, and removed
at the end. Client tests use a test server in `test/` that misbehaves
on purpose. Nothing in `make test` reaches the network beyond the
loopback; real capsules are checked by hand.

Known from the siblings, to keep in mind from the first test:

- **A value `ARRAY OF CHAR` parameter is copied onto the callee's
  stack**, so passing a large response by value overruns a task's 64
  KiB stack (pogemini, Phase 1): test tasks that do get 1 MiB, and the
  library passes nothing large by value.
- **C a task calls must fit in its stack**, and libc may need far more
  than it seems (`gmtime_r` on NetBSD and OpenBSD; pogemini, Phase 7):
  use poDateTime for times, and suspect any libc call that loads
  something on first use.
- **Ignore `SIGPIPE`** (`Sockets.IgnoreBrokenPipe`) in any program that
  writes to a peer, or a peer that goes away kills it.
- **memcheck can't follow poc's coroutines**: check a program with
  tasks with `valgrind --tool=none --track-fds=yes`, allowing for the
  two descriptors `Tasks` keeps open (polibtls's README).

## Testing on the BSD hosts

As pogemini's and polibtls's AGENTS.md say, on the same hosts (alerik,
FreeBSD amd64; artos, NetBSD amd64; yishana, NetBSD i386; jherek,
OpenBSD amd64; cymoril, OpenBSD i386; not rackhir without asking).
Copy the working tree (`tar` less `build/` and `.git`) into a directory
under `~/tmp` there, with the dependencies from `git archive`s, each
installed in turn by `gmake install POCLIBDIR=<dir>` there and used by
`gmake test POCLIBDIR=<dir>`; remove it all when done. Judge a run by
make's exit status, and count `assertion failed` and core files as
well as `FAIL`.

## Conventions

As its siblings', in short:

- **Claim only what has been verified**: a throwaway program, run,
  before a comment or decision depends on how something behaves.
  Throwaway work goes in a session directory under `/usr/local/sw/tmp`
  (`/tmp` is a RAM disk here), removed when done.
- **Portable to the BSDs**: nothing Linux-only (`/proc`, `epoll`, GNU
  options of commands, Linux paths); what needs C goes in a shared
  po* library, changed there with its tests and reinstalled, not
  worked around here. The aim is no C in this library at all.
- **Outside data never halts**: a server's response, a page's gemtext,
  a known-hosts file, a network error all come back as `FALSE` and an
  error the program can read. Programmer errors halt, with codes
  120..129 (PLAN.md, "Halt codes").
- **Nothing large on a task's stack**: buffers on the heap, array
  parameters `VAR` or read-only (`-`).
- **Secrets**: never print, log or commit a key; test certificates are
  generated into `build/certs`.
- **Comments explain why.**
- **Record decisions and findings in PLAN.md as they happen**, mark
  finished phases `[done]`, strike through decided open questions.
- **Commit only when asked.** Commit messages are short and say why.
- **pogemini is another repository**: a change it needs (Phase 8) is
  made there, with its tests, and recorded in its PLAN.md, not here.
