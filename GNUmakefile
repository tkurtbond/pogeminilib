# pogeminilib -- a Gemini library for poc, the Peaseblossom Oberon
# Compiler. See AGENTS.md; adapted from pounix's GNUmakefile, with
# pogemini's deps check.
#
# The library pogeminilib is built in $(LIBDIR) from src/. It is Oberon
# only (PLAN.md, "Portability": no C here), so neither it nor a program
# using it passes flags beyond the libraries it imports. The tests take
# the library from there, so they test this checkout and what make
# install would install.
#
# Its dependencies (DEPLIBS) are taken installed, from $(POCLIBDIR), and
# must have been built by the poc in use, since poc refuses a library
# another poc built: make deps checks, and everything that builds
# depends on it.
#
# poc writes each module's .sym, .ll and .o, and the programs, into $(BUILD).
# Every program writes the files of the modules it compiles into the same
# $(BUILD), so make must not build two at once.
#
# make install installs the library in $(POCLIBDIR), ~/.local/lib/poc by
# default, with and without debug information, under -OC, the only size
# model its dependencies are installed in. poc puts each in
# <triple>/<variant>/ there.

POC      ?= poc
PREFIX ?= $(HOME)/.local
POCLIBDIR ?= $(PREFIX)/lib/poc
# The size model: its dependencies' (PLAN.md, "Integer model and
# memory"); never mix models.
POCFLAGS := -OC
MODELS := OC
VARIANTS := $(MODELS) $(addsuffix -g,$(MODELS))
# --track-fds=yes makes valgrind list the descriptors open at exit; the
# valgrind target requires that the test opened none of them.
VALGRIND ?= valgrind --leak-check=full --show-leak-kinds=all --track-fds=yes --error-exitcode=99 --suppressions=poc-gc.supp

# An installed library on POC_LIBRARY_PATH would be taken in place of this
# checkout's source, or would stop the build if another poc wrote it.
unexport POC_LIBRARY_PATH

BUILD := build
LIBDIR := $(BUILD)/lib

LIBRARY := pogeminilib
# The library's modules, in import order (PLAN.md, "Library and module
# names"). None yet: each phase adds its own.
LIBMODS :=
# The installed libraries it needs (PLAN.md, "Foundations").
DEPLIBS := podatetime posockets polibtls pounix

# $(call variant-flags,<variant>) gives poc's flags for a variant: OC-g gives
# -OC -g.
variant-flags = -$(firstword $(subst -, ,$(1))) $(if $(filter %-g,$(1)),-g)

# A library records the poc that built it, and another poc refuses it, so
# each library depends on poc itself.
POCBIN := $(shell command -v $(POC))
# poc's version and target, as a library's manifest records them.
POCVERSION := $(shell $(POC) -version | sed -n '1s/^poc \([^ ]*\).*/\1/p')
TRIPLE := $(shell $(POC) -version | sed -n 's/^target \([^ ]*\).*/\1/p')
# Where a program finds pogeminilib and what it needs: this checkout's
# library first, so an installed pogeminilib is never taken in its place.
LIBPATH := -library-path $(LIBDIR) -library-path $(POCLIBDIR)

# The modules' sources, and the library's stamp: none until there is a
# module, and then the tests depend on it.
LIBSRC := $(LIBMODS:%=src/%.Mod)
LIBSTAMP := $(if $(LIBMODS),$(LIBDIR)/$(LIBRARY)-OC.stamp)
# Test programs (test/<name>.Mod, each a main module), run from test/.
TESTS := TestCheck
# Programs that must halt (test/<name>.Mod), as name:Assert-code. poc's
# ASSERT(x, n) prints "assertion failed (n)" on standard error and exits
# with status 10, so `make test` requires both. Codes 120..129 are this
# library's (PLAN.md, "Halt codes").
HALTTESTS :=
ASSERTSTATUS := 10

TESTBINS := $(TESTS:%=$(BUILD)/%)
HALTBINS := $(foreach h,$(HALTTESTS),$(BUILD)/$(firstword $(subst :, ,$(h))))

.PHONY: all deps tests test valgrind clean install uninstall doc
.NOTPARALLEL:

all: deps tests

tests: $(TESTBINS) $(HALTBINS)

# Each library in DEPLIBS must be installed in $(POCLIBDIR), by this poc.
deps:
	@status=0; for l in $(DEPLIBS); do \
	  m=$(POCLIBDIR)/$(TRIPLE)/OC/$$l.library; \
	  if [ ! -f $$m ]; then echo "deps: $$l is not installed in $(POCLIBDIR)"; status=1; \
	  elif ! grep -qx 'poc $(POCVERSION)' $$m; then \
	    echo "deps: $$l in $(POCLIBDIR) was built by $$(sed -n 's/^poc //p' $$m), not poc $(POCVERSION): reinstall it"; status=1; \
	  else echo "deps: $$l ok"; fi; \
	done; exit $$status

$(BUILD):
	mkdir -p $@

$(LIBDIR)/$(LIBRARY)-%.stamp: $(LIBSRC) $(POCBIN) | deps $(BUILD)
	mkdir -p $(LIBDIR)
	cd src && $(POC) $(call variant-flags,$*) -output-dir $(abspath $(LIBDIR)) \
	  -library-path $(abspath $(POCLIBDIR)) -library $(LIBRARY) $(LIBMODS:%=%.Mod)
	touch $@

