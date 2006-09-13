/*
  Copyright (C) 2004-2005 SKYRIX Software AG

  This file is part of OpenGroupware.org.

  OGo is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  OGo is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with OGo; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

#include <GDLContentStore/GCSFieldExtractor.h>

@interface OCSContactFieldExtractor : GCSFieldExtractor
@end

#include <NGCards/NGVCard.h>
#include "common.h"

@implementation OCSContactFieldExtractor

static NSString *fieldNames[] = {
  /* quickfield,      vCard KVC path */
  @"givenName",       @"n.given",
  @"cn",              @"fn.stringValue",
  @"sn",              @"n.family",
  @"l",               @"preferredAdr.locality",
  @"mail",            @"preferredEMail.stringValue",
  @"o",               @"org.orgnam",
  @"ou",              @"org.orgunit",
  @"telephoneNumber", @"preferredTel.stringValue",
  nil, nil
};

- (NSMutableDictionary *)extractQuickFieldsFromVCard:(NGVCard *)_vCard {
  NSMutableDictionary *fields;
  unsigned i;

  if (_vCard == nil)
    return nil;
  
  fields = [NSMutableDictionary dictionaryWithCapacity:16];

  for (i = 0; fieldNames[i] != nil; i += 2) {
    id value;

    value = ([fieldNames[i + 1] length] > 0)
      ? [_vCard valueForKeyPath:fieldNames[i + 1]]
      : nil;
    if (![value isNotNull]) value = [NSNull null];
    
    [fields setObject:value forKey:[fieldNames[i] lowercaseString]];
  }
  return fields;
}

- (NSMutableDictionary *)extractQuickFieldsFromVCardString:(NSString *)_str {
  NSArray *vCards;
  
  if ((vCards = [NGVCard parseVCardsFromSource:_str]) == nil) {
    [self errorWithFormat:@"Could not parse content as a vCard."];
    return nil;
  }
  if ([vCards count] == 0) {
    [self errorWithFormat:@"Could not parse content as a vCard."];
    return nil;
  }
  
  if ([vCards count] > 1)
    [self warnWithFormat:@"More than one vCard in content, using first."];
  
  return [self extractQuickFieldsFromVCard:[vCards objectAtIndex:0]];
}

- (NSMutableDictionary *)extractQuickFieldsFromContent:(NSString *)_content {
  NSMutableDictionary *fields;
  NSDictionary *plist;
  unsigned i;
  
  if ([_content length] == 0)
    return nil;
  
  if ([_content hasPrefix:@"BEGIN:VCARD"])
    return [self extractQuickFieldsFromVCardString:_content];
  
  // TODO: we want to support vcard storage in the future?!
  
  if ((plist = [_content propertyList]) == nil) {
    [self logWithFormat:@"ERROR: could not parse property list content!"];
    return nil;
  }
  
  if (![plist isKindOfClass:[NSDictionary class]]) {
    [self logWithFormat:@"ERROR: parsed property list is not a dictionary!"];
    return nil;
  }
  
  fields = [NSMutableDictionary dictionaryWithCapacity:16];
  
  /* copy field values to quick record */
  for (i = 0; fieldNames[i] != nil; i += 2) {
    NSString *fieldName, *sqlName;
    id value;
    
    fieldName = fieldNames[i];
    sqlName   = [fieldName lowercaseString]; /* actually pgsql doesn't care */
    
    value = [plist objectForKey:fieldName];
    if ([value isNotNull])
      [fields setObject:value forKey:sqlName];
    else
      [fields setObject:[NSNull null] forKey:sqlName];
  }
  
  return fields;
}

@end /* OCSContactFieldExtractor */
