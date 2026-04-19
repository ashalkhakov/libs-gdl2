
/* 
   SQLite3Expression.m

   Copyright (C) 2006 Free Software Foundation, Inc.

   Author: Matt Rice <ratmice@gmail.com>
   Date: 2006

   This file is part of the GNUstep Database Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
*/

#ifndef GNUSTEP
#include <GNUstepBase/Additions.h>
#endif
#include "SQLite3Expression.h"
#include <EOAccess/EOEntity.h>
#include <EOAccess/EOModel.h>
#include <EOAccess/EOAttribute.h>
#include <EOAccess/EOSchemaGeneration.h>
#include <EOAccess/EOSchemaSynchronization.h>
#include <EOControl/EONull.h>
#include <Foundation/NSData.h>
#include <Foundation/NSProcessInfo.h>

@implementation SQLite3Expression 
static NSString *escapeValue(id value)
{
  NSMutableString *string = [NSMutableString stringWithFormat: @"%@", value];
  unsigned length = [string length];
  unsigned dif, i;

  if (length)
    {
      unichar tempString[length];
   
      [string getCharacters:tempString];

      for (i = 0, dif = 0; i < length; i++)
        {
          switch (tempString[i])
            {
              case '\'':
                [string insertString: @"'" atIndex: dif + i];
                dif++;
                break;
              default:
                break;
            }
        } 
    }
  return string;
}

+ (NSString *)formatValue: (id)value
             forAttribute: (EOAttribute *)attribute
{
  NSString *externalType = [attribute externalType];
  
  if (!value)
    {
      return @"NULL";
    }
  else if ([value isEqual: [EONull null]])
    {
      return [value sqlString];
    }
  else if ([externalType isEqual:@"TEXT"])
    {
      return [NSString stringWithFormat:@"'%@'", escapeValue(value)];
    }
  else if ([externalType isEqual:@"BLOB"])
    {
      return [NSString stringWithFormat:@"X'%@'", [(NSData *)value hexadecimalRepresentation]];
    }
  else
    {
      return [NSString stringWithFormat:@"'%@'", escapeValue(value)];
    }
}
- (NSString *)lockClause
{
  return @""; // does not support locking..
}

- (NSString *)assembleSelectStatementWithAttributes: (NSArray *)attributes
                                               lock: (BOOL)lock
                                          qualifier: (EOQualifier *)qualifier
                                         fetchOrder: (NSArray *)fetchOrder
                                       selectString: (NSString *)selectString
                                         columnList: (NSString *)columnList
                                          tableList: (NSString *)tableList
                                        whereClause: (NSString *)whereClause
                                         joinClause: (NSString *)joinClause
                                      orderByClause: (NSString *)orderByClause
                                         lockClause: (NSString *)lockClause
{
  NSMutableString *sqlString;
  
  sqlString = [NSMutableString stringWithFormat: @"%@ %@ FROM %@",
                               selectString,
                               columnList,
                               tableList];
  if (whereClause && joinClause)
    {
      [sqlString appendFormat: @" WHERE (%@) AND (%@)",
                  whereClause,
                  joinClause];
    }
  else if (whereClause || joinClause)
    {
      [sqlString appendFormat: @" WHERE %@",
               (whereClause ? whereClause : joinClause)];
    }

  if (orderByClause)
    [sqlString appendFormat: @" ORDER BY %@", orderByClause];

  return sqlString;
}

- (NSString *)columnTypeStringForAttribute:(EOAttribute *)attribute
{
  NSString *typeString = [super columnTypeStringForAttribute:attribute];
  if ([[[attribute entity] primaryKeyAttributes] containsObject:attribute])
    {
      return [NSString stringWithFormat:@"%@ %@", typeString, @"PRIMARY KEY"];
    }
  return typeString; 
}


+ (NSArray *)primaryKeySupportStatementsForEntityGroup: (NSArray *)entityGroup
{
  return [NSArray array];
}

+ (NSArray *)dropPrimaryKeySupportStatementsForEntityGroup: (NSArray *)entityGroup
{
  return [NSArray array];
}

+ (NSArray *)createDatabaseStatementsForConnectionDictionary: (NSDictionary *)connDict
                          administrativeConnectionDictionary: (NSDictionary *)admConnDict
{
  return [NSArray array];
}

