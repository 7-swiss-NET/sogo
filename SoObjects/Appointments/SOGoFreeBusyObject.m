/*
  Copyright (C) 2007-2011 Inverse inc.
  Copyright (C) 2000-2004 SKYRIX Software AG

  This file is part of SOGo

  SOGo is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  SOGo is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with OGo; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSValue.h>

#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGObjWeb/WOResponse.h>
#import <NGExtensions/NSCalendarDate+misc.h>
#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalFreeBusy.h>
#import <NGCards/iCalPerson.h>

#import <SOGo/SOGoBuild.h>
#import <SOGo/SOGoDomainDefaults.h>
#import <SOGo/SOGoUser.h>
#import <SOGo/SOGoUserDefaults.h>
#import <SOGo/SOGoUserManager.h>
#import <SOGo/SOGoPermissions.h>

#import "SOGoAppointmentFolder.h"
#import "SOGoAppointmentFolders.h"

#import "SOGoFreeBusyObject.h"

@interface SOGoFreeBusyObject (PrivateAPI)
- (NSString *) iCalStringForFreeBusyInfos: (NSArray *) _infos
                                     from: (NSCalendarDate *) _startDate
                                       to: (NSCalendarDate *) _endDate;
@end

@implementation SOGoFreeBusyObject

- (iCalPerson *) iCalPersonWithUID: (NSString *) uid
{
  iCalPerson *person;
  SOGoUserManager *um;
  NSDictionary *contactInfos;

  um = [SOGoUserManager sharedUserManager];
  contactInfos = [um contactInfosForUserWithUIDorEmail: uid];

  /* iCal.app compatibility:
     - don't add "cn"; */
  person = [iCalPerson new];
  [person autorelease];
  [person setEmail: [contactInfos objectForKey: @"c_email"]];

  return person;
}

/* Private API */
- (iCalFreeBusyType) _fbTypeForEventStatus: (int) eventStatus
{
  //unsigned int status;
  iCalFreeBusyType fbType;

  //status = [eventStatus unsignedIntValue];
  if (eventStatus == 0)
    fbType = iCalFBBusyTentative;
  else if (eventStatus == 1)
    fbType = iCalFBBusy;
  else
    fbType = iCalFBFree;

  return fbType;    
}

- (NSString *) iCalStringForFreeBusyInfos: (NSArray *) _infos
			       withMethod: (NSString *) method
                                   andUID: (NSString *) uid
                             andOrganizer: (iCalPerson *) organizer
                                     from: (NSCalendarDate *) _startDate
                                       to: (NSCalendarDate *) _endDate
{
  NSArray *emails, *partstates;
  NSEnumerator *events;
  iCalCalendar *calendar;
  iCalFreeBusy *freebusy;
  NSDictionary *info;
  iCalFreeBusyType type;
  SOGoUser *user;
  NSString *login;
  int i;

  login = [container ownerInContext: context];
  user = [SOGoUser userWithLogin: login];

  calendar = [iCalCalendar groupWithTag: @"vcalendar"];
  [calendar setProdID: [NSString stringWithFormat:
                                   @"-//Inverse inc./SOGo %@//EN",
                                 SOGoVersion]];
  [calendar setVersion: @"2.0"];
  if (method)
    [calendar setMethod: method];

  freebusy = [iCalFreeBusy groupWithTag: @"vfreebusy"];
  if (uid)
    [freebusy setUid: uid];
  if (organizer)
    [freebusy setOrganizer: organizer];
  [freebusy addToAttendees: [self iCalPersonWithUID: login]];
  [freebusy setTimeStampAsDate: [NSCalendarDate calendarDate]];
  [freebusy setStartDate: _startDate];
  [freebusy setEndDate: _endDate];

  /* ORGANIZER - strictly required but missing for now */

  /* ATTENDEE */
//   person = [self iCalPersonWithUid: login];
//   [person setTag: @"ATTENDEE"];
//   [ms appendString: [person versitString]];

  /* FREEBUSY */
  events = [_infos objectEnumerator];
  while ((info = [events nextObject]))
    if ([[info objectForKey: @"c_isopaque"] boolValue])
      {
	type = iCalFBFree;

	// If the event has NO organizer (which means it's the user that has created it) OR
	// If we are the organizer of the event THEN we are automatically busy
	if ([[info objectForKey: @"c_orgmail"] length] == 0 ||
	    [user hasEmail: [info objectForKey: @"c_orgmail"]])
	  {
	    type = iCalFBBusy;
	  }
	else
	  {
	    // We check if the user has accepted/declined or needs action
	    // on the current event.
	    emails = [[info objectForKey: @"c_partmails"] componentsSeparatedByString: @"\n"];

	    for (i = 0; i < [emails count]; i++)
	      {
		if ([user hasEmail: [emails objectAtIndex: i]])
		  {
		    // We now fetch the c_partstates array and get the participation
		    // status of the user for the event
		    partstates = [[info objectForKey: @"c_partstates"] componentsSeparatedByString: @"\n"];
		    
		    if (i < [partstates count])
		      {
			type = [self _fbTypeForEventStatus: [[partstates objectAtIndex: i] intValue]];
		      }
		    break;
		  }
	      }
	  }

	if (type == iCalFBBusy
            || type == iCalFBBusyTentative
            || type == iCalFBBusyUnavailable)
	  [freebusy addFreeBusyFrom: [info objectForKey: @"startDate"]
		    to: [info objectForKey: @"endDate"]
		    type: type];
      }

  [calendar setUniqueChild: freebusy];

  return [calendar versitString];
}

