/*
 * GDL2SchemaSyncTestBase.h
 *
 * Database-agnostic XCTest base class for schema synchronization integration tests.
 *
 * All test methods live here. Concrete subclasses only supply the adaptor
 * name and connection dictionary (read from environment variables).  Because
 * XCTest inherits test methods into subclasses, each concrete subclass
 * automatically runs the full suite against its own back-end.
 *
 * Connection configuration
 * ------------------------
 * SQLite  (GDL2SQLiteSchemaSyncTests):
 *   GDL2_TEST_SQLITE_PATH  – path to the SQLite database file.
 *                            If unset the tests are skipped.
 *
 * PostgreSQL (GDL2PostgreSQLSchemaSyncTests):
 *   GDL2_TEST_PG_HOST      – host name (default: localhost)
 *   GDL2_TEST_PG_PORT      – port     (default: 5432)
 *   GDL2_TEST_PG_DB        – database name  (required to enable tests)
 *   GDL2_TEST_PG_USER      – user name
 *   GDL2_TEST_PG_PASSWORD  – password
 */

#ifndef GDL2SchemaSyncTestBase_h
#define GDL2SchemaSyncTestBase_h

#import <XCTest/XCTest.h>
#import <EOAccess/EOAccess.h>
#import <EOAccess/EOJoin.h>
#import <EOAccess/EORelationship.h>
#import <EOAccess/EOSchemaGeneration.h>
#import <EOAccess/EOSchemaSynchronization.h>

@interface GDL2SchemaSyncTestBase : XCTestCase

/* ---- overridden by concrete subclasses ---- */

/** Returns the GDL2 adaptor name, e.g. @"SQLite3" or @"PostgreSQL". */
- (NSString *)adaptorName;

/**
 * Returns the connection dictionary for the adaptor, built from environment
 * variables.  Return nil to skip all tests in this class.
 */
- (NSDictionary *)connectionDictionary;

/** SQL type name for a generic integer column (default: @"INTEGER"). */
- (NSString *)integerTypeName;

/** SQL type name for a generic text column (default: @"TEXT"). */
- (NSString *)textTypeName;

/** SQL type name for a generic floating-point column (default: @"REAL"). */
- (NSString *)floatTypeName;

/**
 * Returns YES if this adaptor's describeModelWithTableNames: populates
 * relationships from the live FK constraints in the database.
 *
 * Defaults to NO.  Override to YES in adaptors that implement
 * -_describeForeignKeysForEntity:forModel: (currently PostgreSQL only;
 * SQLite's implementation is a no-op stub).
 */
- (BOOL)describesForeignKeyRelationships;

/* ---- shared state, configured in -setUp ---- */

@property (nonatomic, strong) EOAdaptor        *adaptor;
@property (nonatomic, strong) EOAdaptorContext *adaptorContext;
@property (nonatomic, strong) EOAdaptorChannel *channel;

@end

#endif /* GDL2SchemaSyncTestBase_h */
