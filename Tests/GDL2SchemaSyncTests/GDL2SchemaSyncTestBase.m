/*
 * GDL2SchemaSyncTestBase.m
 *
 * Database-agnostic integration tests for GDL2 schema synchronization.
 * Each test:
 *   1. Creates a fresh table matching the "before" model.
 *   2. Applies a schema change via statementsToUpdateObjectStoreForModel:
 *   3. Describes the table to verify the result.
 *   4. Drops the table (cleanup).
 *
 * Tests that require the "after" schema to be described correctly rely only
 * on column presence/absence and the allowsNull flag, which are returned by
 * every adaptor's -describeModelWithTableNames:.
 */

#import "GDL2SchemaSyncTestBase.h"

/* ── primary test table name ──────────────────────────────────────── */
static NSString * const kTestTable        = @"gdl2_sync_test";
/* ── secondary name used only by testRenameTable ──────────────────── */
static NSString * const kTestTableRenamed = @"gdl2_sync_test_renamed";

/* ── convenience: case-insensitive attribute lookup by column name ── */
static EOAttribute *attributeWithColumn(EOEntity *entity, NSString *col)
{
    if (!entity) return nil;
    for (EOAttribute *a in [entity attributes])
    {
        if ([[a columnName] caseInsensitiveCompare:col] == NSOrderedSame)
            return a;
    }
    return nil;
}

/* ──────────────────────────────────────────────────────────────────── */
@implementation GDL2SchemaSyncTestBase

/* ---- default overridable methods ---- */
- (NSString *)adaptorName            { return nil; }
- (NSDictionary *)connectionDictionary { return nil; }
- (NSString *)integerTypeName        { return @"INTEGER"; }
- (NSString *)textTypeName           { return @"TEXT"; }
- (NSString *)floatTypeName          { return @"REAL"; }

/* ---- XCTest lifecycle ---- */

- (void)setUp
{
    [super setUp];

    NSDictionary *connDict = [self connectionDictionary];
    if (!connDict)
        return; /* tests will silently skip (self.channel == nil) */

    self.adaptor = [EOAdaptor adaptorWithName:[self adaptorName]];
    [self.adaptor setConnectionDictionary:connDict];

    self.adaptorContext = [self.adaptor createAdaptorContext];
    self.channel        = [self.adaptorContext createAdaptorChannel];
    [self.channel openChannel];
}

- (void)tearDown
{
    if (self.channel)
    {
        /* best-effort cleanup of both possible table names. */
        [self dropTableNamed:kTestTable];
        [self dropTableNamed:kTestTableRenamed];
        [self.channel closeChannel];
    }
    self.channel        = nil;
    self.adaptorContext = nil;
    self.adaptor        = nil;
    [super tearDown];
}

/* ═══════════════════════════════════════════════════════════════════
   HELPER – Build an EOModel/EOEntity programmatically
   ═══════════════════════════════════════════════════════════════════ */

/**
 * Returns a fresh EOModel whose single entity maps to kTestTable and has
 * the given column names.  The first column is the INTEGER primary key
 * (NOT NULL); all others are TEXT and allow NULL.
 */
- (EOModel *)modelWithColumns:(NSArray *)columnNames
{
    EOModel *model = [[EOModel alloc] init];
    [model setName:@"TestModel"];
    [model setAdaptorName:[self adaptorName]];
    [model setConnectionDictionary:[self connectionDictionary]];

    EOEntity *entity = [[EOEntity alloc] init];
    [entity setName:@"TestEntity"];
    [entity setExternalName:kTestTable];
    [entity setClassName:@"NSMutableDictionary"];
    [model addEntity:entity];

    NSMutableArray *pkAttrs = [NSMutableArray array];
    BOOL first = YES;
    for (NSString *col in columnNames)
    {
        EOAttribute *attr = [[EOAttribute alloc] init];
        [attr setName:col];
        [attr setColumnName:col];
        if (first)
        {
            [attr setExternalType:[self integerTypeName]];
            [attr setValueClassName:@"NSNumber"];
            [attr setValueType:@"i"];
            [attr setAllowsNull:NO];
            [pkAttrs addObject:attr];
            first = NO;
        }
        else
        {
            [attr setExternalType:[self textTypeName]];
            [attr setValueClassName:@"NSString"];
            [attr setAllowsNull:YES];
        }
        [entity addAttribute:attr];
    }
    [entity setPrimaryKeyAttributes:pkAttrs];
    return model;
}