+ (NSArray *)dropDatabaseStatementsForConnectionDictionary: (NSDictionary *)connDict
                          administrativeConnectionDictionary: (NSDictionary *)admConnDict
{
  return [NSArray array];
}
			  
// TODO find a better way to do this?
+ (NSArray *)primaryKeyConstraintStatementsForEntityGroup:(NSArray *)entityGroup
{
  NSString *keyTable;
  keyTable = @"CREATE TABLE IF NOT EXISTS 'SQLiteEOAdaptorKeySequences' (" \
	     @"seq_key INTEGER PRIMARY KEY AUTOINCREMENT, " \
	     @"tableName TEXT, " \
	     @"attributeName TEXT, " \
	     @"key INTEGER" \
	     @")";
  return [NSArray arrayWithObject:[self expressionForString:keyTable]];
}

+ (NSArray *)dropPrimaryKeyConstraintStatementsForEntityGroup:(NSArray *)entityGroup
{
  return [NSArray arrayWithObject:[self expressionForString:@"DROP TABLE 'SQLiteEOAdaptorKeySequences'"]];
}

+ (NSArray *)foreignKeyConstraintStatementsForRelationship: (EORelationship *)relationship
{
  /* SQLite3 doesn't currently handle ADD CONSTRAINT from ALTER TABLE. */ 
  return [NSArray array];
}

@end

@implementation SQLite3Expression (EOSchemaSynchronization)

+ (NSArray *)_entityGroupsForModel:(EOModel *)model
{
  NSMutableArray *groups;
  NSMutableDictionary *seenExternalNames;
  NSArray *entities;
  unsigned i, h, count;

  groups = [NSMutableArray array];
  seenExternalNames = [NSMutableDictionary dictionary];
  entities = [model entities];
  count = [entities count];

  for (i = 0; i < count; i++)
    {
      EOEntity *entity;
      NSMutableArray *group;
      NSString *externalName;

      entity = [entities objectAtIndex: i];
      externalName = [entity externalName];
      if ([seenExternalNames objectForKey: externalName])
	{
	  continue;
	}
      [seenExternalNames setObject: @"YES" forKey: externalName];
      group = [NSMutableArray arrayWithCapacity: 1];
      [group addObject: entity];
      [groups addObject: group];

      for (h = i + 1; h < count; h++)
	{
	  EOEntity *otherEntity;

	  otherEntity = [entities objectAtIndex: h];
	  if ([[otherEntity externalName] isEqual: externalName])
	    {
	      [group addObject: otherEntity];
	    }
	}
    }

  return groups;
}

+ (BOOL)supportsSchemaSynchronization
{
  return YES;
}
+ (BOOL)supportsDirectColumnInsertion
{
  return YES;
}
+ (BOOL)supportsDirectColumnDeletion
{
  return NO;
}
+ (BOOL)supportsDirectColumnRenaming
{
  return YES;
}
+ (BOOL)supportsDirectColumnNullRuleModification
{
  return NO;
}
+ (BOOL)supportsDirectColumnCoercion
{
  return NO;
}
+ (BOOL)isCaseSensitive
{
  return NO;
}

+ (NSArray *)statementsToInsertColumnForAttribute:(EOAttribute *)attribute
					  options:(NSDictionary *)options
{
  EOEntity *entity;
  EOSQLExpression *expr;
  NSString *tableName;
  NSString *columnName;
  NSString *columnType;
  NSString *allowsNull;
  NSString *stmt;

  entity = [attribute entity];
  expr = [self sqlExpressionWithEntity: entity];
  tableName = [expr sqlStringForSchemaObjectName: [entity externalName]];
  columnName = [expr sqlStringForSchemaObjectName: [attribute columnName]];
  columnType = [expr columnTypeStringForAttribute: attribute];
  allowsNull = [expr allowsNullClauseForConstraint: [attribute allowsNull]];

  if (allowsNull)
    {
      stmt = [NSString stringWithFormat: @"ALTER TABLE %@ ADD COLUMN %@ %@ %@",
		       tableName, columnName, columnType, allowsNull];
    }
  else
    {
      stmt = [NSString stringWithFormat: @"ALTER TABLE %@ ADD COLUMN %@ %@",
		       tableName, columnName, columnType];
    }
  [expr setStatement: stmt];

  return [NSArray arrayWithObject: expr];
}

