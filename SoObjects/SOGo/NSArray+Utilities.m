/* NSArray+Utilities.m - this file is part of SOGo
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

#import <Foundation/NSNull.h>
#import <Foundation/NSString.h>

#import "NSArray+Utilities.h"

@implementation NSArray (SOGoArrayUtilities)

- (NSArray *) stringsWithFormat: (NSString *) format
{
  NSMutableArray *formattedStrings;
  NSEnumerator *objects;
  id currentObject;

  formattedStrings = [NSMutableArray arrayWithCapacity: [self count]];

  objects = [self objectEnumerator];
  currentObject = [objects nextObject];
  while (currentObject)
    {
      if ([currentObject isKindOfClass: [NSNull class]])
	[formattedStrings addObject: @""];
      else
	[formattedStrings
	  addObject: [NSString stringWithFormat: format, currentObject]];
      currentObject = [objects nextObject];
    }

  return formattedStrings;
}

- (NSArray *) keysWithFormat: (NSString *) format
{
  NSMutableArray *formattedStrings;
  NSEnumerator *objects;
  id currentObject;

  formattedStrings = [NSMutableArray arrayWithCapacity: [self count]];

  objects = [self objectEnumerator];
  currentObject = [objects nextObject];
  while (currentObject)
    {
      [formattedStrings addObject: [currentObject keysWithFormat: format]];
      currentObject = [objects nextObject];
    }

  return formattedStrings;
}

- (NSArray *) objectsForKey: (NSString *) key
{
  NSMutableArray *objectsForKey;
  unsigned int count, max;
  id value;

  max = [self count];
  objectsForKey = [NSMutableArray arrayWithCapacity: max];

  for (count = 0; count < max; count++)
    {
      value = [[self objectAtIndex: count] objectForKey: key];
      [objectsForKey addObject: value];
    }

  return objectsForKey;
}

- (NSArray *) flattenedArray
{
  NSMutableArray *flattenedArray;
  NSEnumerator *objects;
  id currentObject;

  flattenedArray = [NSMutableArray array];
  objects = [self objectEnumerator];
  currentObject = [objects nextObject];
  while (currentObject)
    {
      [flattenedArray addObjectsFromArray: currentObject];
      currentObject = [objects nextObject];
    }

  return flattenedArray;
}

- (NSArray *) uniqueObjects
{
  NSMutableArray *newArray;
  NSEnumerator *objects;
  id currentObject;

  newArray = [NSMutableArray array];

  objects = [self objectEnumerator];
  while ((currentObject = [objects nextObject]))
    [newArray addObjectUniquely: currentObject];

  return newArray;
}

- (void) makeObjectsPerform: (SEL) selector
                 withObject: (id) object1
                 withObject: (id) object2
{
  int count, max;

  max = [self count];
  for (count = 0; count < max; count++)
    [[self objectAtIndex: count] performSelector: selector
                                 withObject: object1
                                 withObject: object2];
}

- (NSString *) jsonRepresentation
{
  id currentElement;
  NSMutableArray *jsonElements;
  NSEnumerator *elements;
  NSString *representation;

  jsonElements = [NSMutableArray new];

  elements = [self objectEnumerator];
  currentElement = [elements nextObject];
  while (currentElement)
    {
      [jsonElements addObject: [currentElement jsonRepresentation]];
      currentElement = [elements nextObject];
    }
  representation = [NSString stringWithFormat: @"[%@]",
			     [jsonElements componentsJoinedByString: @", "]];
  [jsonElements release];

  return representation;
}

- (BOOL) containsCaseInsensitiveString: (NSString *) match
{
  BOOL response;
  NSString *currentString, *cmpObject;
  NSEnumerator *objects;

  response = NO;

  cmpObject = [match lowercaseString];
  objects = [self objectEnumerator];
  currentString = [objects nextObject];
  while (currentString && !response)
    if ([[currentString lowercaseString] isEqualToString: cmpObject])
      response = YES;
    else
      currentString = [objects nextObject];

  return response;
}

@end

@implementation NSMutableArray (SOGoArrayUtilities)

- (void) addObjectUniquely: (id) object
{
  if (![self containsObject: object])
    [self addObject: object];
}

- (void) addRange: (NSRange) newRange
{
  [self addObject: NSStringFromRange (newRange)];
}

- (BOOL) hasRangeIntersection: (NSRange) testRange
{
  NSEnumerator *ranges;
  NSString *currentRangeString;
  NSRange currentRange;
  BOOL response;

  response = NO;

  ranges = [self objectEnumerator];
  currentRangeString = [ranges nextObject];
  while (!response && currentRangeString)
    {
      currentRange = NSRangeFromString (currentRangeString);
      if (NSLocationInRange (testRange.location, currentRange)
	  || NSLocationInRange (NSMaxRange (testRange), currentRange))
	response = YES;
      else
	currentRangeString = [ranges nextObject];
    }

  return response;
}

@end