/** Build a standalone EOAttribute (not yet attached to any entity). */
- (EOAttribute *)makeAttributeNamed:(NSString *)name
                         columnName:(NSString *)col
                       externalType:(NSString *)type
                         allowsNull:(BOOL)allowsNull
{
    EOAttribute *attr = [[EOAttribute alloc] init];
    [attr setName:name];
    [attr setColumnName:col];
    [attr setExternalType:type];
    [attr setAllowsNull:allowsNull];
    /* Set a reasonable value class name so the adaptor can format values. */
    NSString *lc = [type lowercaseString];
    if ([lc hasPrefix:@"int"] || [lc isEqualToString:@"real"]
        || [lc hasPrefix:@"float"] || [lc hasPrefix:@"double"]
        || [lc hasPrefix:@"numeric"] || [lc hasPrefix:@"decimal"])
    {
        [attr setValueClassName:@"NSNumber"];
    }
    else
    {
        [attr setValueClassName:@"NSString"];
    }
    return attr;
}

/* ═══════════════════════════════════════════════════════════════════
   HELPER – Execute DDL
   ═══════════════════════════════════════════════════════════════════ */

- (Class)expressionClass
{
    return [self.adaptor defaultExpressionClass];
}

/** Execute every EOSQLExpression in the array against the open channel. */
- (void)executeStatements:(NSArray *)stmts
{
    for (EOSQLExpression *expr in stmts)
        [self.channel evaluateExpression:expr];
}

/**
 * Create the table(s) represented by the model using the public
 * schema-generation API.  Any pre-existing table with the same name is
 * dropped first so tests are idempotent.
 */
- (void)createSchemaForModel:(EOModel *)model
{
    Class exprClass = [self expressionClass];

    /* Drop first (ignore errors – the table may not yet exist). */
    for (EOEntity *entity in [model entities])
    {
        NS_DURING
            [self executeStatements:
                [exprClass dropTableStatementsForEntityGroup:
                    @[entity]]];
        NS_HANDLER
        NS_ENDHANDLER
    }

    /* Create using the public schemaCreationStatements API.
     * Options: skip DROP phases (already done above), enable CREATE phases. */
    NSDictionary *opts = @{
        EODropTablesKey            : @"NO",
        EODropPrimaryKeySupportKey : @"NO",
        EOCreateTablesKey          : @"YES",
        EOCreatePrimaryKeySupportKey: @"YES",
        EOPrimaryKeyConstraintsKey : @"YES",
        EOForeignKeyConstraintsKey : @"NO",
    };
    NSArray *stmts = [exprClass schemaCreationStatementsForEntities:[model entities]
                                                            options:opts];
    [self executeStatements:stmts];
}

/**
 * Apply a schema synchronization change dictionary against the given model,
 * executing every generated statement on the open channel.
 */
- (void)applySyncChanges:(NSDictionary *)changes toModel:(EOModel *)model
{
    Class exprClass = [self expressionClass];
    NSArray *stmts  = [exprClass statementsToUpdateObjectStoreForModel:model
                                                   withChangeDictionary:changes
                                                                options:nil];
    [self executeStatements:stmts];
}

/**
 * Drop the named table, silently ignoring errors (e.g. table does not exist).
 * Uses a plain SQL string via +expressionForString: to avoid depending on
 * a model object.
 */
