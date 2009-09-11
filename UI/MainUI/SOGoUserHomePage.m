/* SOGoUserHomePage.m - this file is part of SOGo
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

#import <Foundation/NSArray.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>
#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/WOCookie.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/WOResponse.h>
#import <NGExtensions/NSCalendarDate+misc.h>
#import <NGExtensions/NSObject+Logs.h>

#import <Appointments/SOGoFreeBusyObject.h>
#import <SoObjects/SOGo/LDAPUserManager.h>
#import <SoObjects/SOGo/SOGoWebAuthenticator.h>
#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/SOGo/SOGoUserFolder.h>
#import <SoObjects/SOGo/NSCalendarDate+SOGo.h>
#import <SoObjects/SOGo/NSDictionary+Utilities.h>
#import <SOGoUI/UIxComponent.h>

#define intervalSeconds 900 /* 15 minutes */

static NSString *defaultModule = nil;
static NSString *LDAPContactInfoAttribute = nil;

@interface SOGoUserHomePage : UIxComponent

@end

@implementation SOGoUserHomePage

+ (void) initialize
{
  NSUserDefaults *ud;

  if (!defaultModule)
    {
      ud = [NSUserDefaults standardUserDefaults];

      defaultModule = [ud stringForKey: @"SOGoUIxDefaultModule"];
      if (defaultModule)
        {
          if (!([defaultModule isEqualToString: @"Calendar"]
             || [defaultModule isEqualToString: @"Contacts"]
             || [defaultModule isEqualToString: @"Mail"]))
            {
              [self logWithFormat: @"default module '%@' not accepted (must be"
                @"'Calendar', 'Contacts' or 'Mail')", defaultModule];
              defaultModule = @"Calendar";
            }
        }
      else
        defaultModule = @"Calendar";
      [self logWithFormat: @"default module set to '%@'", defaultModule];
      [defaultModule retain];

      LDAPContactInfoAttribute = [ud stringForKey: @"SOGoLDAPContactInfoAttribute"];
      [LDAPContactInfoAttribute retain];
    }
}

- (id <WOActionResults>) defaultAction
{
  SOGoUserFolder *co;
  NSUserDefaults *ud;
  NSString *userDefinedModule;
  NSURL *moduleURL;

  ud = [[context activeUser] userDefaults];
  userDefinedModule = [ud stringForKey: @"SOGoUIxDefaultModule"];
  if (userDefinedModule)
    {
      if ([userDefinedModule isEqualToString: @"Last"])
        userDefinedModule = [ud stringForKey: @"SOGoUIxLastModule"];
    }
  if (!userDefinedModule)
    userDefinedModule = defaultModule;

  co = [self clientObject];
  moduleURL = [NSURL URLWithString: userDefinedModule
		     relativeToURL: [co soURL]];

  return [self redirectToLocation: [moduleURL absoluteString]];
}

- (void) _fillFreeBusyItems: (unsigned int *) items
		      count: (unsigned int) itemCount
                withRecords: (NSArray *) records
              fromStartDate: (NSCalendarDate *) startDate
                  toEndDate: (NSCalendarDate *) endDate
{
  NSArray *emails, *partstates;
  NSCalendarDate *currentDate;
  NSDictionary *record;
  SOGoUser *user;

  int recordCount, recordMax, count, startInterval, endInterval, i, type;

  recordMax = [records count];
  user = [SOGoUser userWithLogin: [[self clientObject] ownerInContext: context]
		     roles: nil];

  for (recordCount = 0; recordCount < recordMax; recordCount++)
    {
      record = [records objectAtIndex: recordCount];
      if ([[record objectForKey: @"c_isopaque"] boolValue])
	{
	type = 0;

	// If the event has NO organizer (which means it's the user that has created it) OR
	// If we are the organizer of the event THEN we are automatically busy
	if ([[record objectForKey: @"c_orgmail"] length] == 0 ||
	    [user hasEmail: [record objectForKey: @"c_orgmail"]])
	  {
	    type = 1;
	  }
	else
	  {
	    // We check if the user has accepted/declined or needs action
	    // on the current event.
	    emails = [[record objectForKey: @"c_partmails"] componentsSeparatedByString: @"\n"];

	    for (i = 0; i < [emails count]; i++)
	      {
		if ([user hasEmail: [emails objectAtIndex: i]])
		  {
		    // We now fetch the c_partstates array and get the participation
		    // status of the user for the event
		    partstates = [[record objectForKey: @"c_partstates"] componentsSeparatedByString: @"\n"];
		    
		    if (i < [partstates count])
		      {
			type = ([[partstates objectAtIndex: i] intValue] < 2 ? 1 : 0);
		      }
		    break;
		  }
	      }
	  }

	  currentDate = [record objectForKey: @"startDate"];
	  if ([currentDate earlierDate: startDate] == currentDate)
	    startInterval = 0;
	  else
	    startInterval = ([currentDate timeIntervalSinceDate: startDate]
			     / intervalSeconds);

	  currentDate = [record objectForKey: @"endDate"];
	  if ([currentDate earlierDate: endDate] == endDate)
	    endInterval = itemCount - 1;
	  else
	    endInterval = ([currentDate timeIntervalSinceDate: startDate]
			   / intervalSeconds);

	  if (type == 1)
	    for (count = startInterval; count < endInterval; count++)
	      *(items + count) = 1;
	}
    }
}

