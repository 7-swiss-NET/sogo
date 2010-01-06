/* UIxAppointmentEditor.m - this file is part of SOGo
 *
 * Copyright (C) 2007-2009 Inverse inc.
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

#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSTimeZone.h>

#import <NGObjWeb/SoObject.h>
#import <NGObjWeb/SoPermissions.h>
#import <NGObjWeb/SoSecurityManager.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/WOResponse.h>
#import <NGObjWeb/NSException+HTTP.h>
#import <NGExtensions/NSCalendarDate+misc.h>

#import <NGCards/iCalAlarm.h>
#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalEvent.h>
#import <NGCards/iCalPerson.h>
#import <NGCards/iCalTrigger.h>
#import <NGCards/iCalRecurrenceRule.h>
#import <NGCards/iCalTimeZone.h>
#import <NGCards/iCalDateTime.h>

#import <SOGo/NSDictionary+Utilities.h>
#import <SOGo/SOGoContentObject.h>
#import <SOGo/SOGoDateFormatter.h>
#import <SOGo/SOGoPermissions.h>
#import <SOGo/SOGoUser.h>
#import <SOGo/SOGoUserDefaults.h>
#import <Appointments/iCalPerson+SOGo.h>
#import <Appointments/SOGoAppointmentFolder.h>
#import <Appointments/SOGoAppointmentObject.h>
#import <Appointments/SOGoAppointmentOccurence.h>

#import <Appointments/SOGoComponentOccurence.h>

#import "UIxComponentEditor.h"
#import "UIxAppointmentEditor.h"

@implementation UIxAppointmentEditor

- (id) init
{
  SOGoUser *user;

  if ((self = [super init]))
    {
      aptStartDate = nil;
      aptEndDate = nil;
      item = nil;
      event = nil;
      isAllDay = NO;
      isTransparent = NO;
      componentCalendar = nil;

      user = [[self context] activeUser];
      ASSIGN (dateFormatter, [user dateFormatterInContext: context]);
    }

  return self;
}

- (void) dealloc
{
  [item release];
  [[event parent] release];
  [aptStartDate release];
  [aptEndDate release];
  [dateFormatter release];
  [componentCalendar release];
  [super dealloc];
}

/* template values */
- (iCalEvent *) event
{
  if (!event)
    {
      event = (iCalEvent *) [[self clientObject] occurence];
      [[event parent] retain];
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
	  || [hm isEqualToString: @"allday"]);
}

- (void) setIsAllDay: (BOOL) newIsAllDay
{
  isAllDay = newIsAllDay;
}

- (BOOL) isTransparent
{
  return isTransparent;
}

