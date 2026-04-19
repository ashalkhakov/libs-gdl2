/*
 * GDL2PostgreSQLSchemaSyncTests.m
 *
 * Runs the full GDL2SchemaSyncTestBase test suite against a PostgreSQL database.
 *
 * Configuration (environment variables):
 *   GDL2_TEST_PG_DB        – database name (required; if absent tests are skipped)
 *   GDL2_TEST_PG_HOST      – host name     (optional, default: localhost)
 *   GDL2_TEST_PG_PORT      – port number   (optional, default: 5432)
 *   GDL2_TEST_PG_USER      – user name     (optional)
 *   GDL2_TEST_PG_PASSWORD  – password      (optional)
 *
 * Example:
 *   export GDL2_TEST_PG_DB=gdl2_test
 *   export GDL2_TEST_PG_USER=myuser
 *   xctest GDL2SchemaSyncTests.bundle
 */

#import "GDL2SchemaSyncTestBase.h"
#import <Foundation/NSProcessInfo.h>

@interface GDL2PostgreSQLSchemaSyncTests : GDL2SchemaSyncTestBase
@end

@implementation GDL2PostgreSQLSchemaSyncTests

- (NSString *)adaptorName
{
    return @"PostgreSQL";
}

- (NSDictionary *)connectionDictionary
{
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *dbName = [env objectForKey:@"GDL2_TEST_PG_DB"];
    if (!dbName || [dbName length] == 0)
        return nil; /* skip tests */

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:dbName forKey:@"databaseName"];

    NSString *host = [env objectForKey:@"GDL2_TEST_PG_HOST"];
    if (host)
        [dict setObject:host forKey:@"hostName"];

    NSString *port = [env objectForKey:@"GDL2_TEST_PG_PORT"];
    if (port)
        [dict setObject:port forKey:@"port"];

    NSString *user = [env objectForKey:@"GDL2_TEST_PG_USER"];
    if (user)
        [dict setObject:user forKey:@"userName"];

    NSString *password = [env objectForKey:@"GDL2_TEST_PG_PASSWORD"];
    if (password)
        [dict setObject:password forKey:@"password"];

    return [NSDictionary dictionaryWithDictionary:dict];
}

/* Standard PostgreSQL type names */
- (NSString *)integerTypeName { return @"INTEGER"; }
- (NSString *)textTypeName    { return @"TEXT"; }
- (NSString *)floatTypeName   { return @"FLOAT8"; }

@end
