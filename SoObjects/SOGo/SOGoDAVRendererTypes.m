/* SOGoDAVRendererTypes.m - this file is part of SOGo
 *
 * Copyright (C) 2006 Inverse groupe conseil
 *
 * Author: Wolfgang Sourdeau <wsourdeau@inverse.ca>
 *
 * This file is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This file is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

#import <Foundation/NSArray.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSString.h>

#import "SOGoDAVRendererTypes.h"

@implementation SOGoDAVSet

+ (id) davSetWithArray: (NSArray *) newValues
      ofValuesTaggedAs: (NSString *) newValueTag
{
  id davSet;

  davSet = [self new];
  [davSet setValueTag: newValueTag];
  [davSet setValues: newValues];
  [davSet autorelease];

  return davSet;
}

- (id) init
{
  if ((self = [super init]))
    {
      valueTag = nil;
      values = nil;
    }

  return self;
}

- (void) dealloc
{
  if (valueTag)
    [valueTag release];
  if (values)
    [values release];
  [super dealloc];
}

- (void) setValueTag: (NSString *) newValueTag
{
  ASSIGN (valueTag, newValueTag);
}

- (void) setValues: (NSArray *) newValues
{
  ASSIGN (values, newValues);
}

- (NSString *) stringForTag: (NSString *) _key
                    rawName: (NSString *) setTag
                  inContext: (id) context
                   prefixes: (NSDictionary *) prefixes
{
  NSMutableString *resultString;
  id currentValue;
  NSString *valueString;
  NSEnumerator *valueEnum;

  resultString = [NSMutableString new];
  [resultString autorelease];

  [resultString appendFormat: @"<%@>", setTag];
  valueEnum = [values objectEnumerator];
  currentValue = [valueEnum nextObject];
  while (currentValue)
    {
      if ([currentValue isKindOfClass: [SoWebDAVValue class]])
        valueString
          = [currentValue stringForTag:
                            [NSString stringWithFormat: @"{DAV:}%@", valueTag]
                          rawName: [NSString stringWithFormat: @"D:%@", valueTag]
                          inContext: context
                          prefixes: prefixes];
      else
        valueString = currentValue;

      [resultString appendFormat: @"<%@>%@</%@>",
                    valueTag, valueString, valueTag];
      currentValue = [valueEnum nextObject];
    }
  [resultString appendFormat: @"</%@>", setTag];

  NSLog(@"dav rendering for key '%@' and tag '%@':\n", _key, setTag,
        resultString);

  return resultString;
}

@end
