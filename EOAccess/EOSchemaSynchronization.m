/* -*-objc-*-
   EOSchemaSynchronization.m

   Copyright (C) 2007 Free Software Foundation, Inc.

   Date: July 2007

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

#include <Foundation/Foundation.h>

#include "EOSchemaSynchronization.h"

NSString *EOSchemaSynchronizationForeignKeyConstraintsKey = @"EOSchemaSynchronizationForeignKeyConstraintsKey";
NSString *EOSchemaSynchronizationPrimaryKeyConstraintsKey = @"EOSchemaSynchronizationPrimaryKeyConstraintsKey";
NSString *EOSchemaSynchronizationPrimaryKeySupportKey = @"EOSchemaSynchronizationPrimaryKeySupportKey";

NSString *EOAllowsNullKey = @"allowsNull";
NSString *EOColumnNameKey = @"columnName";
NSString *EOExternalNameKey = @"externalName";
NSString *EOExternalTypeKey = @"externalType";
NSString *EONameKey = @"name";
NSString *EOPrecisionKey = @"precision";
NSString *EORelationshipsKey = @"relationships";
NSString *EOScaleKey = @"scale";
NSString *EOWidthKey = @"width";
static id _schemaSynchronizationDelegate = nil;

@implementation EOAdaptor (EOSchemaSynchronization)
- (NSDictionary *)objectStoreChangesFromAttribute:(EOAttribute *)schemaAttribute
				      toAttribute:(EOAttribute *)modelAttribute
{
  NSMutableDictionary *changes;
  Class exprClass;
  NSString *schemaColumnName;
  NSString *modelColumnName;

  changes = [NSMutableDictionary dictionary];
  exprClass = [self defaultExpressionClass];
  schemaColumnName = [schemaAttribute columnName];
  modelColumnName = [modelAttribute columnName];

  if ((schemaColumnName || modelColumnName)
      && ![schemaColumnName isEqualToString: modelColumnName])
    {
      if (modelColumnName)
	{
	  [changes setObject: modelColumnName
		      forKey: EOColumnNameKey];
	}
    }

  if (![exprClass isColumnType:(id <EOColumnTypes>)schemaAttribute
	equivalentToColumnType:(id <EOColumnTypes>)modelAttribute
			 options:nil])
    {
      if ([modelAttribute externalType])
	{
	  [changes setObject:[modelAttribute externalType]
		      forKey:EOExternalTypeKey];
	}
      if ([modelAttribute width])
	{
	  [changes setObject:[NSNumber numberWithUnsignedInt:[modelAttribute width]]
		      forKey:EOWidthKey];
	}
      if ([modelAttribute precision])
	{
	  [changes setObject:[NSNumber numberWithUnsignedInt:[modelAttribute precision]]
		      forKey:EOPrecisionKey];
	}
      if ([modelAttribute scale])
	{
	  [changes setObject:[NSNumber numberWithInt:[modelAttribute scale]]
		      forKey:EOScaleKey];
	}
    }

  if ([schemaAttribute allowsNull] != [modelAttribute allowsNull])
    {
      [changes setObject:[NSNumber numberWithBool:[modelAttribute allowsNull]]
		  forKey:EOAllowsNullKey];
    }

  return [changes count] ? [NSDictionary dictionaryWithDictionary: changes] : nil;
}
@end

@implementation EOAdaptorChannel (EOSchemaSynchronization)
- (void)beginSchemaSynchronization
{
  /* Subclasses may override to BEGIN a transaction for DDL statements. */
}
- (void)endSchemaSynchronization
{
  /* Subclasses may override to COMMIT. */
}
@end

@implementation EOSQLExpression (EOSchemaSynchronization)
+ (BOOL)isCaseSensitive
{
  return NO;
}