- (void) setIsTransparent: (BOOL) newIsTransparent
{
  isTransparent = newIsTransparent;
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

- (SOGoAppointmentFolder *) componentCalendar
{
  return componentCalendar;
}

- (void) setComponentCalendar: (SOGoAppointmentFolder *) _componentCalendar
{
  ASSIGN (componentCalendar, _componentCalendar);
}

/* read-only event */
- (NSString *) aptStartDateText
{
  return [dateFormatter formattedDate: aptStartDate];
}

- (NSString *) aptStartDateTimeText
{
  return [dateFormatter formattedDateAndTime: aptStartDate];
}

- (NSString *) aptEndDateText
{
  return [dateFormatter formattedDate: aptEndDate];
}

- (NSString *) aptEndDateTimeText
{
  return [dateFormatter formattedDateAndTime: aptEndDate];
}

- (BOOL) startDateIsEqualToEndDate
{
  return [aptStartDate isEqualToDate: aptEndDate];
}

/* actions */
- (NSCalendarDate *) newStartDate
{
  NSCalendarDate *newStartDate, *now;
  NSTimeZone *timeZone;
  SOGoUserDefaults *ud;
  int hour;
  unsigned int uStart, uEnd;

  newStartDate = [self selectedDate];
  if (![[self queryParameterForKey: @"hm"] length])
    {
      ud = [[context activeUser] userDefaults];
      timeZone = [ud timeZone];
      now = [NSCalendarDate calendarDate];
      [now setTimeZone: timeZone];

      uStart = [ud dayStartHour];
      if ([now isDateOnSameDay: newStartDate])
        {
	  uEnd = [ud dayEndHour];
          hour = [now hourOfDay];
          if (hour < uStart)
            newStartDate = [now hour: uStart minute: 0];
          else if (hour > uEnd)
            newStartDate = [[now tomorrow] hour: uStart minute: 0];
          else
            newStartDate = now;
        }
      else
        newStartDate = [newStartDate hour: uStart minute: 0];
    }

  return newStartDate;
}

- (id <WOActionResults>) defaultAction
{
  NSCalendarDate *startDate, *endDate;
  NSString *duration;
  NSTimeZone *timeZone;
  unsigned int minutes;
  SOGoObject <SOGoComponentOccurence> *co;
  SOGoUserDefaults *ud;

  [self event];
  co = [self clientObject];

  ud = [[context activeUser] userDefaults];
  timeZone = [ud timeZone];

  if ([co isNew]
      && [co isKindOfClass: [SOGoCalendarComponent class]])
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
      NSCalendarDate *firstDate;
      iCalEvent *master;
      signed int daylightOffset;

      startDate = [event startDate];
      daylightOffset = 0;

      if ([co isNew] && [co isKindOfClass: [SOGoAppointmentOccurence class]])
        {
          // We are creating a new exception in a recurrent event -- compute the daylight
          // saving time with respect to the first occurrence of the recurrent event.
          master = (iCalEvent*)[[event parent] firstChildWithTag: @"vevent"];
          firstDate = [master startDate];

          if ([timeZone isDaylightSavingTimeForDate: startDate] != [timeZone isDaylightSavingTimeForDate: firstDate])
            {
              daylightOffset = (signed int)[timeZone secondsFromGMTForDate: firstDate]
                             - (signed int)[timeZone secondsFromGMTForDate: startDate];
              startDate = [startDate dateByAddingYears:0 months:0 days:0 hours:0 minutes:0 seconds:daylightOffset];
            }
        }

      isAllDay = [event isAllDay];
      if (isAllDay)
        endDate = [[event endDate] dateByAddingYears: 0 months: 0 days: -1];
      else
        endDate = [[event endDate] dateByAddingYears:0 months:0 days:0 hours:0 minutes:0 seconds:daylightOffset];
      isTransparent = ![event isOpaque];
    }

  [startDate setTimeZone: timeZone];
  ASSIGN (aptStartDate, startDate);

  [endDate setTimeZone: timeZone];
  ASSIGN (aptEndDate, endDate);

  return self;
}

- (id <WOActionResults>) newAction
{
  NSString *objectId, *method, *uri;
  id <WOActionResults> result;
  SOGoAppointmentFolder *co;
  SoSecurityManager *sm;

  co = [self clientObject];
  objectId = [co globallyUniqueObjectId];
  if ([objectId length])
    {
      sm = [SoSecurityManager sharedSecurityManager];
      if (![sm validatePermission: SoPerm_AddDocumentsImagesAndFiles
                         onObject: co
                        inContext: context])
        method = [NSString stringWithFormat:@"%@/%@.ics/editAsAppointment",
                           [co soURL], objectId];
      else
        method = [NSString stringWithFormat: @"%@/Calendar/personal/%@.ics/editAsAppointment",
                           [self userFolderPath], objectId];
      uri = [self completeHrefForMethod: method];
      result = [self redirectToLocation: uri];
    }
  else
    result = [NSException exceptionWithHTTPStatus: 500 /* Internal Error */
                          reason: @"could not create a unique ID"];

  return result;
}

- (void) _adjustRecurrentRules
{
  iCalRecurrenceRule *rule;
  NSEnumerator *rules;
  NSCalendarDate *untilDate;
  SOGoUserDefaults *ud;
  NSTimeZone *timeZone;
  
  rules = [[event recurrenceRules] objectEnumerator];
  ud = [[context activeUser] userDefaults];
  timeZone = [ud timeZone];

  while ((rule = [rules nextObject]))
    {
      untilDate = [rule untilDate];
      if (untilDate)
	{
	  // The until date must match the time of the start date
	  NSCalendarDate *date;

	  date = [[event startDate] copy];
	  [date setTimeZone: timeZone];
	  untilDate = [untilDate dateByAddingYears:0
				 months:0
				 days:0
				 hours:[date hourOfDay]
				 minutes:[date minuteOfHour]
				 seconds:0];
	  [rule setUntilDate: untilDate];
	  [date release];
	}
    }
}

