/*
  Copyright (C) 2008-2011 Inverse inc.
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

#import <Foundation/NSArray.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimeZone.h>

#import <NGCards/iCalDateTime.h>
#import <NGCards/iCalRecurrenceRule.h>
#import <NGCards/iCalRecurrenceCalculator.h>
#import <NGCards/iCalTimeZone.h>
#import <NGCards/NSString+NGCards.h>
#import <NGExtensions/NGCalendarDateRange.h>

#import "iCalRepeatableEntityObject+SOGo.h"

@implementation iCalRepeatableEntityObject (SOGoExtensions)

- (NSArray *) _indexedRules: (NSArray *) rules
{
  NSMutableArray *ma;
  unsigned int i, count;
  NSString *valuesString;
  iCalRecurrenceRule *rule;

  ma = nil;

  count = [rules count];
  if (count > 0)
    {
      ma = [NSMutableArray arrayWithCapacity: count];
      for (i = 0; i < count; i++)
	{
	  rule = [rules objectAtIndex:i];
#warning we could return an NSArray instead and feed it as such to the iCalRecurrenceRule in SOGoAppointmentFolder...
	  valuesString = [[rule values] componentsJoinedByString: @";"];
	  [ma addObject: valuesString];
	}
    }

  return ma;
}

- (NSString *) cycleInfo
{
  NSArray *rules;
  NSString *value;
  NSMutableDictionary *cycleInfo;

  if ([self isRecurrent])
    {
      cycleInfo = [NSMutableDictionary dictionaryWithCapacity: 3];

      /* rules */
      rules = [self _indexedRules: [self recurrenceRules]];
      if (rules)
	[cycleInfo setObject: rules forKey: @"rules"];
      
      rules = [self _indexedRules: [self exceptionRules]];
      if (rules)
	[cycleInfo setObject: rules forKey: @"exRules"];

      rules = [self exceptionDates];
      if ([rules count])
	[cycleInfo setObject: rules forKey: @"exDates"];

      value = [cycleInfo description];
    }
  else
    value = nil;

  return value;
}

- (NGCalendarDateRange *) firstOccurenceRange
{
  [self subclassResponsibility: _cmd];

  return nil;
}

- (unsigned int) occurenceInterval
{
  [self subclassResponsibility: _cmd];

  return 0;
}

/**
 * Checks if a date is part of the recurring entity.
 * @param theOccurrenceDate the date to verify.
 * @return true if the occurence date is part of the recurring entity.
 */
- (BOOL) doesOccurOnDate: (NSCalendarDate *) theOccurenceDate
{
  NSArray *ranges;
  NGCalendarDateRange *checkRange, *firstRange;
  NSCalendarDate *startDate, *endDate;
  iCalDateTime *firstStartDate;
  BOOL doesOccur;

  doesOccur = [self isRecurrent];
  if (doesOccur)
    {
      // Retrieve the range of the first event
      firstRange = [self firstOccurenceRange];

      // Set the range to check with respect to the event timezone (extracted from the start date)
      firstStartDate = (iCalDateTime *)[self uniqueChildWithTag: @"dtstart"];
      startDate = [[firstStartDate timeZone] computedDateForDate: theOccurenceDate];
      endDate = [startDate addTimeInterval: [self occurenceInterval]];
      checkRange = [NGCalendarDateRange calendarDateRangeWithStartDate: startDate
							       endDate: endDate];

      // Calculate the occurrences for the given date
      ranges = [iCalRecurrenceCalculator recurrenceRangesWithinCalendarDateRange: checkRange
						  firstInstanceCalendarDateRange: firstRange
								 recurrenceRules: [self recurrenceRules]
								  exceptionRules: [self exceptionRules]
								  exceptionDates: [self exceptionDates]];
      doesOccur = [ranges dateRangeArrayContainsDate: startDate];
    }

  return doesOccur;
}

@end