+ (BOOL)isColumnType:(id <EOColumnTypes>)columnType1
equivalentToColumnType:(id <EOColumnTypes>)columnType2
	     options:(NSDictionary *)options
{
  NSString *name1;
  NSString *name2;

  name1 = [columnType1 name];
  name2 = [columnType2 name];
  if (name1 == nil || name2 == nil)
    {
      if (name1 != name2)
	return NO;
    }
  else if ([name1 caseInsensitiveCompare: name2] != NSOrderedSame)
    return NO;
  if ([columnType1 width] != [columnType2 width])
    return NO;
  if ([columnType1 precision] != [columnType2 precision])
    return NO;
  if ([columnType1 scale] != [columnType2 scale])
    return NO;

  return YES;
}
+ (NSArray *)logicalErrorsInChangeDictionary:(NSDictionary *)changes
				    forModel:(EOModel *)model
				     options:(NSDictionary *)options
{
  NSMutableArray *errors;

  errors = [NSMutableArray array];

  if ([changes objectForKey: EOExternalTypeKey] && ![self supportsDirectColumnCoercion])
    {
      [errors addObject: @"Direct column type coercion is not supported by this adaptor."];
    }
  if ([changes objectForKey: EOColumnNameKey] && ![self supportsDirectColumnRenaming])
    {
      [errors addObject: @"Direct column renaming is not supported by this adaptor."];
    }
  if ([changes objectForKey: EOAllowsNullKey]
      && ![self supportsDirectColumnNullRuleModification])
    {
      [errors addObject: @"Direct column null rule modification is not supported by this adaptor."];
    }

  return [errors count] ? errors : nil;
}
+ (NSString *)phraseCastingColumnNamed:(NSString *)columnName
			      fromType:(id <EOColumnTypes>)type
				toType:(id <EOColumnTypes>)castType
			       options:(NSDictionary *)options
{
  return nil;
}

+ (id)schemaSynchronizationDelegate
{
  return _schemaSynchronizationDelegate;
}
+ (void)setSchemaSynchronizationDelegate:(id)delegate
{
  _schemaSynchronizationDelegate = delegate;
}
+ (NSArray *)statementsToCopyTableNamed:(NSString *)tableName
		intoTableForEntityGroup:(NSArray *)entityGroup
		   withChangeDictionary:(NSDictionary *)changes
				options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToModifyColumnNamed:(NSString *)columnName
			      inTableNamed:(NSString *)tableName
				toNullRule:(BOOL)allowsNull
				   options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToConvertColumnNamed:(NSString *)columnName
			       inTableNamed:(NSString *)tableName
				   fromType:(id <EOColumnTypes>)type
				     toType:(id <EOColumnTypes>)newType
				    options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToDeleteColumnNamed:(NSString *)columnName
			      inTableNamed:(NSString *)tableName
				   options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToInsertColumnForAttribute:(EOAttribute *)attribute
					  options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToRenameColumnNamed:(NSString *)columnName
			      inTableNamed:(NSString *)tableName
				   newName:(NSString *)newName
				   options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToDropForeignKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
					    withChangeDictionary:(NSDictionary *)changes
							 options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToDropPrimaryKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
					    withChangeDictionary:(NSDictionary *)changes
							 options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToDropPrimaryKeySupportForEntityGroups:(NSArray *)entityGroups
					 withChangeDictionary:(NSDictionary *)changes
						      options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToImplementForeignKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
						 withChangeDictionary:(NSDictionary *)changes
							      options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToImplementPrimaryKeyConstraintsOnEntityGroups:(NSArray *)entityGroups
						 withChangeDictionary:(NSDictionary *)changes
							      options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToImplementPrimaryKeySupportForEntityGroups:(NSArray *)entityGroups
					      withChangeDictionary:(NSDictionary *)changes
							   options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToRenameTableNamed:(NSString *)tableName
				  newName:(NSString *)newName
				  options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToUpdateObjectStoreForModel:(EOModel *)model
			      withChangeDictionary:(NSDictionary *)changes
					   options:(NSDictionary *)options
{
  return nil;
}
+ (NSArray *)statementsToUpdateObjectStoreForEntityGroups:(NSArray *)entityGroups
				     withChangeDictionary:(NSDictionary *)changes
						  options:(NSDictionary *)options
{
  return nil;
}
+ (BOOL)supportsDirectColumnNullRuleModification
{
  return NO;
}
+ (BOOL)supportsDirectColumnCoercion
{
  return NO;
}
+ (BOOL)supportsDirectColumnDeletion
{
  return NO;
}
+ (BOOL)supportsDirectColumnInsertion
{
  return NO;
}
+ (BOOL)supportsDirectColumnRenaming
{
  return NO;
}

+ (BOOL)supportsSchemaSynchronization
{
  return NO;
}

@end