- (NSString *) _freeBusyAsTextFromStartDate: (NSCalendarDate *) startDate
                                  toEndDate: (NSCalendarDate *) endDate
                                forFreeBusy: (SOGoFreeBusyObject *) fb
{
  NSMutableString *response;
  unsigned int *freeBusyItems;
  NSTimeInterval interval;
  unsigned int count, intervals;

  interval = [endDate timeIntervalSinceDate: startDate] + 60;
  intervals = interval / intervalSeconds; /* slices of 15 minutes */
  freeBusyItems = NSZoneCalloc (NULL, intervals, sizeof (int));
  [self _fillFreeBusyItems: freeBusyItems count: intervals
	withRecords: [fb fetchFreeBusyInfosFrom: startDate to: endDate]
        fromStartDate: startDate toEndDate: endDate];

  response = [NSMutableString string];
  for (count = 0; count < intervals; count++)
    [response appendFormat: @"%d,", *(freeBusyItems + count)];
  [response deleteCharactersInRange: NSMakeRange (intervals * 2 - 1, 1)];
  NSZoneFree (NULL, freeBusyItems);

  return response;
}

- (NSString *) _freeBusyAsText
{
  SOGoFreeBusyObject *co;
  NSCalendarDate *startDate, *endDate;
  NSString *queryDay, *additionalDays;
  NSTimeZone *uTZ;
  SOGoUser *user;

  co = [self clientObject];
  user = [context activeUser];
  uTZ = [user timeZone];

  queryDay = [self queryParameterForKey: @"sday"];
  if ([queryDay length])
    startDate = [NSCalendarDate dateFromShortDateString: queryDay
                                andShortTimeString: @"0000"
                                inTimeZone: uTZ];
  else
    {
      startDate = [NSCalendarDate calendarDate];
      [startDate setTimeZone: uTZ];
      startDate = [startDate hour: 0 minute: 0];
    }

  queryDay = [self queryParameterForKey: @"eday"];
  if ([queryDay length])
    endDate = [NSCalendarDate dateFromShortDateString: queryDay
                              andShortTimeString: @"2359"
                              inTimeZone: uTZ];
  else
    endDate = [startDate hour: 23 minute: 59];

  additionalDays = [self queryParameterForKey: @"additional"];
  if ([additionalDays length] > 0)
    endDate = [endDate dateByAddingYears: 0 months: 0
                       days: [additionalDays intValue]
                       hours: 0 minutes: 0 seconds: 0];

  return [self _freeBusyAsTextFromStartDate: startDate toEndDate: endDate
               forFreeBusy: co];
}

- (id <WOActionResults>) readFreeBusyAction
{
  WOResponse *response;

  response = [self responseWithStatus: 200];
//   [response setHeader: @"text/plain; charset=iso-8859-1"
//             forKey: @"Content-Type"];
  [response appendContentString: [self _freeBusyAsText]];

  return response;
}

