# GDL2 Schema Synchronization Integration Tests

This directory contains XCTest integration tests for GDL2's schema
synchronization and initial schema setup APIs.

## Design

The test suite is **database-agnostic**: all test logic lives in
`GDL2SchemaSyncTestBase`.  Concrete subclasses (`GDL2SQLiteSchemaSyncTests`
and `GDL2PostgreSQLSchemaSyncTests`) only supply an adaptor name and a
connection dictionary read from environment variables.  Because XCTest
propagates test methods to subclasses, the complete suite runs against every
configured backend automatically.

Each test:
1. Creates a fresh table using the standard `schemaCreationStatements` API.
2. Applies one type of schema change via `statementsToUpdateObjectStoreForModel:`.
3. Calls `describeModelWithTableNames:` to inspect the live schema.
4. Asserts the expected structural outcome (column presence/absence, null rule).
5. Drops the table.

Tests check **results only** — not the internal SQL or whether SQLite used a
table-rebuild vs. ALTER TABLE.

## Tests covered

### Column-level schema changes

| Test method               | Change type                                  |
|---------------------------|----------------------------------------------|
| `testInitialSchemaSetup`  | Create table; verify columns exist           |
| `testAddColumn`           | Add a column                                 |
| `testDropColumn`          | Drop a column                                |
| `testRenameColumn`        | Rename a column                              |
| `testChangeColumnType`    | Change a column's external type              |
| `testChangeColumnNullRule`| Change a column from `NULL` to `NOT NULL`    |
| `testRenameTable`         | Rename the table                             |

### Relationship-level schema changes

Relationships are represented at the DB level as FK columns (and, on adaptors
that support it, FK constraints).  Tests verify the observable result in the
live schema (column presence/absence, `allowsNull` flag, and — where supported
— the presence of described FK relationships).

| Test method                             | Change type                                                   |
|-----------------------------------------|---------------------------------------------------------------|
| `testInitialSchemaSetupWithToOneRelationship` | Create two tables with FK column; verify FK column exists; on PostgreSQL verify FK relationship is described back |
| `testAddToOneRelationship`              | Add FK column to child table (= new to-one)                   |
| `testDropToOneRelationship`             | Drop FK column from child table (= drop to-one)               |
| `testToOneRelationshipMandatory`        | Make FK column NOT NULL (= `isMandatory = YES`)               |
| `testAddToManyRelationship`             | Add FK column on the many-side (= new to-many from parent's view) |

**Notes on to-many relationships**: A to-many relationship has no DB schema of
its own — the FK lives on the "many" side (child) table.  `testAddToManyRelationship`
verifies the FK backing column is created on the child table, which is the
observable DB effect of adding a to-many.

**Notes on multiplicity (isToMany) changes**: Changing `isToMany` is a model
metadata change with no DB-visible effect.  These are not tested.

**Notes on FK constraint inspection**: `describesForeignKeyRelationships`
defaults to `NO`.  It is overridden to `YES` in `GDL2PostgreSQLSchemaSyncTests`
because PostgreSQL's `_describeForeignKeysForEntity:forModel:` is fully
implemented.  SQLite's equivalent is currently a no-op stub, so FK-constraint
assertions are skipped for that backend.

## Building

Prerequisites: GNUstep (with `GNUSTEP_MAKEFILES` set), `tools-xctest`
installed, and GDL2 built or installed.

```sh
# From this directory
. $GNUSTEP_MAKEFILES/GNUstep.sh
make
```

Or from the repo root:

```sh
cd Tests/GDL2SchemaSyncTests
make
```

## Running

### SQLite

```sh
export GDL2_TEST_SQLITE_PATH=/tmp/gdl2_sync_test.sqlite
xctest GDL2SchemaSyncTests.bundle
```

### PostgreSQL

```sh
export GDL2_TEST_PG_DB=my_test_database
export GDL2_TEST_PG_HOST=localhost      # optional, default: localhost
export GDL2_TEST_PG_PORT=5432           # optional, default: 5432
export GDL2_TEST_PG_USER=myuser         # optional
export GDL2_TEST_PG_PASSWORD=secret     # optional
xctest GDL2SchemaSyncTests.bundle
```

If an environment variable required for a backend is absent, the tests for
that backend are silently skipped (the test method returns immediately).

### Running both backends in one command

```sh
export GDL2_TEST_SQLITE_PATH=/tmp/gdl2_sync_test.sqlite
export GDL2_TEST_PG_DB=my_test_database
make run-tests
```

## Note on the test table

All tests use a table named `gdl2_sync_test` (and `gdl2_sync_test_renamed`
for the rename test).  The `setUp` / `tearDown` methods ensure these tables
are cleaned up even if a test fails.  Do **not** run the tests against a
production database that contains tables with these names.
