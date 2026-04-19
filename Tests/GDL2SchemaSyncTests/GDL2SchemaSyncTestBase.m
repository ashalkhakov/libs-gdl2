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
/* ── two-table names used by relationship tests ───────────────────── */
static NSString * const kParentTable      = @"gdl2_sync_parent";
static NSString * const kChildTable       = @"gdl2_sync_child";

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
- (BOOL)describesForeignKeyRelationships { return NO; }

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
        /* best-effort cleanup of all possible table names. */
        /* Child must be dropped before parent (FK constraint). */
        [self dropTableNamed:kChildTable];
        [self dropTableNamed:kParentTable];
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

    /* Build the "after" model: 'name' becomes 'full_name'.
     * EOAttribute has two identifiers: 'name' (the ObjC property name used by
     * EOModel/EOEntity APIs) and 'columnName' (the SQL column name used in DDL).
     * Both must be updated so that EOEntity can find the attribute by its new
     * name and so the schema-sync SQL is generated with the correct column. */
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

/* ═══════════════════════════════════════════════════════════════════
   RELATIONSHIP HELPER
   ═══════════════════════════════════════════════════════════════════ */

/**
 * Build a two-entity EOModel that represents a parent→child relationship:
 *
 *   gdl2_sync_parent(parent_id INTEGER PK, name TEXT)
 *   gdl2_sync_child (child_id INTEGER PK, parent_id INTEGER, label TEXT)
 *
 * The child entity has a to-one relationship "toParent" joining
 * child.parent_id → parent.parent_id.
 * The parent entity has the inverse to-many relationship "toChildren".
 *
 * The FK column on the child is nullable by default (isMandatory = NO).
 */
- (EOModel *)makeParentChildModel
{
    EOModel *model = [[EOModel alloc] init];
    [model setName:@"RelTestModel"];
    [model setAdaptorName:[self adaptorName]];
    [model setConnectionDictionary:[self connectionDictionary]];

    /* ── parent entity ───────────────────────────────────────────── */
    EOEntity *parent = [[EOEntity alloc] init];
    [parent setName:@"Parent"];
    [parent setExternalName:kParentTable];
    [parent setClassName:@"NSMutableDictionary"];
    [model addEntity:parent];

    EOAttribute *parentPK = [[EOAttribute alloc] init];
    [parentPK setName:@"parent_id"];
    [parentPK setColumnName:@"parent_id"];
    [parentPK setExternalType:[self integerTypeName]];
    [parentPK setValueClassName:@"NSNumber"];
    [parentPK setValueType:@"i"];
    [parentPK setAllowsNull:NO];
    [parent addAttribute:parentPK];
    [parent setPrimaryKeyAttributes:@[parentPK]];

    EOAttribute *parentName = [[EOAttribute alloc] init];
    [parentName setName:@"name"];
    [parentName setColumnName:@"name"];
    [parentName setExternalType:[self textTypeName]];
    [parentName setValueClassName:@"NSString"];
    [parentName setAllowsNull:YES];
    [parent addAttribute:parentName];

    /* ── child entity ────────────────────────────────────────────── */
    EOEntity *child = [[EOEntity alloc] init];
    [child setName:@"Child"];
    [child setExternalName:kChildTable];
    [child setClassName:@"NSMutableDictionary"];
    [model addEntity:child];

    EOAttribute *childPK = [[EOAttribute alloc] init];
    [childPK setName:@"child_id"];
    [childPK setColumnName:@"child_id"];
    [childPK setExternalType:[self integerTypeName]];
    [childPK setValueClassName:@"NSNumber"];
    [childPK setValueType:@"i"];
    [childPK setAllowsNull:NO];
    [child addAttribute:childPK];
    [child setPrimaryKeyAttributes:@[childPK]];

    EOAttribute *fkAttr = [[EOAttribute alloc] init];
    [fkAttr setName:@"parent_id"];
    [fkAttr setColumnName:@"parent_id"];
    [fkAttr setExternalType:[self integerTypeName]];
    [fkAttr setValueClassName:@"NSNumber"];
    [fkAttr setValueType:@"i"];
    [fkAttr setAllowsNull:YES]; /* nullable = not mandatory */
    [child addAttribute:fkAttr];

    EOAttribute *label = [[EOAttribute alloc] init];
    [label setName:@"label"];
    [label setColumnName:@"label"];
    [label setExternalType:[self textTypeName]];
    [label setValueClassName:@"NSString"];
    [label setAllowsNull:YES];
    [child addAttribute:label];

    /* ── to-one relationship: Child → Parent ─────────────────────── */
    EORelationship *toParent = [[EORelationship alloc] init];
    [toParent setName:@"toParent"];
    [toParent setEntity:child];
    [toParent setToMany:NO];
    [toParent setIsMandatory:NO];
    EOJoin *join = [EOJoin joinWithSourceAttribute:fkAttr
                              destinationAttribute:parentPK];
    [toParent addJoin:join];
    [child addRelationship:toParent];

    /* ── to-many relationship: Parent → Child ────────────────────── */
    EORelationship *toChildren = [[EORelationship alloc] init];
    [toChildren setName:@"toChildren"];
    [toChildren setEntity:parent];
    [toChildren setToMany:YES];
    [toChildren setIsMandatory:NO];
    EOJoin *inverseJoin = [EOJoin joinWithSourceAttribute:parentPK
                                     destinationAttribute:fkAttr];
    [toChildren addJoin:inverseJoin];
    [parent addRelationship:toChildren];

    return model;
}

