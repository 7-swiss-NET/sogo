/*
  Copyright (C) 2004-2005 SKYRIX Software AG
  
  This file is part of OpenGroupware.org.

  OGo is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  OGo is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with OGo; see the file COPYING. If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

/*
  UIxMailPartICalViewer
 
  Show plain/calendar mail parts.
*/

#import <NGObjWeb/WOResponse.h>

#import <NGExtensions/NSCalendarDate+misc.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGExtensions/NSObject+Logs.h>

#import <NGImap4/NGImap4EnvelopeAddress.h>

#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalEvent.h>
#import <NGCards/iCalPerson.h>
#import <NGCards/iCalDateTime.h>

#import <SoObjects/SOGo/SOGoDateFormatter.h>
#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/Appointments/SOGoAppointmentFolder.h>
#import <SoObjects/Appointments/SOGoAppointmentObject.h>
#import <SoObjects/Mailer/SOGoMailObject.h>

#import "UIxMailPartICalViewer.h"

@implementation UIxMailPartICalViewer

- (void) dealloc
{
  [storedEventObject release];
  [storedEvent release];
  [attendee release];
  [item release];
  [inCalendar release];
  [inEvent release];
  [dateFormatter release];
  [super dealloc];
}

/* maintain caches */

- (void) resetPathCaches
{
  [super resetPathCaches];
  [inEvent release]; inEvent = nil;
  [inCalendar release]; inCalendar = nil;
  [storedEventObject release]; storedEventObject = nil;
  [storedEvent release]; storedEvent = nil;
 
  /* not strictly path-related, but useless without it anyway: */
  [attendee release]; attendee = nil;
  [item release]; item = nil;
}

/* raw content handling */

- (NSStringEncoding) fallbackStringEncoding
{
  /*
    iCalendar invitations sent by Outlook 2002 have the annoying bug that the
    mail states an UTF-8 content encoding but the actual iCalendar content is
    encoding in Latin-1 (or Windows Western?).
 
    As a result the content decoding will fail (TODO: always?). In this case we
    try to decode with Latin-1.
 
    Note: we could check for the Outlook x-mailer, but it was considered better
    to try Latin-1 as a fallback in any case (be tolerant).
  */
  return NSISOLatin1StringEncoding;
}

/* accessors */

- (iCalCalendar *) inCalendar
{
  if (!inCalendar)
    {
      inCalendar
	= [iCalCalendar parseSingleFromSource: [self flatContentAsString]];
      [inCalendar retain];
    }

  return inCalendar;
}

- (BOOL) couldParseCalendar
{
  return [[self inCalendar] isNotNull];
}

- (iCalEvent *) inEvent
{
  NSArray *events;
 
  if (inEvent)
    return [inEvent isNotNull] ? inEvent : nil;
 
  events = [[self inCalendar] events];
  if ([events count] > 0) {
    inEvent = [[events objectAtIndex:0] retain];
    return inEvent;
  }
  else {
    inEvent = [[NSNull null] retain];
    return nil;
  }
}

/* formatters */

- (SOGoDateFormatter *) dateFormatter
{
  if (dateFormatter == nil) {
    dateFormatter = [[context activeUser] dateFormatterInContext: context];
    [dateFormatter retain];
  }

  return dateFormatter;
}

/* below is copied from UIxAppointmentView, can we avoid that? */

- (void) setAttendee: (id) _attendee
{
  ASSIGN(attendee, _attendee);
}

- (id) attendee
{
  return attendee;
}

- (NSString *) _personForDisplay: (iCalPerson *) person
{
  NSString *fn, *email, *result;

  fn = [person cnWithoutQuotes];
  email = [person rfc822Email];
  if ([fn length])
    result = [NSString stringWithFormat: @"%@ <%@>",
		       fn, email];
  else
    result = email;

  return result;
}

- (NSString *) attendeeForDisplay
{
  return [self _personForDisplay: attendee];
}

- (void) setItem: (id) _item
{
  ASSIGN(item, _item);
}

- (id) item
{
  return item;
}

- (NSCalendarDate *) startTime
{
  NSCalendarDate *date;
  NSTimeZone *timeZone;
 
  date = [[self authorativeEvent] startDate];
  timeZone = [[context activeUser] timeZone];
  [date setTimeZone: timeZone];

  return date;
}

- (NSCalendarDate *) endTime
{
  NSCalendarDate *date;
  NSTimeZone *timeZone;
 
  date = [[self authorativeEvent] endDate];
  timeZone = [[context activeUser] timeZone];
  [date setTimeZone: timeZone];

  return date;
}

- (BOOL) isEndDateOnSameDay
{
  return [[self startTime] isDateOnSameDay:[self endTime]];
}

- (NSTimeInterval) duration
{
  return [[self endTime] timeIntervalSinceDate:[self startTime]];
}

/* calendar folder support */