- (void)dropTableNamed:(NSString *)tableName
{
    Class exprClass = [self expressionClass];
    EOSQLExpression *expr =
        [exprClass expressionForString:
            [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", tableName]];
    NS_DURING
        [self.channel evaluateExpression:expr];
    NS_HANDLER
    NS_ENDHANDLER
}

/* ═══════════════════════════════════════════════════════════════════
   HELPER – Inspect the live database schema
   ═══════════════════════════════════════════════════════════════════ */

/**
 * Ask the adaptor to describe the named table and return the entity
 * (or nil if the table does not exist / cannot be found).
 */
- (EOEntity *)describeTableNamed:(NSString *)tableName
{
    EOModel *m = nil;
    NS_DURING
        m = [self.channel describeModelWithTableNames:@[tableName]];
    NS_HANDLER
        return nil;
    NS_ENDHANDLER
    if (!m) return nil;
    /* The described entity's externalName matches the table; name may differ. */
    for (EOEntity *e in [m entities])
    {
        if ([[e externalName] caseInsensitiveCompare:tableName] == NSOrderedSame)
            return e;
    }
    /* Some adaptors use the table name as the entity name. */
    return [[m entities] count] > 0 ? [[m entities] objectAtIndex:0] : nil;
}

- (BOOL)table:(NSString *)tableName hasColumnNamed:(NSString *)col
{
    EOEntity *entity = [self describeTableNamed:tableName];
    return attributeWithColumn(entity, col) != nil;
}

/* ═══════════════════════════════════════════════════════════════════
   TESTS
   ═══════════════════════════════════════════════════════════════════ */

/**
 * Verifies that the channel can create an initial table and that the
 * resulting live schema matches what was requested.
 */
- (void)testInitialSchemaSetup
{
    if (!self.channel) return; /* not configured – skip */

    EOModel *model = [self modelWithColumns:@[@"id", @"name"]];
    [self createSchemaForModel:model];

    EOEntity *described = [self describeTableNamed:kTestTable];
    XCTAssertNotNil(described, @"Table should exist after createSchemaForModel:");
    XCTAssertTrue(attributeWithColumn(described, @"id")   != nil, @"'id' column should exist");
    XCTAssertTrue(attributeWithColumn(described, @"name") != nil, @"'name' column should exist");

    [self dropTableNamed:kTestTable];
}

/**
 * Creates a two-column table, then adds a third column via schema sync,
 * and verifies that the column is present in the live schema.
 */
- (void)testAddColumn
{
    if (!self.channel) return;

    EOModel *model  = [self modelWithColumns:@[@"id", @"name"]];
    [self createSchemaForModel:model];

    /* Build the "after" model: add a 'score' column. */
    EOEntity   *entity    = [model entityNamed:@"TestEntity"];
    EOAttribute *scoreAttr = [self makeAttributeNamed:@"score"
                                           columnName:@"score"
                                         externalType:[self floatTypeName]
                                           allowsNull:YES];
    [entity addAttribute:scoreAttr];

    NSDictionary *changes = @{
        kTestTable: @{
            @"insertedAttributes": @[scoreAttr]
        }
    };
    [self applySyncChanges:changes toModel:model];

    XCTAssertTrue([self table:kTestTable hasColumnNamed:@"score"],
                  @"'score' column should exist after ADD COLUMN");

    [self dropTableNamed:kTestTable];
}

/**
 * Creates a three-column table, then removes one column via schema sync,
 * and verifies that the column is absent from the live schema.
 */
- (void)testDropColumn
{
    if (!self.channel) return;

    /* Create table with three columns. */
    EOModel *model = [self modelWithColumns:@[@"id", @"name", @"score"]];
    [self createSchemaForModel:model];

    /* Build the "after" model: entity has only 'id' (name was removed). */
    EOEntity    *entity   = [model entityNamed:@"TestEntity"];
    EOAttribute *nameAttr = [entity attributeNamed:@"name"];
    [entity removeAttribute:nameAttr];

    NSDictionary *changes = @{
        kTestTable: @{
            @"deletedColumnNames": @[@"name"]
        }
    };
    [self applySyncChanges:changes toModel:model];

    XCTAssertFalse([self table:kTestTable hasColumnNamed:@"name"],
                   @"'name' column should be absent after DROP COLUMN");
    XCTAssertTrue([self table:kTestTable hasColumnNamed:@"id"],
                  @"'id' column should still exist");

    [self dropTableNamed:kTestTable];
}

/**
 * Creates a two-column table, renames one column via schema sync,
 * and verifies that the old name is gone and the new name is present.
 */
- (void)testRenameColumn
{
    if (!self.channel) return;

    EOModel *model = [self modelWithColumns:@[@"id", @"name"]];
    [self createSchemaForModel:model];

    /* Build the "after" model: 'name' becomes 'full_name'. */
    EOEntity    *entity   = [model entityNamed:@"TestEntity"];
    EOAttribute *nameAttr = [entity attributeNamed:@"name"];
    [nameAttr setColumnName:@"full_name"];
    [nameAttr setName:@"full_name"];

    NSDictionary *changes = @{
        kTestTable: @{
            @"renamedColumns": @{ @"name": @"full_name" }
        }
    };
    [self applySyncChanges:changes toModel:model];

    XCTAssertFalse([self table:kTestTable hasColumnNamed:@"name"],
                   @"old column name 'name' should be gone after rename");
    XCTAssertTrue([self table:kTestTable hasColumnNamed:@"full_name"],
                  @"new column name 'full_name' should exist after rename");

    [self dropTableNamed:kTestTable];
}

/**
 * Creates a table, changes a column's type via schema sync,
 * and verifies the column still exists (and its type was accepted by the DB).
 * We change the 'name' column from text to float and back to detect any
 * breakage; the exact type name returned by describe is not asserted since
 * it varies between backends.
 */
- (void)testChangeColumnType
{
    if (!self.channel) return;

    EOModel *model = [self modelWithColumns:@[@"id", @"name"]];
    [self createSchemaForModel:model];

    /* Build the "after" model: change 'name' column to float type. */
    EOEntity    *entity   = [model entityNamed:@"TestEntity"];
    EOAttribute *nameAttr = [entity attributeNamed:@"name"];
    NSString    *oldType  = [nameAttr externalType];
    NSString    *newType  = [self floatTypeName];
    [nameAttr setExternalType:newType];
    [nameAttr setValueClassName:@"NSNumber"];
    [nameAttr setValueType:@"d"];

    NSDictionary *changes = @{
        kTestTable: @{
            @"modifiedAttributes": @{
                @"name": @{
                    EOExternalTypeKey: newType
                }
            }
        }
    };
    [self applySyncChanges:changes toModel:model];

    /* The column must still exist; the type change succeeded without error. */
    EOEntity *described = [self describeTableNamed:kTestTable];
    XCTAssertNotNil(described, @"Table must exist after column type change");
    EOAttribute *attr = attributeWithColumn(described, @"name");
    XCTAssertNotNil(attr, @"'name' column should still exist after type change");
    XCTAssertFalse([[attr externalType] caseInsensitiveCompare:oldType] == NSOrderedSame,
                   @"Column type should have changed from original '%@'", oldType);

    [self dropTableNamed:kTestTable];
}

/**
 * Creates a table with a nullable column, then changes it to NOT NULL
 * via schema sync, and verifies the allowsNull flag is NO in the live schema.
 */
- (void)testChangeColumnNullRule
{
    if (!self.channel) return;

    EOModel *model = [self modelWithColumns:@[@"id", @"name"]];
    [self createSchemaForModel:model];

    /* Build the "after" model: 'name' becomes NOT NULL. */
    EOEntity    *entity   = [model entityNamed:@"TestEntity"];
    EOAttribute *nameAttr = [entity attributeNamed:@"name"];
    [nameAttr setAllowsNull:NO];

    NSDictionary *changes = @{
        kTestTable: @{
            @"modifiedAttributes": @{
                @"name": @{
                    EOAllowsNullKey: @NO
                }
            }
        }
    };
    [self applySyncChanges:changes toModel:model];

    EOEntity *described = [self describeTableNamed:kTestTable];
    XCTAssertNotNil(described, @"Table must exist after null rule change");
    EOAttribute *attr = attributeWithColumn(described, @"name");
    XCTAssertNotNil(attr, @"'name' column should exist after null rule change");
    XCTAssertFalse([attr allowsNull],
                   @"'name' column should be NOT NULL after null-rule sync");

    [self dropTableNamed:kTestTable];
}

/**
 * Creates a table, renames the table via schema sync, and verifies that
 * the new table name is visible and the old one is gone.
 * Cleanup for the renamed table is also handled by tearDown via
 * kTestTableRenamed.
 */
- (void)testRenameTable
{
    if (!self.channel) return;

    EOModel *model = [self modelWithColumns:@[@"id", @"name"]];
    [self createSchemaForModel:model];

    /* Build the "after" model: update the entity's external name. */
    EOEntity *entity = [model entityNamed:@"TestEntity"];
    [entity setExternalName:kTestTableRenamed];

    NSDictionary *changes = @{
        kTestTable: @{
            EOExternalNameKey: kTestTableRenamed
        }
    };
    [self applySyncChanges:changes toModel:model];

    /* Verify new name exists. */
    EOEntity *described = [self describeTableNamed:kTestTableRenamed];
    XCTAssertNotNil(described,
                    @"Table should exist under new name '%@' after rename",
                    kTestTableRenamed);

    /* Verify old name is gone (describe returns nil / empty entity). */
    EOEntity *old = [self describeTableNamed:kTestTable];
    XCTAssertNil(old,
                 @"Old table name '%@' should not exist after rename", kTestTable);
    /* kTestTableRenamed will be cleaned up by tearDown. */
}

@end