/* ═══════════════════════════════════════════════════════════════════
   RELATIONSHIP TESTS
   ═══════════════════════════════════════════════════════════════════ */

/**
 * Creates a parent and child table connected by a FK column (to-one relationship).
 * Verifies:
 *   – Both tables exist with their respective columns.
 *   – The FK column is present on the child table.
 *   – On adaptors that describe FK constraints, the to-one relationship is
 *     reflected back from the live schema.
 */
- (void)testInitialSchemaSetupWithToOneRelationship
{
    if (!self.channel) return;

    EOModel *model = [self makeParentChildModel];
    [self createSchemaForModel:model];

    /* Both tables must exist. */
    XCTAssertNotNil([self describeTableNamed:kParentTable],
                    @"Parent table should exist after schema setup");
    XCTAssertNotNil([self describeTableNamed:kChildTable],
                    @"Child table should exist after schema setup");

    /* FK column must be on the child. */
    XCTAssertTrue([self table:kChildTable hasColumnNamed:@"parent_id"],
                  @"FK column 'parent_id' should exist on child table");

    /* On adaptors that describe FK constraints, the relationship appears. */
    if ([self describesForeignKeyRelationships])
    {
        EOEntity *describedChild = [self describeTableNamed:kChildTable];
        XCTAssertTrue([[describedChild relationships] count] > 0,
                      @"Described child entity should have at least one FK relationship");
    }
}

/**
 * Creates a child table without any FK column, then adds one via schema sync
 * (representing a new to-one relationship being introduced).
 * Verifies the FK column is present on the child table afterwards.
 */
- (void)testAddToOneRelationship
{
    if (!self.channel) return;

    /* Create parent table and a child table WITHOUT the FK column yet. */
    EOModel *parentModel = [self modelWithColumns:@[@"parent_id", @"name"]];
    [[parentModel entityNamed:@"TestEntity"] setExternalName:kParentTable];
    [self createSchemaForModel:parentModel];

    EOModel *childModel = [self modelWithColumns:@[@"child_id", @"label"]];
    [[childModel entityNamed:@"TestEntity"] setExternalName:kChildTable];
    [self createSchemaForModel:childModel];

    /* Build the "after" child model: add a FK column 'parent_id'. */
    EOEntity    *childEntity = [childModel entityNamed:@"TestEntity"];
    EOAttribute *fkAttr      = [self makeAttributeNamed:@"parent_id"
                                             columnName:@"parent_id"
                                           externalType:[self integerTypeName]
                                             allowsNull:YES];
    [childEntity addAttribute:fkAttr];

    NSDictionary *changes = @{
        kChildTable: @{
            @"insertedAttributes": @[fkAttr]
        }
    };
    [self applySyncChanges:changes toModel:childModel];

    XCTAssertTrue([self table:kChildTable hasColumnNamed:@"parent_id"],
                  @"FK column 'parent_id' should exist on child table after add");

    /* Single-table cleanup; the rename test uses kTestTableRenamed. */
    [self dropTableNamed:kChildTable];
    [self dropTableNamed:kParentTable];
}

