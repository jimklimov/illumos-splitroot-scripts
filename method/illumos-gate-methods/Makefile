# Automate patch-file generation from working copy of the scripts

GDIFF = /usr/gnu/bin/diff

OLDPATCH = ../fs-root-zfs.patch
NEWPATCH = $(OLDPATCH).new
PATCHDESCR = $(OLDPATCH).hdr
PATCHDIFF= $(OLDPATCH).diff

FILES = fs-root fs-minimal fs-root-zfs fs-usr

VERBATIM = /usr/gnu/bin/echo -E
#VERBATIM = printf '%s\n'

all: newpatch-compare

newpatch-quiet: $(PATCHDIFF)
newpatch: newpatch-compare

clean:
	$(RM) -f $(PATCHDESCR) $(addsuffix .diff, $(FILES)) $(PATCHDIFF)

clobber: clean
	$(RM) -f $(NEWPATCH)

$(PATCHDESCR): $(OLDPATCH)
	@echo "  SHELL   Extracting header from old patch file"
	@IFS=''; export IFS; while read LINE; do case "$$LINE" in \
		"--- "*|"+++ "*|"diff -"*) exit 0 ;; \
		*) $(VERBATIM) "$$LINE" ;; \
	 esac; done < $< > $@

$(NEWPATCH): $(PATCHDESCR) $(addsuffix .diff, $(FILES))
	@echo "  CAT     $^ > $@"
	@cat $^ > $@
	@echo "=== You can now revise the new patch and replace the old one with it if ok"

$(PATCHDIFF): $(OLDPATCH) $(NEWPATCH)
	@echo "  DIFF    -bu $^ > $@"
	@$(GDIFF) -bu $^ > $@ || true

newpatch-compare: $(PATCHDIFF)
	@cat "$<"
	@echo "=== If all is ok, run : mv -f '$(NEWPATCH)' '$(OLDPATCH)'; git add '$(OLDPATCH)'; git commit -m 'Patchfile regenerated `date -u`'"
	@echo "Do not forget to zap not-our changes like cachefs/indentation in fs-usr"

# Two files needed, a symlink to original upstream script and
# and the working copy of modified script
%.diff: %.orig %
	@echo "  DIFF    -Naur $^"
	@$(GDIFF) -Naur $^ | sed -e 's,^\(---\) \(fs-.*\)$$,\1 /lib/svc/method/\2,' -e 's,^\(\+\+\+\) \(fs-.*\)$$,\1 /lib/svc/method/\2,' > $@ ; \
	 [ -s "$@" ]

.PHONY:
fs-root-zfs.orig: .PHONY
