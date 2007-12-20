/* NSString+NGCards.m - this file is part of SOPE
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
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSTimeZone.h>
#import <NGExtensions/NSObject+Logs.h>

#import <ctype.h>

#import "NSString+NGCards.h"

static NSString *commaSeparator = nil;

@implementation NSString (NGCardsExtensions)

- (void) _initCommaSeparator
{
  commaSeparator = [NSMutableString stringWithFormat: @"%c", 255];
  [commaSeparator retain];
}

- (NSString *) foldedForVersitCards
{
  NSMutableString *foldedString;
  unsigned int length;
  NSRange subStringRange;

  foldedString = [NSMutableString new];
  [foldedString autorelease];

  length = [self length];
  if (length < 76)
    [foldedString appendString: self];
  else
    {
      subStringRange = NSMakeRange (0, 75);
      [foldedString appendFormat: @"%@\r\n",
                    [self substringWithRange: subStringRange]];
      subStringRange = NSMakeRange (75, 74);
      while ((length - subStringRange.location) > 74)
        {
          [foldedString appendFormat: @" %@\r\n",
                        [self substringWithRange: subStringRange]];
          subStringRange.location += 74;
        }
      subStringRange.length = length - subStringRange.location;
      [foldedString appendFormat: @" %@",
                    [self substringWithRange: subStringRange]];
    }

  return foldedString;
}

- (NSArray *) asCardAttributeValues
{
  NSMutableArray *values;
  NSEnumerator *rawValues;
  NSString *tmpString, *rawValue, *newString;

  values = [NSMutableArray new];
  [values autorelease];

  if (!commaSeparator)
    [self _initCommaSeparator];

  tmpString = [self stringByReplacingString: @"\\,"
                    withString: commaSeparator];
  rawValues = [[tmpString componentsSeparatedByString: @","]
                objectEnumerator];
  rawValue = [rawValues nextObject];
  while (rawValue)
    {
      newString = [rawValue stringByReplacingString: commaSeparator
                            withString: @","];
      [values addObject: [newString stringByTrimmingSpaces]];
      rawValue = [rawValues nextObject];
    }

  return values;
}

- (NSString *) escapedForCards
{
  NSString *string;

  string = [self stringByReplacingString: @"\\"
                 withString: @"\\\\"];
  string = [string stringByReplacingString: @","
                   withString: @"\\,"];
//   string = [string stringByReplacingString: @":"
//                    withString: @"\\:"];
  string = [string stringByReplacingString: @";"
                   withString: @"\\;"];
  string = [string stringByReplacingString: @"\n"
                   withString: @"\\n"];
  string = [string stringByReplacingString: @"\r"
                   withString: @"\\r"];

  return string;
}

- (NSString *) unescapedFromCard
{
  NSString *string;

  string = [self stringByReplacingString: @"\\,"
                 withString: @","];
  string = [string stringByReplacingString: @"\\:"
                   withString: @":"];
  string = [string stringByReplacingString: @"\\;"
                   withString: @";"];
  string = [string stringByReplacingString: @"\\n"
                   withString: @"\n"];
  string = [string stringByReplacingString: @"\\r"
                   withString: @"\r"];
  string = [string stringByReplacingString: @"\\\\"
                   withString: @"\\"];

  return string;
}

- (NSTimeInterval) durationAsTimeInterval
{
  /*
    eg: DURATION:PT1H
    P      - "period"
    P2H30M - "2 hours 30 minutes"

     dur-value  = (["+"] / "-") "P" (dur-date / dur-time / dur-week)

     dur-date   = dur-day [dur-time]
     dur-time   = "T" (dur-hour / dur-minute / dur-second)
     dur-week   = 1*DIGIT "W"
     dur-hour   = 1*DIGIT "H" [dur-minute]
     dur-minute = 1*DIGIT "M" [dur-second]
     dur-second = 1*DIGIT "S"
     dur-day    = 1*DIGIT "D"
  */
  unsigned       i, len;
  NSTimeInterval ti;
  BOOL           isTime;
  int            val;
    
  if (![self hasPrefix:@"P"]) {
    NSLog(@"Cannot parse iCal duration value: '%@'", self);
    return 0.0;
  }
    
  ti  = 0.0;
  val = 0;
  for (i = 1, len = [self length], isTime = NO; i < len; i++) {
    unichar c;
      
    c = [self characterAtIndex:i];
    if (c == 't' || c == 'T') {
      isTime = YES;
      val = 0;
      continue;
    }
      
    if (isdigit(c)) {
      val = (val * 10) + (c - 48);
      continue;
    }
      
    switch (c) {
    case 'W': /* week */
      ti += (val * 7 * 24 * 60 * 60);
      break;
    case 'D': /* day  */
      ti += (val * 24 * 60 * 60);
      break;
    case 'H': /* hour */
      ti += (val * 60 * 60);
      break;
    case 'M': /* min  */
      ti += (val * 60);
      break;
    case 'S': /* sec  */
      ti += val;
      break;
    default:
      [self logWithFormat: @"cannot process duration unit: '%c'", c];
      break;
    }
    val = 0;
  }
  return ti;
}

- (NSCalendarDate *) asCalendarDate
{
  NSRange cursor;
  NSCalendarDate *date;
  NSTimeZone *utc;
  unsigned int length;
  int year, month, day, hour, minute, second;

  length = [self length];
  if (length > 7)
    {
      cursor = NSMakeRange(0, 4);
      year = [[self substringWithRange: cursor] intValue];
      cursor.location += cursor.length;
      cursor.length = 2;
      month = [[self substringWithRange: cursor] intValue];
      cursor.location += cursor.length;
      day = [[self substringWithRange: cursor] intValue];

      if (length > 14)
	{
	  cursor.location += cursor.length + 1;
	  hour = [[self substringWithRange: cursor] intValue];
	  cursor.location += cursor.length;
	  minute = [[self substringWithRange: cursor] intValue];
	  cursor.location += cursor.length;
	  second = [[self substringWithRange: cursor] intValue];
	}
      else
	{
	  hour = 0;
	  minute = 0;
	  second = 0;
	}

      utc = [NSTimeZone timeZoneWithAbbreviation: @"GMT"];
      date = [NSCalendarDate dateWithYear: year month: month 
                             day: day hour: hour minute: minute 
                             second: second
                             timeZone: utc];
    }
  else
    date = nil;

  return date;
}

- (BOOL) isAllDayDate
{
  return ([self length] == 8);
}

- (NSArray *) componentsWithSafeSeparator: (unichar) separator
{
  NSMutableArray *components;
  NSRange currentRange;
  unichar *stringBuffer;
  unichar currentChar;
  unsigned int count, length;
  BOOL escaped;

  components = [NSMutableArray array];

  length = [self length];
  stringBuffer = malloc (sizeof (unichar) * length);
  [self getCharacters: stringBuffer];

  currentRange = NSMakeRange(0, 0);
  escaped = NO;
  count = 0;
  while (count < length)
    {
      if (escaped)
	currentRange.length++;
      else
	{
	  currentChar = *(stringBuffer + count);
	  if (currentChar == '\\')
	    escaped = YES;
	  else if (currentChar == separator)
	    {
	      [components
		addObject: [self substringWithRange: currentRange]];
	      currentRange = NSMakeRange (count + 1, 0);
	    }
	  else
	    currentRange.length++;
	}
      count++;
    }
  [components
    addObject: [self substringWithRange: currentRange]];

  free (stringBuffer);

  return components;
}

@end
