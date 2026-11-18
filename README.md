# pogeminilib - Gemini for poc

This software is developed with the aid of AI.

An Oberon-2 library for programs that speak the
[Gemini protocol](https://geminiprotocol.net/), for poc, the
[Peaseblossom](https://github.com/tkurtbond/peaseblossom) Oberon
compiler: URLs, requests and responses, a client connection in poc's
cooperative `Tasks` and a blocking one without them, trust on first
use, client certificates, and gemtext parsed and written; later, the
server engine of pogemini, a Gemini server, moved here.

**Status: begun.** Phases 0 and 1 of [PLAN.md](PLAN.md) are done:
`GeminiUrls` (URLs parsed, resolved, written, and checked as a server
must) and `GeminiPunycode` (internationalised host names); Phase 2,
gemtext, is next. Their reference is in [doc/](doc/). PLAN.md
has the design and the roadmap; [AGENTS.md](AGENTS.md) has the working
notes.

## Requirements

- poc 0.14.0.
- Installed in `~/.local/lib/poc` (or `POCLIBDIR=<dir>`), by the same
  poc: poDateTime, posockets, polibtls and pounix. `make deps` checks.
- Linux, FreeBSD, NetBSD or OpenBSD; GNU make, as `gmake` on the BSDs.
- valgrind, for `make valgrind` (Linux).

## Building

    make            # the library and the tests, under build/
    make test       # run the tests
    make valgrind   # the tests under valgrind
    make install    # into ~/.local/lib/poc (POCLIBDIR=<dir> to change)

A library works only with the poc that built it: after upgrading poc,
install poDateTime, then posockets, polibtls and pounix, then
pogeminilib again.

## License

BSD 3-clause; see [LICENSE](LICENSE).