- (id <WOActionResults>) saveAction
{
  SOGoAppointmentFolder *previousCalendar;
  SOGoAppointmentObject *co;
  SoSecurityManager *sm;
  NSException *ex;

  co = [self clientObject];
  if ([co isKindOfClass: [SOGoAppointmentOccurence class]])
    co = [co container];
  previousCalendar = [co container];
  sm = [SoSecurityManager sharedSecurityManager];

  if ([event hasRecurrenceRules])
    [self _adjustRecurrentRules];

  if ([co isNew])
    {
      if (componentCalendar && componentCalendar != previousCalendar)
	{
	  // New event in a different calendar -- make sure the user can
	  // write to the selected calendar since the rights were verified
	  // on the calendar specified in the URL, not on the selected
	  // calendar of the popup menu.
	  if (![sm validatePermission: SoPerm_AddDocumentsImagesAndFiles
		   onObject: componentCalendar
		   inContext: context])
	    co = [componentCalendar lookupName: [co nameInContainer]
				    inContext: context
				    acquire: NO];
	}
      
      // Save the event.
      [co saveComponent: event];
    }
  else
    {
      // The event was modified -- save it.
      [co saveComponent: event];

      if (componentCalendar && componentCalendar != previousCalendar)
	{
	  // The event was moved to a different calendar.
	  if (![sm validatePermission: SoPerm_DeleteObjects
		   onObject: previousCalendar
		   inContext: context])
	    {
	      if (![sm validatePermission: SoPerm_AddDocumentsImagesAndFiles
		       onObject: componentCalendar
		       inContext: context])
		ex = [co moveToFolder: componentCalendar];
	    }
	}
    }
  
  return [self jsCloseWithRefreshMethod: @"refreshEventsAndDisplay()"];
}

- (id <WOActionResults>) viewAction
{
  WOResponse *result;
  NSDictionary *data;
  NSCalendarDate *firstDate, *eventDate;
  NSTimeZone *timeZone;
  SOGoUserDefaults *ud;
  SOGoCalendarComponent *co;
  iCalEvent *master;
  BOOL resetAlarm;
  signed int daylightOffset;

  [self event];

  result = [self responseWithStatus: 200];
  ud = [[context activeUser] userDefaults];
  timeZone = [ud timeZone];
  eventDate = [event startDate];
  [eventDate setTimeZone: timeZone];
  co = [self clientObject];
  
  if (!componentCalendar)
    {
      componentCalendar = [co container];
      if ([componentCalendar isKindOfClass: [SOGoCalendarComponent class]])
	componentCalendar = [componentCalendar container];
      [componentCalendar retain];
    }
  
  resetAlarm = [[[context request] formValueForKey: @"resetAlarm"] boolValue];
  if (resetAlarm && [event hasAlarms] && ![event hasRecurrenceRules])
    {
      iCalAlarm *anAlarm;
      iCalTrigger *aTrigger;

      anAlarm = [[event alarms] objectAtIndex: 0];
      aTrigger = [anAlarm trigger];
      [aTrigger setValue: 0 ofAttribute: @"x-webstatus" to: @"triggered"];

      [co saveComponent: event];
    }

  if ([co isNew] && [co isKindOfClass: [SOGoAppointmentOccurence class]])
    {
      // This is a new exception in a recurrent event -- compute the daylight
      // saving time with respect to the first occurrence of the recurrent event.
      master = (iCalEvent*)[[event parent] firstChildWithTag: @"vevent"];
      firstDate = [master startDate];

      if ([timeZone isDaylightSavingTimeForDate: eventDate] != [timeZone isDaylightSavingTimeForDate: firstDate])
	{
	  daylightOffset = (signed int)[timeZone secondsFromGMTForDate: firstDate] 
	    - (signed int)[timeZone secondsFromGMTForDate: eventDate];
	  eventDate = [eventDate dateByAddingYears:0 months:0 days:0 hours:0 minutes:0 seconds:daylightOffset];
	}
    }
  data = [NSDictionary dictionaryWithObjectsAndKeys:
		       [componentCalendar displayName], @"calendar",
		       [event tag], @"component",
		       [dateFormatter formattedDate: eventDate], @"startDate",
		       [dateFormatter formattedTime: eventDate], @"startTime",
		       ([event hasRecurrenceRules]? @"1": @"0"), @"isReccurent",
		       ([event isAllDay]? @"1": @"0"), @"isAllDay",
		       [event summary], @"summary",
		       [event location], @"location",
		       [event comment], @"description",
		       nil];
  
  [result appendContentString: [data jsonRepresentation]];

  return result;
}