- (NSString *) contentAsString
{
  NSCalendarDate *today, *startDate, *endDate;
  SOGoUserDefaults *ud;
  SOGoDomainDefaults *dd;
  NSArray *interval;
  unsigned int start, end;
  
  today = [[NSCalendarDate calendarDate] beginOfDay];
  ud = [[context activeUser] userDefaults];
  [today setTimeZone: [ud timeZone]];

  dd = [[context activeUser] domainDefaults];
  interval = [dd freeBusyDefaultInterval];
  if ([interval count] > 1)
    {
      start = [[interval objectAtIndex: 0] unsignedIntValue];
      end = [[interval objectAtIndex: 1] unsignedIntValue];
    }
  else
    {
      start = 7;
      end = 7;
    }

  startDate = [today dateByAddingYears: 0 months: 0 days: -start
                     hours: 0 minutes: 0 seconds: 0];
  endDate = [today dateByAddingYears: 0 months: 0 days: end
		   hours: 0 minutes: 0 seconds: 0];

  return [self contentAsStringFrom: startDate to: endDate];
}

- (NSString *) contentAsStringWithMethod: (NSString *) method
                                  andUID: (NSString *) UID
                            andOrganizer: (iCalPerson *) organizer
				    from: (NSCalendarDate *) _startDate
				      to: (NSCalendarDate *) _endDate
{
  NSArray *infos;

  infos = [self fetchFreeBusyInfosFrom: _startDate to: _endDate];

  return [self iCalStringForFreeBusyInfos: infos
                               withMethod: method
                                   andUID: UID andOrganizer: organizer
                                     from: _startDate to: _endDate];
}

- (NSString *) contentAsStringFrom: (NSCalendarDate *) _startDate
				to: (NSCalendarDate *) _endDate
{
  return [self contentAsStringWithMethod: nil andUID: nil
                            andOrganizer: nil
                                    from: _startDate
                                      to: _endDate];
}

- (NSArray *) fetchFreeBusyInfosFrom: (NSCalendarDate *) startDate
                                  to: (NSCalendarDate *) endDate
{
  SOGoAppointmentFolder *calFolder;
//   SoSecurityManager *sm;
  NSArray *folders;
  NSMutableArray *infos;
  unsigned int count, max;

  infos = [NSMutableArray array];

  folders = [[container lookupName: @"Calendar"
			inContext: context
			acquire: NO] subFolders];
  max = [folders count];
  for (count = 0; count < max; count++)
    {
      calFolder = [folders objectAtIndex: count];
      if (![calFolder isSubscription] && [calFolder includeInFreeBusy])
	[infos addObjectsFromArray: [calFolder fetchFreeBusyInfosFrom: startDate
                                                                   to: endDate]];
    }

  return infos;
}

- (NSString *) iCalString
{
  // for UI-X appointment viewer
  return [self contentAsString];
}

/* deliver content without need for view method */

- (id) GETAction: (id)_ctx
{
  WOResponse *r;
  NSData *contentData;

  contentData = [[self contentAsString]
		  dataUsingEncoding: NSUTF8StringEncoding];

  r = [(WOContext *) _ctx response];
  [r setHeader: @"text/calendar" forKey: @"content-type"];
  [r setContent: contentData];
  [r setStatus: 200];

  return r;
}

- (BOOL) isFolderish
{
  return NO;
}

- (NSString *) davContentType
{
  return @"text/calendar";
}

- (NSArray *) aclsForUser: (NSString *) uid
{
  return nil;
}

@end