/**
 * Creates parent and child tables with a FK column, then removes that FK
 * column via schema sync (representing dropping the to-one relationship).
 * Verifies the FK column is absent from the child table afterwards.
 */
- (void)testDropToOneRelationship
{
    if (!self.channel) return;

    EOModel *model = [self makeParentChildModel];
    [self createSchemaForModel:model];

    /* Build the "after" child model: remove the FK column. */
    EOEntity    *childEntity = [model entityNamed:@"Child"];
    EOAttribute *fkAttr      = [childEntity attributeNamed:@"parent_id"];
    [childEntity removeAttribute:fkAttr];

    NSDictionary *changes = @{
        kChildTable: @{
            @"deletedColumnNames": @[@"parent_id"]
        }
    };
    [self applySyncChanges:changes toModel:model];

    XCTAssertFalse([self table:kChildTable hasColumnNamed:@"parent_id"],
                   @"FK column 'parent_id' should be absent after drop");
    XCTAssertTrue([self table:kChildTable hasColumnNamed:@"child_id"],
                  @"PK column 'child_id' should still be present");
}

/**
 * Makes a to-one relationship mandatory (isMandatory = YES) by changing the
 * FK column from NULL to NOT NULL via schema sync.
 * Verifies that the FK column has allowsNull == NO in the live schema.
 */
- (void)testToOneRelationshipMandatory
{
    if (!self.channel) return;

    EOModel *model = [self makeParentChildModel];
    [self createSchemaForModel:model];

    /* Make the FK column NOT NULL. */
    EOEntity    *childEntity = [model entityNamed:@"Child"];
    EOAttribute *fkAttr      = [childEntity attributeNamed:@"parent_id"];
    [fkAttr setAllowsNull:NO];

    NSDictionary *changes = @{
        kChildTable: @{
            @"modifiedAttributes": @{
                @"parent_id": @{
                    EOAllowsNullKey: @NO
                }
            }
        }
    };
    [self applySyncChanges:changes toModel:model];

    EOEntity *described = [self describeTableNamed:kChildTable];
    XCTAssertNotNil(described, @"Child table must exist after mandatory change");
    EOAttribute *attr = attributeWithColumn(described, @"parent_id");
    XCTAssertNotNil(attr, @"FK column 'parent_id' should still exist");
    XCTAssertFalse([attr allowsNull],
                   @"FK column should be NOT NULL after isMandatory sync");
}

/**
 * Tests the "add to-many relationship" scenario, which — at the DB level —
 * is identical to adding a FK column on the "many" side (child) table.
 * (The to-many lives on the parent entity in the model, but the FK column
 * lives on the child's table.)
 *
 * Verifies the FK column is present on the child (many-side) table.
 */
- (void)testAddToManyRelationship
{
    if (!self.channel) return;

    /* Create parent and a child table without any FK column. */
    EOModel *parentModel = [self modelWithColumns:@[@"parent_id", @"name"]];
    [[parentModel entityNamed:@"TestEntity"] setExternalName:kParentTable];
    [self createSchemaForModel:parentModel];

    EOModel *childModel = [self modelWithColumns:@[@"child_id", @"label"]];
    [[childModel entityNamed:@"TestEntity"] setExternalName:kChildTable];
    [self createSchemaForModel:childModel];

    /* Add the FK column on the child (many-side) table.
     * From the parent model's perspective, this FK column backs the
     * to-many relationship "parent has many children". */
    EOEntity    *childEntity = [childModel entityNamed:@"TestEntity"];
    EOAttribute *fkAttr      = [self makeAttributeNamed:@"parent_id"
                                             columnName:@"parent_id"
                                           externalType:[self integerTypeName]
                                             allowsNull:YES];
    [childEntity addAttribute:fkAttr];

    NSDictionary *changes = @{
        kChildTable: @{
            @"insertedAttributes": @[fkAttr]
        }
    };
    [self applySyncChanges:changes toModel:childModel];

    XCTAssertTrue([self table:kChildTable hasColumnNamed:@"parent_id"],
                  @"FK column 'parent_id' (to-many backing column) should exist on child table");

    [self dropTableNamed:kChildTable];
    [self dropTableNamed:kParentTable];
}

@end