$(TESTBINS): $(BUILD)/%: test/%.Mod test/Check.Mod $(LIBSTAMP) | deps $(BUILD)
	$(POC) $(POCFLAGS) $(LIBPATH) -import-path test -output-dir $(BUILD) -o $@ $<

$(BUILD)/Halt%: test/Halt%.Mod $(LIBSTAMP) | deps $(BUILD)
	$(POC) $(POCFLAGS) $(LIBPATH) -output-dir $(BUILD) -o $@ $<

# Run every test from test/; report all, fail at the end if any failed.
# Each halt test must exit with poc's ASSERT status and name its Assert
# code on standard error. Standard input is /dev/null. A test makes its
# files under build/test-<name>, afresh, and removes them at its end.
test: all
	@status=0; for t in $(TESTS); do \
	  echo "== $$t"; (cd test && ../$(BUILD)/$$t < /dev/null) || status=1; \
	done; \
	for h in $(HALTTESTS); do \
	  t=$${h%%:*}; code=$${h##*:}; echo "== $$t (must fail ASSERT code $$code)"; \
	  (cd test && ../$(BUILD)/$$t < /dev/null) 2> $(BUILD)/$$t.err; got=$$?; \
	  if [ $$got -eq $(ASSERTSTATUS) ] && grep -q "assertion failed ($$code)" $(BUILD)/$$t.err; then \
	    echo "ok   - $$t: $$(cat $(BUILD)/$$t.err)"; \
	  else echo "FAIL - $$t exited with $$got: $$(cat $(BUILD)/$$t.err)"; status=1; fi; \
	done; exit $$status

# Each test under valgrind. Besides definite and indirect leaks, every
# still-reachable block must be the collector's own (test/vg-reachable.sh),
# and every descriptor open at exit must be one the test inherited
# (test/vg-fds.sh, from valgrind's --track-fds=yes report). A test with
# tasks needs --tool=none instead (AGENTS.md, "Test"): added with the
# first one, in Phase 4.
valgrind: all
	@status=0; for t in $(TESTS); do \
	  echo "== valgrind $$t"; \
	  (cd test && $(VALGRIND) --log-file=../$(BUILD)/$$t.vg ../$(BUILD)/$$t < /dev/null) || status=1; \
	  grep -E 'ERROR SUMMARY|lost:|reachable:|FILE DESCRIPTORS' $(BUILD)/$$t.vg; \
	  test/vg-reachable.sh $(BUILD)/$$t.vg || { echo "FAIL - $$t: still-reachable memory the collector did not allocate"; status=1; }; \
	  test/vg-fds.sh $(BUILD)/$$t.vg || { echo "FAIL - $$t: descriptors left open at exit (see $(BUILD)/$$t.vg)"; status=1; }; \
	done; exit $$status

# install copies the library, in each variant, into $(POCLIBDIR) with poc
# -install-library, which copies only what a program needs: the archive,
# the shared object, the manifest, and each module's .sym and .owner. A
# program then finds it with -library-path $(POCLIBDIR). A library
# records the poc that built it, and another poc refuses it: install
# again after upgrading poc (and its dependencies first).
define newline


endef

ifeq ($(LIBMODS),)
install:
	@echo "install: the library has no modules yet"; exit 1
else
install: $(foreach v,$(VARIANTS),$(LIBDIR)/$(LIBRARY)-$(v).stamp)
	$(foreach v,$(VARIANTS),$(POC) $(call variant-flags,$(v)) \
	  $(LIBPATH) -install-library $(LIBRARY) -output-dir $(POCLIBDIR)$(newline))
endif

# uninstall removes from $(POCLIBDIR)/<triple>/<variant> what install put
# there. It leaves other libraries' files alone, and removes a directory only
# when nothing is left in it. The triple is poc's target.
INSTALLED_FILES := $(LIBRARY).library lib$(LIBRARY).a lib$(LIBRARY).so lib$(LIBRARY).so.0.0 \
  $(foreach m,$(LIBMODS),$(m).sym $(m).owner)

uninstall:
	@triple=$$($(POC) -version | sed -n 's/^target \([^ ]*\).*/\1/p'); \
	if [ -z "$$triple" ]; then echo "uninstall: cannot get the target from $(POC) -version" >&2; exit 1; fi; \
	for v in $(VARIANTS); do \
	  dir=$(POCLIBDIR)/$$triple/$$v; \
	  if [ -d "$$dir" ]; then \
	    echo "cd $$dir && rm -f $(INSTALLED_FILES)"; \
	    (cd "$$dir" && rm -f $(INSTALLED_FILES)) || exit 1; \
	    rmdir "$$dir" 2>/dev/null || :; \
	  fi; \
	done; \
	rmdir $(POCLIBDIR)/$$triple 2>/dev/null || :; \
	rmdir $(POCLIBDIR) 2>/dev/null || :

# The reference in doc/, from each module's exported declarations and
# their comments (doc/mkref.py, from pounix). Its output is committed,
# so a reader needs no build.
DOCS := $(patsubst %,doc/%.md,$(LIBMODS))

doc: $(DOCS)

doc/%.md: src/%.Mod doc/mkref.py
	python3 doc/mkref.py $< > $@

clean:
	rm -rf $(BUILD)
