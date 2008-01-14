/* UIxAppointmentEditor.m - this file is part of SOGo
 *
 * Copyright (C) 2007 Inverse groupe conseil
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

#include <math.h>

#import <NGObjWeb/SoObject.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/WOResponse.h>
#import <NGObjWeb/NSException+HTTP.h>
#import <NGExtensions/NSCalendarDate+misc.h>

#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalEvent.h>
#import <NGCards/iCalPerson.h>
#import <NGCards/iCalRecurrenceRule.h>

#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/SOGo/SOGoContentObject.h>
#import <SoObjects/Appointments/SOGoAppointmentFolder.h>
#import <SoObjects/Appointments/SOGoAppointmentObject.h>

#import "UIxComponentEditor.h"
#import "UIxAppointmentEditor.h"

@implementation UIxAppointmentEditor

- (id) init
{
  if ((self = [super init]))
    {
      aptStartDate = nil;
      aptEndDate = nil;
      item = nil;
      event = nil;
      isAllDay = NO;
    }

  return self;
}

- (void) dealloc
{
  [item release];
  [aptStartDate release];
  [aptEndDate release];
  [super dealloc];
}

/* template values */
- (iCalEvent *) event
{
  if (!event)
    {
      event = (iCalEvent *) [[self clientObject] component: YES secure: YES];
      [event retain];
    }

  return event;
}

- (NSString *) saveURL
{
  return [NSString stringWithFormat: @"%@/saveAsAppointment",
                   [[self clientObject] baseURL]];
}

/* icalendar values */
- (BOOL) isAllDay
{
  NSString *hm;

  hm = [self queryParameterForKey: @"hm"];

  return (isAllDay
	  || (hm && [hm isEqualToString: @"allday"]));
}

- (void) setIsAllDay: (BOOL) newIsAllDay
{
  isAllDay = newIsAllDay;
}

- (void) setAptStartDate: (NSCalendarDate *) newAptStartDate
{
  ASSIGN (aptStartDate, newAptStartDate);
}

- (NSCalendarDate *) aptStartDate
{
  return aptStartDate;
}

- (void) setAptEndDate: (NSCalendarDate *) newAptEndDate
{
  ASSIGN (aptEndDate, newAptEndDate);
}

- (NSCalendarDate *) aptEndDate
{
  return aptEndDate;
}

- (void) setItem: (NSString *) newItem
{
  ASSIGN (item, newItem);
}

- (NSString *) item
{
  return item;
}

/* actions */
- (NSCalendarDate *) newStartDate
{
  NSCalendarDate *newStartDate, *now;
  NSTimeZone *timeZone;
  int hour;

  newStartDate = [self selectedDate];
  if ([[self queryParameterForKey: @"hm"] length] == 0)
    {
      now = [NSCalendarDate calendarDate];
      timeZone = [[context activeUser] timeZone];
      [now setTimeZone: timeZone];
      if ([now isDateOnSameDay: newStartDate])
        {
          hour = [now hourOfDay];
          if (hour < 8)
            newStartDate = [now hour: 8 minute: 0];
          else if (hour > 18)
            newStartDate = [[now tomorrow] hour: 8 minute: 0];
          else
            newStartDate = now;
        }
      else
        newStartDate = [newStartDate hour: 8 minute: 0];
    }

  return newStartDate;
}

- (id <WOActionResults>) defaultAction
{
  NSCalendarDate *startDate, *endDate;
  NSString *duration;
  unsigned int minutes;

  [self event];
  if ([[self clientObject] isNew])
    {
      startDate = [self newStartDate];
      duration = [self queryParameterForKey:@"dur"];
      if ([duration length] > 0)
	minutes = [duration intValue];
      else
	minutes = 60;
      endDate
	= [startDate dateByAddingYears: 0 months: 0 days: 0
		     hours: 0 minutes: minutes seconds: 0];
    }
  else
    {
      startDate = [event startDate];
      isAllDay = [event isAllDay];
      if (isAllDay)
	endDate = [[event endDate] dateByAddingYears: 0 months: 0 days: -1];
      else
	endDate = [event endDate];
    }

  ASSIGN (aptStartDate, startDate);
  ASSIGN (aptEndDate, endDate);

  return self;
}

- (id <WOActionResults>) newAction
{
  NSString *objectId, *method, *uri;
  id <WOActionResults> result;
  SOGoAppointmentFolder *co;

  co = [self clientObject];
  objectId = [co globallyUniqueObjectId];
  if ([objectId length] > 0)
    {
      method = [NSString stringWithFormat:@"%@/%@.ics/editAsAppointment",
                         [co soURL], objectId];
      uri = [self completeHrefForMethod: method];
      result = [self redirectToLocation: uri];
    }
  else
    result = [NSException exceptionWithHTTPStatus: 500 /* Internal Error */
                          reason: @"could not create a unique ID"];

  return result;
}

- (id <WOActionResults>) saveAction
{
  [[self clientObject] saveComponent: event];

  return [self jsCloseWithRefreshMethod: @"refreshEventsAndDisplay()"];
}

- (BOOL) shouldTakeValuesFromRequest: (WORequest *) request
                           inContext: (WOContext*) context
{
  NSString *actionName;

  actionName = [[request requestHandlerPath] lastPathComponent];

  return ([[self clientObject] isKindOfClass: [SOGoAppointmentObject class]]
	  && [actionName hasPrefix: @"save"]);
}

- (void) takeValuesFromRequest: (WORequest *) _rq
                     inContext: (WOContext *) _ctx
{
  SOGoAppointmentObject *clientObject;
  int nbrDays;

  clientObject = [self clientObject];
  [self event];

  [super takeValuesFromRequest: _rq inContext: _ctx];

  if (isAllDay)
    {
      nbrDays = ((float) abs ([aptEndDate timeIntervalSinceDate: aptStartDate])
		 / 86400) + 1;
      [event setAllDayWithStartDate: aptStartDate
	     duration: nbrDays];
    }
  else
    {
      [event setStartDate: aptStartDate];
      [event setEndDate: aptEndDate];
    }
  if ([clientObject isNew])
    [event setTransparency: @"OPAQUE"];
}

// TODO: add tentatively

- (id) acceptAction
{
  [[self clientObject] changeParticipationStatus: @"ACCEPTED"];

  return self;
}

- (id) declineAction
{
  [[self clientObject] changeParticipationStatus: @"DECLINED"];

  return self;
}

@end
