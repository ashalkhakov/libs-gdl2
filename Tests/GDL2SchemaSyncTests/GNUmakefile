include $(GNUSTEP_MAKEFILES)/common.make

# ── Bundle name ─────────────────────────────────────────────────────
BUNDLE_NAME = GDL2SchemaSyncTests

# ── Sources ─────────────────────────────────────────────────────────
GDL2SchemaSyncTests_OBJC_FILES = \
    GDL2SchemaSyncTestBase.m       \
    GDL2SQLiteSchemaSyncTests.m    \
    GDL2PostgreSQLSchemaSyncTests.m

# ── Headers search path (find <EOAccess/…> from the repo root) ──────
GDL2SchemaSyncTests_INCLUDE_DIRS = -I../..

# ── Libraries ───────────────────────────────────────────────────────
# EOAccess and EOControl are listed here so the bundle can be used both
# against an installed GDL2 and against a local development build.
GDL2SchemaSyncTests_LIBRARIES = objc gnustep-base XCTest EOAccess EOControl

# ── Test runner target ───────────────────────────────────────────────
XCTEST ?= xctest

.PHONY: check run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(XCTEST) $(BUNDLE_NAME).bundle

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble
