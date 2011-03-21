/*
  Copyright (C) 2004-2005 SKYRIX Software AG
  Copyright (C) 2010 Inverse inc.

  This file is part of SOPE.

  SOPE is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  SOPE is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with SOPE; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSString.h>

#import <NGExtensions/NGCalendarDateRange.h>

#import "NSCalendarDate+NGCards.h"
#import "iCalDateTime.h"
#import "iCalTimeZone.h"
#import "iCalRecurrenceRule.h"
#import "iCalRecurrenceCalculator.h"
#import "iCalRepeatableEntityObject.h"

@implementation iCalRepeatableEntityObject

- (Class) classForTag: (NSString *) classTag
{
  Class tagClass;

  if ([classTag isEqualToString: @"RRULE"])
    tagClass = [iCalRecurrenceRule class];
  else if ([classTag isEqualToString: @"EXDATE"])
    tagClass = [iCalDateTime class];
  else
    tagClass = [super classForTag: classTag];

  return tagClass;
}

/* Accessors */

- (void) removeAllRecurrenceRules
{
  [self removeChildren: [self recurrenceRules]];
}

- (void) addToRecurrenceRules: (id) _rrule
{
  [self addChild: _rrule];
}

- (void) setRecurrenceRules: (NSArray *) _rrules
{
  [children removeObjectsInArray: [self childrenWithTag: @"rrule"]];
  [self addChildren: _rrules];
}

- (BOOL) hasRecurrenceRules
{
  return ([[self childrenWithTag: @"rrule"] count] > 0);
}

- (NSArray *) recurrenceRules
{
  return [self childrenWithTag: @"rrule"];
}

- (void) removeAllExceptionRules
{
  [self removeChildren: [self exceptionRules]];
}

- (void) addToExceptionRules: (id) _rrule
{
  [self addChild: _rrule];
}

- (void) setExceptionRules: (NSArray *) _rrules
{
  [children removeObjectsInArray: [self childrenWithTag: @"exrule"]];
  [self addChildren: _rrules];
}

- (BOOL) hasExceptionRules
{
  return ([[self childrenWithTag: @"exrule"] count] > 0);
}

- (NSArray *) exceptionRules
{
  return [self childrenWithTag: @"exrule"];
}

- (void) removeAllExceptionDates
{
  [self removeChildren: [self exceptionDates]];
}

- (void) addToExceptionDates: (NSCalendarDate *) _rdate
{
  iCalDateTime *dateTime;

  dateTime = [iCalDateTime new];
  [dateTime setTag: @"exdate"];
  [dateTime setDateTime: _rdate];
  [self addChild: dateTime];
  [dateTime release];
}

//- (void) setExceptionDates: (NSArray *) _rdates
//{
//  [children removeObjectsInArray: [self childrenWithTag: @"exdate"]];
//  [self addChildren: _rdates];
//}

- (BOOL) hasExceptionDates
{
  return ([[self childrenWithTag: @"exdate"] count] > 0);
}

/**
 * Return the exception dates of the event in GMT.
 * @return an array of strings.
 */
- (NSArray *) exceptionDates
{
  NSArray *exDates;
  NSMutableArray *dates;
  NSEnumerator *dateList;
  NSCalendarDate *exDate;
  NSString *dateString;
  unsigned i;

  dates = [NSMutableArray array];
  dateList = [[self childrenWithTag: @"exdate"] objectEnumerator];
  
  while ((dateString = [dateList nextObject]))
    {
      exDates = [(iCalDateTime*) dateString dateTimes];
      for (i = 0; i < [exDates count]; i++)
	{
	  exDate = [exDates objectAtIndex: i];
	  dateString = [NSString stringWithFormat: @"%@Z",
				 [exDate iCalFormattedDateTimeString]];
	  [dates addObject: dateString];
	}
    }

  return dates;
}

/**
 * Returns the exception dates for the event, but adjusted to the event timezone.
 * Used when calculating a recurrence rule.
 * @param theTimeZone the timezone of the event.
 * @see [iCalTimeZone computedDatesForStrings:]
 * @return the exception dates for the event, adjusted to the event timezone.
 */
- (NSArray *) exceptionDatesWithEventTimeZone: (iCalTimeZone *) theTimeZone
{
  NSArray *dates, *exDates;
  NSEnumerator *dateList;
  NSCalendarDate *exDate;
  NSString *dateString;
  unsigned i;

  if (theTimeZone)
    {
      dates = [NSMutableArray array];
      dateList = [[self childrenWithTag: @"exdate"] objectEnumerator];
      
      while ((dateString = [dateList nextObject]))
	{
	  exDates = [(iCalDateTime*) dateString values];
	  for (i = 0; i < [exDates count]; i++)
	    {
	      dateString = [exDates objectAtIndex: i];
	      exDate = [theTimeZone computedDateForString: dateString];
	      [(NSMutableArray *) dates addObject: exDate];
	    }
	}
    }
  else
    dates = [self exceptionDates];

  return dates;
}

/* Convenience */

- (BOOL) isRecurrent
{
  return [self hasRecurrenceRules];
}

/* Matching */

- (BOOL) isWithinCalendarDateRange: (NGCalendarDateRange *) _range
    firstInstanceCalendarDateRange: (NGCalendarDateRange *) _fir
{
  NSArray *ranges;
  
  ranges = [self recurrenceRangesWithinCalendarDateRange:_range
                 firstInstanceCalendarDateRange:_fir];
  return [ranges count] > 0;
}

- (NSArray *) recurrenceRangesWithinCalendarDateRange: (NGCalendarDateRange *)_r
                       firstInstanceCalendarDateRange: (NGCalendarDateRange *)_fir
{
  return [iCalRecurrenceCalculator recurrenceRangesWithinCalendarDateRange: _r
                                   firstInstanceCalendarDateRange: _fir
                                   recurrenceRules: [self recurrenceRules]
                                   exceptionRules: [self exceptionRules]
                                   exceptionDates: [self exceptionDates]];
}


/* this is the outmost bound possible, not necessarily the real last date */
-    (NSCalendarDate *)
lastPossibleRecurrenceStartDateUsingFirstInstanceCalendarDateRange: (NGCalendarDateRange *)_r
{
  NSCalendarDate *date;
  NSEnumerator *rRules;
  iCalRecurrenceRule *rule;
  iCalRecurrenceCalculator *calc;
  NSCalendarDate *rdate;

  date  = nil;

  rRules = [[self recurrenceRules] objectEnumerator];
  rule = [rRules nextObject];
  while (rule && ![rule isInfinite] & !date)
    {
      calc = [iCalRecurrenceCalculator
               recurrenceCalculatorForRecurrenceRule: rule
               withFirstInstanceCalendarDateRange: _r];
      rdate = [[calc lastInstanceCalendarDateRange] startDate];
      if (!date
          || ([date compare: rdate] == NSOrderedAscending))
        date = rdate;
      else
        rule = [rRules nextObject];
    }

  return date;
}

@end
