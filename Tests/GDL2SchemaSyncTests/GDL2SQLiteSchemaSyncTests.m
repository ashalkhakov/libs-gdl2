/*
 * GDL2SQLiteSchemaSyncTests.m
 *
 * Runs the full GDL2SchemaSyncTestBase test suite against a SQLite database.
 *
 * Configuration (environment variables):
 *   GDL2_TEST_SQLITE_PATH  – path to the SQLite file to use for testing.
 *                            If unset, all tests are skipped.
 *
 * Example:
 *   export GDL2_TEST_SQLITE_PATH=/tmp/gdl2_sync_test.sqlite
 *   xctest GDL2SchemaSyncTests.bundle
 */

#import "GDL2SchemaSyncTestBase.h"

@interface GDL2SQLiteSchemaSyncTests : GDL2SchemaSyncTestBase
@end

@implementation GDL2SQLiteSchemaSyncTests

- (NSString *)adaptorName
{
    return @"SQLite3";
}

- (NSDictionary *)connectionDictionary
{
    NSString *path = [[[NSProcessInfo processInfo] environment]
                      objectForKey:@"GDL2_TEST_SQLITE_PATH"];
    if (!path || [path length] == 0)
        return nil; /* skip tests */
    return @{ @"databasePath": path };
}

/* SQLite affinity types */
- (NSString *)integerTypeName { return @"INTEGER"; }
- (NSString *)textTypeName    { return @"TEXT"; }
- (NSString *)floatTypeName   { return @"REAL"; }

@end