+ (NSArray *)statementsToRenameColumnNamed:(NSString *)columnName
			      inTableNamed:(NSString *)tableName
				   newName:(NSString *)newName
				   options:(NSDictionary *)options
{
  EOSQLExpression *expr;
  NSString *quotedTableName;
  NSString *quotedColumnName;
  NSString *quotedNewName;
  NSString *stmt;

  expr = [self sqlExpressionWithEntity: nil];
  quotedTableName = [expr sqlStringForSchemaObjectName: tableName];
  quotedColumnName = [expr sqlStringForSchemaObjectName: columnName];
  quotedNewName = [expr sqlStringForSchemaObjectName: newName];
  stmt = [NSString stringWithFormat: @"ALTER TABLE %@ RENAME COLUMN %@ TO %@",
		   quotedTableName, quotedColumnName, quotedNewName];
  [expr setStatement: stmt];

  return [NSArray arrayWithObject: expr];
}

+ (NSArray *)statementsToRenameTableNamed:(NSString *)tableName
				  newName:(NSString *)newName
				  options:(NSDictionary *)options
{
  EOSQLExpression *expr;
  NSString *quotedTableName;
  NSString *quotedNewName;
  NSString *stmt;

  expr = [self sqlExpressionWithEntity: nil];
  quotedTableName = [expr sqlStringForSchemaObjectName: tableName];
  quotedNewName = [expr sqlStringForSchemaObjectName: newName];
  stmt = [NSString stringWithFormat: @"ALTER TABLE %@ RENAME TO %@",
		   quotedTableName, quotedNewName];
  [expr setStatement: stmt];

  return [NSArray arrayWithObject: expr];
}

