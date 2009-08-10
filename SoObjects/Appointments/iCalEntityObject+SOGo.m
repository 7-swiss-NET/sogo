/* iCalEntityObject+SOGo.m - this file is part of SOGo
 *
 * Copyright (C) 2007 Inverse inc.
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
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSTimeZone.h>

#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalDateTime.h>
#import <NGCards/iCalPerson.h>

#import <NGObjWeb/WOApplication.h>
#import <NGObjWeb/WOContext+SoObjects.h>

#import <SoObjects/SOGo/NSArray+Utilities.h>
#import <SoObjects/SOGo/SOGoUser.h>

#import "iCalPerson+SOGo.h"

#import "iCalEntityObject+SOGo.h"

static int utcOffset = -1;

@implementation iCalEntityObject (SOGoExtensions)

static inline int
_computeAllDayOffset()
{
  NSTimeZone *tz;
  SOGoUser *user;
  WOApplication *application;
  int offset;

  if (utcOffset == -1)
    {
      tz = [[NSCalendarDate date] timeZone];
      utcOffset = [tz secondsFromGMT];
    }

  application = [WOApplication application];
  user = [[application context] activeUser];
  offset = utcOffset - [[user timeZone] secondsFromGMT];

  return offset;
}

+ (void) initializeSOGoExtensions;
{
  if (!iCalDistantFuture)
    {
      iCalDistantFuture = [[NSCalendarDate distantFuture] retain];
      /* INT_MAX due to Postgres constraint */
      iCalDistantFutureNumber = [[NSNumber numberWithUnsignedInt: INT_MAX] retain];
    }
}

- (BOOL) userIsParticipant: (SOGoUser *) user
{
  NSEnumerator *participants;
  iCalPerson *currentParticipant;
  BOOL isParticipant;

  isParticipant = NO;

  participants = [[self participants] objectEnumerator];
  currentParticipant = [participants nextObject];
  while (!isParticipant
	 && currentParticipant)
    if ([user hasEmail: [currentParticipant rfc822Email]])
      isParticipant = YES;
    else
      currentParticipant = [participants nextObject];

  return isParticipant;
}

- (iCalPerson *) userAsParticipant: (SOGoUser *) user
{
  NSEnumerator *participants;
  iCalPerson *currentParticipant, *userParticipant;

  userParticipant = nil;

  participants = [[self participants] objectEnumerator];
  while (!userParticipant
	 && (currentParticipant = [participants nextObject]))
    if ([user hasEmail: [currentParticipant rfc822Email]])
      userParticipant = currentParticipant;

  return userParticipant;
}

- (BOOL) userIsOrganizer: (SOGoUser *) user
{
  NSString *mail;
  BOOL b;

  mail = [[self organizer] rfc822Email];
  b = [user hasEmail: mail];
  if (b) return YES;

  // We check for the SENT-BY
  mail = [[self organizer] sentBy];

  if ([mail length])
    return [user hasEmail: mail];
  
  return NO;
}

- (NSArray *) attendeeUIDs
{
  NSEnumerator *attendees;
  NSString *uid;
  iCalPerson *currentAttendee;
  NSMutableArray *uids;

  uids = [NSMutableArray array];

  attendees = [[self attendees] objectEnumerator];
  while ((currentAttendee = [attendees nextObject]))
    {
      uid = [currentAttendee uid];
      if (uid)
	[uids addObject: uid];
    }

  return uids;
}

#warning this method should be implemented in a category of iCalToDo
- (BOOL) isStillRelevant
{
  [self subclassResponsibility: _cmd];
  return NO;
}

- (id) itipEntryWithMethod: (NSString *) method
{
  iCalCalendar *newCalendar;
  iCalEntityObject *currentEvent, *newEntry;
  iCalPerson *organizer;

  NSArray *events;
  int i, count;
  
  newCalendar = [parent mutableCopy];
  [newCalendar autorelease];
  [newCalendar setMethod: method];
  
  events = [newCalendar childrenWithTag: tag];
  count = [events count];
  if (count > 1)
    {
      // If the event is recurrent, remove all occurences
      organizer = [[(iCalEntityObject *)[newCalendar firstChildWithTag: tag] organizer] mutableCopy];
      for (i = 0; i < count; i++)
	{
	  currentEvent = [events objectAtIndex: i];
	  [[newCalendar children] removeObject: currentEvent];
	}
      newEntry = [[self mutableCopy] autorelease];
      [newEntry setOrganizer: organizer];
      [newCalendar addChild: newEntry];
    }
  else
    newEntry = (iCalEntityObject *) [newCalendar firstChildWithTag: tag];

  return newEntry;
}

- (NSArray *) attendeesWithoutUser: (SOGoUser *) user
{
  NSMutableArray *newAttendees;
  NSArray *oldAttendees;
  unsigned int count, max;
  iCalPerson *currentAttendee;
  NSString *userID;

  userID = [user login];
  oldAttendees = [self attendees];
  max = [oldAttendees count];
  newAttendees = [NSMutableArray arrayWithCapacity: max];
  for (count = 0; count < max; count++)
    {
      currentAttendee = [oldAttendees objectAtIndex: count];
      if (![[currentAttendee uid] isEqualToString: userID])
	[newAttendees addObject: currentAttendee];
    }

  return newAttendees;
}

- (NSNumber *) quickRecordDateAsNumber: (NSCalendarDate *) _date
			    withOffset: (int) offset
			     forAllDay: (BOOL) allDay
{
  NSTimeInterval seconds;
  NSNumber *dateNumber;

  if (_date == iCalDistantFuture)
    dateNumber = iCalDistantFutureNumber;
  else
    {
      seconds = [_date timeIntervalSince1970] + offset;
      if (allDay)
	seconds += _computeAllDayOffset ();

      dateNumber = [NSNumber numberWithInt: seconds];
    }

  return dateNumber;
}

- (NSMutableDictionary *) quickRecord
{
  [self subclassResponsibility: _cmd];

  return nil;
}

- (int) priorityNumber
{
  NSString *prio;
  NSRange r;
  int priorityNumber;

  prio = [self priority];
  if (prio)
    {
      r = [prio rangeOfString: @";"];
      if (r.length)
	prio = [prio substringToIndex:r.location];
      priorityNumber = [prio intValue];
    }
  else
    priorityNumber = 0;

  return priorityNumber;
}

@end