- (id <WOActionResults>) logoffAction
{
  WOResponse *response;
  WOCookie *cookie;
  SOGoWebAuthenticator *auth;
  id container;
  NSCalendarDate *date;
  NSString *userName, *cookieName;

  container = [[self clientObject] container];

  userName = [[context activeUser] login];
  [self logWithFormat: @"user '%@' logged off", userName];

  response = [context response];
  [response setStatus: 302];
  [response setHeader: [container baseURLInContext: context]
	    forKey: @"location"];

  date = [NSCalendarDate calendarDate];
  [date setTimeZone: [NSTimeZone timeZoneWithAbbreviation: @"GMT"]];

  auth = [[self clientObject] authenticatorInContext: context];
  if ([auth respondsToSelector: @selector (cookieNameInContext:)])
    cookieName = [auth cookieNameInContext: context];
  else
    cookieName = nil;
  if (cookieName)
    {
      cookie = [WOCookie cookieWithName: cookieName value: @"discard"];
      [cookie setPath: @"/"];
      [cookie setExpires: [date yesterday]];
      [response addCookie: cookie];
    }

  [response setHeader: [date rfc822DateString] forKey: @"Last-Modified"];
  [response setHeader: @"no-store, no-cache, must-revalidate."
            @" max-age=0, post-check=0, pre-check=0"
               forKey: @"Cache-Control"];
  [response setHeader: @"no-cache" forKey: @"Pragma"];

  return response;
}

- (WOResponse *) _usersResponseForResults: (NSArray *) users
{
  WOResponse *response;
  NSString *uid;
  NSMutableString *responseString;
  NSDictionary *contact;
  NSString *contactInfo, *login;
  NSArray *allUsers;
  int i;

  login = [[context activeUser] login];
  response = [context response];
  [response setStatus: 200];
  [response setHeader: @"text/plain; charset=utf-8"
	    forKey: @"Content-Type"];

  responseString = [NSMutableString new];

  // We sort our array - this is pretty useful for the Web
  // interface of SOGo.
  allUsers = [users
	       sortedArrayUsingSelector: @selector (caseInsensitiveDisplayNameCompare:)];

  for (i = 0; i < [allUsers count]; i++)
    {
      contact = [allUsers objectAtIndex: i];
      uid = [contact objectForKey: @"c_uid"];
      if (![uid isEqualToString: login])
        {
          if ([LDAPContactInfoAttribute length])
            {
              contactInfo = [contact objectForKey: LDAPContactInfoAttribute];
              if (!contactInfo)
                contactInfo = @"";
            }
          else
            contactInfo = @"";
          [responseString appendFormat: @"%@:%@:%@:%@\n", uid,
                 [contact objectForKey: @"cn"],
                 [contact objectForKey: @"c_email"],
                          contactInfo];
        }
    }
  [response appendContentString: responseString];
  [responseString release];

  return response;
}

- (id <WOActionResults>) usersSearchAction
{
  NSString *contact;
  id <WOActionResults> result;
  LDAPUserManager *um;

  um = [LDAPUserManager sharedUserManager];
  contact = [self queryParameterForKey: @"search"];
  if ([contact length])
    {
      result
        = [self _usersResponseForResults: [um fetchUsersMatching: contact]];
    }
  else
    result = [NSException exceptionWithHTTPStatus: 400
                          reason: @"missing 'search' parameter"];

  return result;
}

- (WOResponse *) _foldersResponseForResults: (NSArray *) folders
{
  WOResponse *response;
  NSEnumerator *foldersEnum;
  NSDictionary *currentFolder;

  response = [context response];
  [response setStatus: 200];
  [response setHeader: @"text/plain; charset=utf-8"
	    forKey: @"Content-Type"];
  foldersEnum = [folders objectEnumerator];
  while ((currentFolder = [foldersEnum nextObject]))
    [response appendContentString:
		[currentFolder keysWithFormat: @";%{displayName}:%{name}:%{type}"]];

  return response;
}

- (id <WOActionResults>) foldersSearchAction
{
  NSString *folderType;
  NSArray *folders;
  id <WOActionResults> result;
  SOGoUserFolder *userFolder;

  folderType = [self queryParameterForKey: @"type"];
  userFolder = [self clientObject];
  folders
    = [userFolder foldersOfType: folderType
			 forUID: [userFolder ownerInContext: context]];
  result = [self _foldersResponseForResults: folders];
  
  return result;
}

@end