+ (NSArray *)statementsToCopyTableNamed:(NSString *)tableName
		intoTableForEntityGroup:(NSArray *)entityGroup
		   withChangeDictionary:(NSDictionary *)changes
				options:(NSDictionary *)options
{
  NSMutableArray *sqlExps;
  EOEntity *entity;
  EOSQLExpression *expr;
  NSString *tmpTableName;
  NSString *quotedTableName;
  NSString *quotedTmpTableName;
  NSEnumerator *entityEnum;
  EOEntity *iterEntity;
  NSMutableArray *insertColumns;
  NSMutableArray *selectColumns;
  NSDictionary *renamedColumns;
  NSMutableDictionary *oldByNewColumnNames;
  NSArray *insertedAttributes;
  NSArray *deletedColumnNames;
  NSString *stmt;

  sqlExps = [NSMutableArray array];
  entity = [entityGroup objectAtIndex: 0];
  expr = [self sqlExpressionWithEntity: entity];
  tmpTableName = [NSString stringWithFormat: @"__gdl2tmp__%@_%@",
			   tableName,
			   [[NSProcessInfo processInfo] globallyUniqueString]];
  quotedTableName = [expr sqlStringForSchemaObjectName: tableName];
  quotedTmpTableName = [expr sqlStringForSchemaObjectName: tmpTableName];

  {
    EOSQLExpression *createExpr;
    NSEnumerator *groupEntityEnum;
    EOEntity *groupEntity;

    createExpr = [self sqlExpressionWithEntity: entity];
    groupEntityEnum = [entityGroup objectEnumerator];
    while ((groupEntity = [groupEntityEnum nextObject]))
      {
	NSEnumerator *attrEnum;
	EOAttribute *attribute;

	attrEnum = [[groupEntity attributes] objectEnumerator];
	while ((attribute = [attrEnum nextObject]))
	  [createExpr addCreateClauseForAttribute: attribute];
      }
    stmt = [NSString stringWithFormat: @"CREATE TABLE %@ (%@)",
		     quotedTmpTableName,
		     [createExpr listString]];
    [createExpr setStatement: stmt];
    [sqlExps addObject: createExpr];
  }

  renamedColumns = [changes objectForKey: @"renamedColumns"];
  oldByNewColumnNames = [NSMutableDictionary dictionary];
  {
    NSEnumerator *nameEnum;
    NSString *oldColumnName;

    nameEnum = [renamedColumns keyEnumerator];
    while ((oldColumnName = [nameEnum nextObject]))
      {
	[oldByNewColumnNames setObject: oldColumnName
				 forKey: [renamedColumns objectForKey: oldColumnName]];
      }
  }

  insertedAttributes = [changes objectForKey: @"insertedAttributes"];
  deletedColumnNames = [changes objectForKey: @"deletedColumnNames"];
  insertColumns = [NSMutableArray array];
  selectColumns = [NSMutableArray array];

  entityEnum = [entityGroup objectEnumerator];
  while ((iterEntity = [entityEnum nextObject]))
    {
      NSEnumerator *attrEnum;
      EOAttribute *attribute;

      attrEnum = [[iterEntity attributes] objectEnumerator];
      while ((attribute = [attrEnum nextObject]))
	{
	  NSString *targetColumnName;
	  NSString *sourceColumnName;
	  BOOL skipColumn;
	  NSEnumerator *insertedEnum;
	  EOAttribute *insertedAttribute;

	  targetColumnName = [attribute columnName];
	  sourceColumnName = [oldByNewColumnNames objectForKey: targetColumnName];
	  if (sourceColumnName == nil)
	    sourceColumnName = targetColumnName;

	  skipColumn = NO;
	  insertedEnum = [insertedAttributes objectEnumerator];
	  while ((insertedAttribute = [insertedEnum nextObject]))
	    {
	      if ([[insertedAttribute columnName] isEqualToString: targetColumnName])
		{
		  skipColumn = YES;
		  break;
		}
	    }
	  if ([deletedColumnNames containsObject: sourceColumnName])
	    {
	      skipColumn = YES;
	    }
	  if (skipColumn)
	    continue;

	  [insertColumns addObject: [expr sqlStringForSchemaObjectName: targetColumnName]];
	  [selectColumns addObject: [expr sqlStringForSchemaObjectName: sourceColumnName]];
	}
    }

  if ([insertColumns count])
    {
      EOSQLExpression *insertExpr;

      insertExpr = [self sqlExpressionWithEntity: entity];
      stmt = [NSString stringWithFormat: @"INSERT INTO %@ (%@) SELECT %@ FROM %@",
		       quotedTmpTableName,
		       [insertColumns componentsJoinedByString: @", "],
		       [selectColumns componentsJoinedByString: @", "],
		       quotedTableName];
      [insertExpr setStatement: stmt];
      [sqlExps addObject: insertExpr];
    }

  {
    EOSQLExpression *dropExpr;

    dropExpr = [self sqlExpressionWithEntity: entity];
    stmt = [NSString stringWithFormat: @"DROP TABLE %@", quotedTableName];
    [dropExpr setStatement: stmt];
    [sqlExps addObject: dropExpr];
  }

  {
    EOSQLExpression *renameExpr;

    renameExpr = [self sqlExpressionWithEntity: entity];
    stmt = [NSString stringWithFormat: @"ALTER TABLE %@ RENAME TO %@",
		     quotedTmpTableName, quotedTableName];
    [renameExpr setStatement: stmt];
    [sqlExps addObject: renameExpr];
  }

  [sqlExps addObjectsFromArray:
	    [self primaryKeyConstraintStatementsForEntityGroup: entityGroup]];

  return sqlExps;
}

+ (NSArray *)statementsToDropPrimaryKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
					    withChangeDictionary:(NSDictionary *)changes
							 options:(NSDictionary *)options
{
  return [NSArray array];
}

+ (NSArray *)statementsToImplementPrimaryKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
						 withChangeDictionary:(NSDictionary *)changes
							      options:(NSDictionary *)options
{
  return [self primaryKeyConstraintStatementsForEntityGroups: entityGroups];
}

+ (NSArray *)statementsToDropPrimaryKeySupportForEntityGroups:(NSArray *)entityGroups
					 withChangeDictionary:(NSDictionary *)changes
						      options:(NSDictionary *)options
{
  return [NSArray array];
}

+ (NSArray *)statementsToImplementPrimaryKeySupportForEntityGroups:(NSArray *)entityGroups
					      withChangeDictionary:(NSDictionary *)changes
							   options:(NSDictionary *)options
{
  return [NSArray array];
}

+ (NSArray *)statementsToDropForeignKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
					    withChangeDictionary:(NSDictionary *)changes
							 options:(NSDictionary *)options
{
  return [NSArray array];
}