- (BOOL) shouldTakeValuesFromRequest: (WORequest *) request
                           inContext: (WOContext*) context
{
  NSString *actionName;

  actionName = [[request requestHandlerPath] lastPathComponent];

  return ([[self clientObject] conformsToProtocol: @protocol (SOGoComponentOccurence)]
	  && [actionName hasPrefix: @"save"]);
}

- (void) takeValuesFromRequest: (WORequest *) _rq
                     inContext: (WOContext *) _ctx
{
  int nbrDays;
  SOGoUserDefaults *ud;
  
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
  
  if ([[self clientObject] isNew])
    {
      iCalTimeZone *tz;

      ud = [[context activeUser] userDefaults];
      
      tz = [iCalTimeZone timeZoneForName: [ud timeZoneName]];
      [[event parent] addTimeZone: tz];
      [(iCalDateTime *)[event uniqueChildWithTag: @"dtstart"] setTimeZone: tz];
      [(iCalDateTime *)[event uniqueChildWithTag: @"dtend"] setTimeZone: tz];
    }

  [event setTransparency: (isTransparent? @"TRANSPARENT" : @"OPAQUE")];
}

// TODO: add tentatively

- (id) acceptAction
{
  [[self clientObject] changeParticipationStatus: @"ACCEPTED"
                                    withDelegate: nil];

  return self;
}

- (id) declineAction
{
  [[self clientObject] changeParticipationStatus: @"DECLINED"
                                    withDelegate: nil];

  return self;
}

- (id) delegateAction
{
//  BOOL receiveUpdates;
  NSString *delegatedEmail, *delegatedUid;
  iCalPerson *delegatedAttendee;
  SOGoUser *user;
  WORequest *request;
  WOResponse *response;

  response = nil;
  request = [context request];
  delegatedEmail = [request formValueForKey: @"to"];
  if ([delegatedEmail length])
    {
      user = [context activeUser];
      delegatedAttendee = [iCalPerson new];
      [delegatedAttendee autorelease];
      [delegatedAttendee setEmail: delegatedEmail];
      delegatedUid = [delegatedAttendee uid];
      if (delegatedUid)
	{
	  SOGoUser *delegatedUser;
	  delegatedUser = [SOGoUser userWithLogin: delegatedUid];
	  [delegatedAttendee setCn: [delegatedUser cn]];
	}
      
      [delegatedAttendee setRole: @"REQ-PARTICIPANT"];
      [delegatedAttendee setRsvp: @"TRUE"];
      [delegatedAttendee setParticipationStatus: iCalPersonPartStatNeedsAction];
      [delegatedAttendee setDelegatedFrom:
	       [NSString stringWithFormat: @"mailto:%@", [[user allEmails] objectAtIndex: 0]]];
      
//      receiveUpdates = [[request formValueForKey: @"receiveUpdates"] boolValue];
//      if (receiveUpdates)
//	[delegatedAttendee setRole: @"NON-PARTICIPANT"];

      response = (WOResponse*)[[self clientObject] changeParticipationStatus: @"DELEGATED"
						   withDelegate: delegatedAttendee];
    }
  else
    response = [NSException exceptionWithHTTPStatus: 400
					     reason: @"missing 'to' parameter"];

  if (!response)
    response = [self responseWithStatus: 200];

  return response;
}

@end
