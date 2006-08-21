/* UIxCalAptListView.m - this file is part of SOGo
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

#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

#import <NGExtensions/NSCalendarDate+misc.h>
#import <Appointments/SOGoAppointmentFolder.h>

#import <SOGoUI/SOGoDateFormatter.h>

#import "UIxCalAptListView.h"

@implementation UIxCalAptListView

- (id) init
{
  if ((self = [super init]))
    {
      startDate = nil;
      endDate = nil;
    }

  return self;
}

- (void) setCurrentAppointment: (NSDictionary *) apt
{
  currentAppointment = apt;
}

- (NSDictionary *) currentAppointment
{
  return currentAppointment;
}

//     @"view_all", nil,
//     @"view_today",  @"flags = 'seen'   AND NOT (flags = 'deleted')",
//     @"view_next7",  @"flags = 'unseen' AND NOT (flags = 'deleted')",
//     @"view_next14", @"flags = 'deleted'",
//     @"view_next31", @"flags = 'flagged'",
//     @"view_thismonth", @"flags = 'flagged'",
//     @"view_future", @"flags = 'flagged'",
//     @"view_selectedday", @"flags = 'flagged'",

// - (NSCalendarDate *)firstDayOfMonth;
// - (NSCalendarDate *)lastDayOfMonth;

- (NSCalendarDate *) startDate
{
  NSString *filterPopup;

  if (!startDate)
    {
      filterPopup = [self queryParameterForKey: @"filterpopup"];
      if (filterPopup
          && [filterPopup length] > 0
          && ![filterPopup isEqualToString: @"view_all"])
        {
          if ([filterPopup isEqualToString: @"view_thismonth"])
            startDate = [[NSCalendarDate date] firstDayOfMonth];
          else if ([filterPopup isEqualToString: @"view_selectedday"])
            startDate = [self selectedDate];
          else
            startDate = [NSCalendarDate date];
          startDate = [startDate beginOfDay];
        }
      else
        startDate = [NSCalendarDate dateWithTimeIntervalSince1970: 0];
    }

  return startDate;
}

- (NSCalendarDate *) endDate
{
  NSCalendarDate *today;
  NSString *filterPopup;

  if (!endDate)
    {
      filterPopup = [self queryParameterForKey: @"filterpopup"];
      if (filterPopup
          && [filterPopup length] > 0
          && ![filterPopup isEqualToString: @"view_all"]
          && ![filterPopup isEqualToString: @"view_future"])
        {
          if ([filterPopup isEqualToString: @"view_thismonth"])
            endDate = [[NSCalendarDate date] lastDayOfMonth];
          else if ([filterPopup isEqualToString: @"view_selectedday"])
            endDate = [self selectedDate];
          else
            {
              today = [NSCalendarDate date];
              if ([filterPopup isEqualToString: @"view_today"])
                endDate = today;
              else if ([filterPopup isEqualToString: @"view_next7"])
                endDate = [today dateByAddingYears: 0 months: 0 days: 7];
              else if ([filterPopup isEqualToString: @"view_next14"])
                endDate = [today dateByAddingYears: 0 months: 0 days: 14];
              else if ([filterPopup isEqualToString: @"view_next31"])
                endDate = [today dateByAddingYears: 0 months: 1 days: 0];
            }

          endDate = [endDate endOfDay];
        }
      else
        endDate = [NSCalendarDate dateWithTimeIntervalSince1970: 0x7fffffff];
    }

  return endDate;
}

- (SOGoDateFormatter *) itemDateFormatter
{
  SOGoDateFormatter *fmt;
  
  fmt = [[SOGoDateFormatter alloc] initWithLocale: [self locale]];
  [fmt autorelease];
  [fmt setFullWeekdayNameAndDetails];

  return fmt;
}

- (NSString *) currentTitle
{
  NSString *fullTitle, *title;

  fullTitle = [currentAppointment objectForKey: @"title"];
  if ([fullTitle length] > 49)
    title = [NSString stringWithFormat: @"%@...",
                      [[currentAppointment objectForKey: @"title"]
                        substringToIndex: 50]];
  else
    title = fullTitle;

  return title;
}

- (NSString *) currentStartTime
{
  NSCalendarDate *date;

  date = [NSCalendarDate dateWithTimeIntervalSince1970:
                           [[currentAppointment objectForKey: @"startdate"]
                             intValue]];

  return [[self itemDateFormatter] stringForObjectValue: date];
}

- (NSString *) currentEndTime
{
  NSCalendarDate *date;

  date = [NSCalendarDate dateWithTimeIntervalSince1970:
                           [[currentAppointment objectForKey: @"enddate"]
                             intValue]];

  return [[self itemDateFormatter] stringForObjectValue: date];
}

- (NSString *) currentLocation
{
  return [currentAppointment objectForKey: @"location"];
}

@end