+ (NSArray *)statementsToImplementForeignKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
						 withChangeDictionary:(NSDictionary *)changes
							      options:(NSDictionary *)options
{
  return [NSArray array];
}

+ (NSArray *)statementsToUpdateObjectStoreForEntityGroups:(NSArray *)entityGroups
				     withChangeDictionary:(NSDictionary *)changes
						  options:(NSDictionary *)options
{
  NSMutableArray *sqlExps;
  NSEnumerator *groupEnum;
  NSArray *group;

  sqlExps = [NSMutableArray array];
  groupEnum = [entityGroups objectEnumerator];
  while ((group = [groupEnum nextObject]))
    {
      EOEntity *entity;
      NSString *tableName;
      NSDictionary *entityChanges;
      NSArray *insertedAttributes;
      NSDictionary *renamedColumns;
      NSDictionary *modifiedAttributes;
      NSArray *deletedColumnNames;
      BOOL requiresCopy;

      entity = [group objectAtIndex: 0];
      tableName = [entity externalName];
      entityChanges = [changes objectForKey: tableName];
      if (entityChanges == nil)
	continue;

      insertedAttributes = [entityChanges objectForKey: @"insertedAttributes"];
      renamedColumns = [entityChanges objectForKey: @"renamedColumns"];
      modifiedAttributes = [entityChanges objectForKey: @"modifiedAttributes"];
      deletedColumnNames = [entityChanges objectForKey: @"deletedColumnNames"];

      requiresCopy = NO;
      if ([deletedColumnNames count])
	requiresCopy = YES;
      if ([modifiedAttributes count])
	{
	  NSEnumerator *modEnum;
	  NSString *columnName;

	  modEnum = [modifiedAttributes keyEnumerator];
	  while ((columnName = [modEnum nextObject]))
	    {
	      NSDictionary *columnChanges;

	      columnChanges = [modifiedAttributes objectForKey: columnName];
	      if ([self logicalErrorsInChangeDictionary: columnChanges
					     forModel: [entity model]
					      options: options])
		{
		  requiresCopy = YES;
		  break;
		}
	    }
	}

      if (requiresCopy)
	{
	  NSString *newTableName;

	  [sqlExps addObjectsFromArray:
		    [self statementsToCopyTableNamed: tableName
				      intoTableForEntityGroup: group
					 withChangeDictionary: entityChanges
						      options: options]];
	  newTableName = [entityChanges objectForKey: EOExternalNameKey];
	  if (newTableName)
	    {
	      [sqlExps addObjectsFromArray:
			[self statementsToRenameTableNamed: tableName
						   newName: newTableName
						   options: options]];
	    }
	  continue;
	}

      {
	NSEnumerator *attrEnum;
	EOAttribute *attribute;

	attrEnum = [insertedAttributes objectEnumerator];
	while ((attribute = [attrEnum nextObject]))
	  {
	    [sqlExps addObjectsFromArray:
		      [self statementsToInsertColumnForAttribute: attribute
							 options: options]];
	  }
      }

      {
	NSEnumerator *nameEnum;
	NSString *oldColumnName;

	nameEnum = [renamedColumns keyEnumerator];
	while ((oldColumnName = [nameEnum nextObject]))
	  {
	    NSString *newColumnName;

	    newColumnName = [renamedColumns objectForKey: oldColumnName];
	    [sqlExps addObjectsFromArray:
		      [self statementsToRenameColumnNamed: oldColumnName
					     inTableNamed: tableName
						  newName: newColumnName
						  options: options]];
	  }
      }

      {
	NSString *newTableName;

	newTableName = [entityChanges objectForKey: EOExternalNameKey];
	if (newTableName)
	  {
	    [sqlExps addObjectsFromArray:
		      [self statementsToRenameTableNamed: tableName
						 newName: newTableName
						 options: options]];
	  }
      }
    }

  return sqlExps;
}

+ (NSArray *)statementsToUpdateObjectStoreForModel:(EOModel *)model
			      withChangeDictionary:(NSDictionary *)changes
					   options:(NSDictionary *)options
{
  NSArray *entityGroups;

  entityGroups = [self _entityGroupsForModel: model];

  return [self statementsToUpdateObjectStoreForEntityGroups: entityGroups
				 withChangeDictionary: changes
					      options: options];
}

@end
 