- (id) calendarFolder
{
  /* return scheduling calendar of currently logged-in user */
  SOGoUser *user;
  id folder;

  user = [context activeUser];
  folder = [[user homeFolderInContext: context] lookupName: @"Calendar"
						inContext: context
						acquire: NO];

  return [folder lookupName: @"personal" inContext: context acquire: NO];
}

- (id) storedEventObject
{
  /* lookup object in the users Calendar */
  id calendar;
 
  if (storedEventObject)
    return [storedEventObject isNotNull] ? storedEventObject : nil;
 
  calendar = [self calendarFolder];
  if ([calendar isKindOfClass:[NSException class]]) {
    [self errorWithFormat:@"Did not find Calendar folder: %@", calendar];
  }
  else {
    NSString *filename;
 
    filename = [calendar resourceNameForEventUID:[[self inEvent] uid]];
    if (filename) {
      // TODO: When we get an exception, this might be an auth issue meaning
      // that the UID indeed exists but that the user has no access to
      // the object.
      // Of course this is quite unusual for the private calendar though.
      id tmp;
 
      tmp = [calendar lookupName:filename inContext:[self context] acquire:NO];
      if ([tmp isNotNull] && ![tmp isKindOfClass:[NSException class]])
	storedEventObject = [tmp retain];
    }
  }
 
  if (storedEventObject == nil)
    storedEventObject = [[NSNull null] retain];
 
  return storedEventObject;
}

- (BOOL) isEventStoredInCalendar
{
  return [[self storedEventObject] isNotNull];
}

- (iCalEvent *) storedEvent
{
  return (iCalEvent *) [(SOGoAppointmentObject *)[self storedEventObject] component: NO];
}

/* organizer tracking */

- (NSString *) loggedInUserEMail
{
  NSDictionary *identity;

  identity = [[context activeUser] primaryIdentity];

  return [identity objectForKey: @"email"];
}

- (iCalEvent *) authorativeEvent
{
  iCalEvent *authorativeEvent;

  if ([[self storedEvent] compare: [self inEvent]]
      == NSOrderedAscending)
    authorativeEvent = inEvent;
  else
    authorativeEvent = storedEventObject;

  return authorativeEvent;
}

- (BOOL) isLoggedInUserTheOrganizer
{
  iCalPerson *organizer;
 
  organizer = [[self authorativeEvent] organizer];

  return [[context activeUser] hasEmail: [organizer rfc822Email]];
}

- (BOOL) isLoggedInUserAnAttendee
{
  NSString *loginEMail;
 
  if ((loginEMail = [self loggedInUserEMail]) == nil) {
    [self warnWithFormat:@"Could not determine email of logged in user?"];
    return NO;
  }

  return [[self authorativeEvent] isParticipant:loginEMail];
}

/* derived fields */

- (NSString *) organizerDisplayName
{
  iCalPerson *organizer;
  NSString *value;

  organizer = [[self authorativeEvent] organizer];
  if (organizer)
    value = [self _personForDisplay: organizer];
  else
    value = @"[todo: no organizer set, use 'from']";

  return value;
}

/* replies */

- (NGImap4EnvelopeAddress *) replySenderAddress
{
  /* 
     The iMIP reply is the sender of the mail, the 'attendees' are NOT set to
     the actual attendees. BUT the attendee field contains the reply-status!
  */
  id tmp;
 
  tmp = [[self clientObject] fromEnvelopeAddresses];
  if ([tmp count] == 0) return nil;
  return [tmp objectAtIndex:0];
}

- (NSString *) replySenderEMail
{
  return [[self replySenderAddress] email];
}

- (NSString *) replySenderBaseEMail
{
  return [[self replySenderAddress] baseEMail];
}

- (iCalPerson *) inReplyAttendee
{
  NSArray *attendees;
 
  attendees = [[self inEvent] attendees];
  if ([attendees count] == 0)
    return nil;
  if ([attendees count] > 1)
    [self warnWithFormat:@"More than one attendee in REPLY: %@", attendees];
 
  return [attendees objectAtIndex:0];
}

- (iCalPerson *) storedReplyAttendee
{
  /*
    TODO: since an attendee can have multiple email addresses, maybe we
    should translate the email to an internal uid and then retrieve
    all emails addresses for matching the participant.
 
    Note: -findParticipantWithEmail: does not parse the email!
  */
  iCalEvent *e;
  iCalPerson *p;

  p = nil;
 
  e = [self storedEvent];
  if (e)
    {
      p = [e findParticipantWithEmail: [self replySenderBaseEMail]];
      if (!p)
	p = [e findParticipantWithEmail:[self replySenderEMail]];
    }

  return p;
}

- (BOOL) isReplySenderAnAttendee
{
  return [[self storedReplyAttendee] isNotNull];
}

@end /* UIxMailPartICalViewer */
