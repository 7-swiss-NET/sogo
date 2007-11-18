/* UIxMailPartICalActions.m - this file is part of SOGo
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

#import <Foundation/NSCalendarDate.h>

#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGObjWeb/WOResponse.h>

#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalEvent.h>
#import <NGCards/iCalPerson.h>

#import <UI/Common/WODirectAction+SOGo.h>

#import <NGImap4/NGImap4EnvelopeAddress.h>

#import <SoObjects/Appointments/iCalPerson+SOGo.h>
#import <SoObjects/Appointments/SOGoAppointmentObject.h>
#import <SoObjects/Appointments/SOGoAppointmentFolder.h>
#import <SoObjects/Mailer/SOGoMailObject.h>
#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/SOGo/iCalEntityObject+Utilities.h>
#import <SoObjects/Mailer/SOGoMailBodyPart.h>

#import "UIxMailPartICalActions.h"

@implementation UIxMailPartICalActions

- (iCalEvent *) _emailEvent
{
  NSData *content;
  NSString *eventString;
  iCalCalendar *emailCalendar;

  content = [[self clientObject] fetchBLOB];
  eventString = [[NSString alloc] initWithData: content
				  encoding: NSUTF8StringEncoding];
  if (!eventString)
    eventString = [[NSString alloc] initWithData: content
				    encoding: NSISOLatin1StringEncoding];
  emailCalendar = [iCalCalendar parseSingleFromSource: eventString];

  return (iCalEvent *) [emailCalendar firstChildWithTag: @"vevent"];
}

- (SOGoAppointmentObject *) _eventObjectWithUID: (NSString *) uid
					forUser: (SOGoUser *) user
{
  SOGoAppointmentFolder *personalFolder;
  SOGoAppointmentObject *eventObject;

  personalFolder = [user personalCalendarFolderInContext: context];
  eventObject = [personalFolder lookupName: uid
				inContext: context acquire: NO];
  if (![eventObject isKindOfClass: [SOGoAppointmentObject class]])
    eventObject = [SOGoAppointmentObject objectWithName: uid
					 inContainer: personalFolder];
  
  return eventObject;
}

- (SOGoAppointmentObject *) _eventObjectWithUID: (NSString *) uid
{
  return [self _eventObjectWithUID: uid forUser: [context activeUser]];
}

- (iCalEvent *)
  _setupChosenEventAndEventObject: (SOGoAppointmentObject **) eventObject
{
  iCalEvent *emailEvent, *calendarEvent, *chosenEvent;

  emailEvent = [self _emailEvent];
  if (emailEvent)
    {
      *eventObject = [self _eventObjectWithUID: [emailEvent uid]];
      if ([*eventObject isNew])
	chosenEvent = emailEvent;
      else
	{
	  calendarEvent = (iCalEvent *) [*eventObject component: NO secure: NO];
	  if ([calendarEvent compare: emailEvent] == NSOrderedAscending)
	    chosenEvent = emailEvent;
	  else
	    chosenEvent = calendarEvent;
	}
    }
  else
    chosenEvent = nil;

  return chosenEvent;
}

#warning this is code copied from SOGoAppointmentObject...
- (void) _updateAttendee: (iCalPerson *) attendee
	    withSequence: (NSNumber *) sequence
	       andCalUID: (NSString *) calUID
		  forUID: (NSString *) uid
{
  SOGoAppointmentObject *eventObject;
  iCalEvent *event;
  iCalPerson *otherAttendee;
  NSString *iCalString;

  eventObject = [self _eventObjectWithUID: calUID
		      forUser: [SOGoUser userWithLogin: uid roles: nil]];
  if (![eventObject isNew])
    {
      event = [eventObject component: NO secure: NO];
      if ([[event sequence] compare: sequence]
	  == NSOrderedSame)
	{
	  otherAttendee
	    = [event findParticipantWithEmail: [attendee rfc822Email]];
	  [otherAttendee setPartStat: [attendee partStat]];
	  iCalString = [[event parent] versitString];
	  [eventObject saveContentString: iCalString];
	}
    }
}

- (WOResponse *) _changePartStatusAction: (NSString *) newStatus
{
  WOResponse *response;
  SOGoAppointmentObject *eventObject;
  iCalEvent *chosenEvent;
  iCalPerson *user;
  iCalCalendar *emailCalendar, *calendar;
  NSString *rsvp, *method, *organizerUID;

  chosenEvent = [self _setupChosenEventAndEventObject: &eventObject];
  if (chosenEvent)
    {
      user = [chosenEvent findParticipant: [context activeUser]];
      [user setPartStat: newStatus];
      calendar = [chosenEvent parent];
      emailCalendar = [[self _emailEvent] parent];
      method = [[emailCalendar method] lowercaseString];
      if ([method isEqualToString: @"request"])
	{
	  [calendar setMethod: @""];
	  rsvp = [[user rsvp] lowercaseString];
	}
      else
	rsvp = nil;
      [eventObject saveContentString: [calendar versitString]];
      if ([rsvp isEqualToString: @"true"])
	[eventObject sendResponseToOrganizer];
      organizerUID = [[chosenEvent organizer] uid];
      if (organizerUID)
	[self _updateAttendee: user withSequence: [chosenEvent sequence]
	      andCalUID: [chosenEvent uid] forUID: organizerUID];
      response = [self responseWith204];
    }
  else
    {
      response = [context response];
      [response setStatus: 409];
    }

  return response;
}

- (WOResponse *) acceptAction
{
  return [self _changePartStatusAction: @"ACCEPTED"];
}

- (WOResponse *) declineAction
{
  return [self _changePartStatusAction: @"DECLINED"];
}

- (WOResponse *) deleteFromCalendarAction
{
  iCalEvent *emailEvent;
  SOGoAppointmentObject *eventObject;
  WOResponse *response;

  emailEvent = [self _emailEvent];
  if (emailEvent)
    {
      eventObject = [self _eventObjectWithUID: [emailEvent uid]];
      response = [self responseWith204];
    }
  else
    {
      response = [context response];
      [response setStatus: 409];
    }

  return response;
}

- (iCalPerson *) _emailParticipantWithEvent: (iCalEvent *) event
{
  NSString *emailFrom;
  SOGoMailObject *mailObject;
  NGImap4EnvelopeAddress *address;

  mailObject = [[self clientObject] mailObject];
  address = [[mailObject fromEnvelopeAddresses] objectAtIndex: 0];
  emailFrom = [address baseEMail];

  return [event findParticipantWithEmail: emailFrom];
}

- (BOOL) _updateParticipantStatusInEvent: (iCalEvent *) calendarEvent
			       fromEvent: (iCalEvent *) emailEvent
				inObject: (SOGoAppointmentObject *) eventObject
{
  iCalPerson *calendarParticipant, *mailParticipant;
  NSString *partStat;
  BOOL result;

  calendarParticipant = [self _emailParticipantWithEvent: calendarEvent];
  mailParticipant = [self _emailParticipantWithEvent: emailEvent];
  if (calendarParticipant && mailParticipant)
    {
      result = YES;
      partStat = [mailParticipant partStat];
      if ([partStat caseInsensitiveCompare: [calendarParticipant partStat]]
	  != NSOrderedSame)
	{
	  [calendarParticipant setPartStat: [partStat uppercaseString]];
	  [eventObject saveComponent: calendarEvent];
	}
    }
  else
    result = NO;

  return result;
}

- (WOResponse *) updateUserStatusAction
{
  iCalEvent *emailEvent, *calendarEvent;
  SOGoAppointmentObject *eventObject;
  WOResponse *response;

  response = nil;

  emailEvent = [self _emailEvent];
  if (emailEvent)
    {
      eventObject = [self _eventObjectWithUID: [emailEvent uid]];
      calendarEvent = [eventObject component: NO secure: NO];
      if (([[emailEvent sequence] compare: [calendarEvent sequence]]
	  != NSOrderedDescending)
	  && ([self _updateParticipantStatusInEvent: calendarEvent
		    fromEvent: emailEvent
		    inObject: eventObject]))
	response = [self responseWith204];
    }

  if (!response)
    {
      response = [context response];
      [response setStatus: 409];
    }

  return response;
}

// - (WOResponse *) markTentativeAction
// {
//   return [self _changePartStatusAction: @"TENTATIVE"];
// }

// - (WOResponse *) addToCalendarAction
// {
//   return [self responseWithStatus: 404];
// }

// - (WOResponse *) deleteFromCalendarAction
// {
//   return [self responseWithStatus: 404];
// }

@end
