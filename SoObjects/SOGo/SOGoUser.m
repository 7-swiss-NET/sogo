/*
  Copyright (C) 2005 SKYRIX Software AG

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
#import <Foundation/NSNull.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSUserDefaults.h>
#import <NGObjWeb/WOApplication.h>
#import <NGObjWeb/SoObject.h>
#import <NGExtensions/NSNull+misc.h>

#import "AgenorUserDefaults.h"
#import "LDAPUserManager.h"
#import "SOGoContentObject.h"
#import "SOGoUser.h"
#import "SOGoPermissions.h"

static NSTimeZone *serverTimeZone = nil;
static NSString *fallbackIMAP4Server = nil;
static NSURL *AgenorProfileURL = nil;

@interface NSObject (SOGoRoles)

- (NSArray *) rolesOfUser: (NSString *) uid;

@end

@implementation SOGoUser

+ (void) initialize
{
  NSString *tzName;
  NSUserDefaults *ud;
  NSString *profileURL;

  ud = [NSUserDefaults standardUserDefaults];
  if (!serverTimeZone)
    {
      tzName = [ud stringForKey: @"SOGoServerTimeZone"];
      if (!tzName)
        tzName = @"Canada/Eastern";
      serverTimeZone = [NSTimeZone timeZoneWithName: tzName];
      [serverTimeZone retain];
    }
  if (!AgenorProfileURL)
    {
      profileURL = [ud stringForKey: @"AgenorProfileURL"];
      AgenorProfileURL = [[NSURL alloc] initWithString: profileURL];
    }
  if (!fallbackIMAP4Server)
    ASSIGN (fallbackIMAP4Server, [ud stringForKey: @"SOGoFallbackIMAP4Server"]);
}

+ (SOGoUser *) userWithLogin: (NSString *) newLogin
		       roles: (NSArray *) newRoles
{
  SOGoUser *user;

  user = [[self alloc] initWithLogin: newLogin roles: newRoles];
  [user autorelease];

  return user;
}

- (id) init
{
  if ((self = [super init]))
    {
      userDefaults = nil;
      userSettings = nil;
      allEmails = nil;
    }

  return self;
}

- (id) initWithLogin: (NSString *) newLogin
	       roles: (NSArray *) newRoles
{
  LDAPUserManager *um;
  NSDictionary *user;

  if ([newLogin isEqualToString: @"anonymous"]
      || [newLogin isEqualToString: @"freebusy"])
    self = [super initWithLogin: newLogin roles: newRoles];
  else
    {
      um = [LDAPUserManager sharedUserManager];
      user = [um contactInfosForUserWithUIDorEmail: newLogin];
      self = [super initWithLogin: [user objectForKey: @"c_uid"]
		    roles: newRoles];
    }

  return self;
}

- (void) dealloc
{
  [userDefaults release];
  [userSettings release];
  [super dealloc];
}

- (id) _fetchFieldForUser: (NSString *) field
{
  NSDictionary *contactInfos;
  LDAPUserManager *um;

  um = [LDAPUserManager sharedUserManager];
  contactInfos = [um contactInfosForUserWithUIDorEmail: login];

  return [contactInfos objectForKey: field];
}

- (void) _fetchAllEmails
{
  allEmails = [self _fetchFieldForUser: @"emails"];
  [allEmails retain];
}

- (void) _fetchCN
{
  cn = [self _fetchFieldForUser: @"cn"];
  [cn retain];
}

/* properties */

- (NSString *) primaryEmail
{
  if (!allEmails)
    [self _fetchAllEmails];

  return [allEmails objectAtIndex: 0];
}

- (NSString *) systemEmail
{
  if (!allEmails)
    [self _fetchAllEmails];

  return [allEmails lastObject];
}

- (NSArray *) allEmails
{
  if (!allEmails)
    [self _fetchAllEmails];

  return allEmails;  
}

- (BOOL) hasEmail: (NSString *) email
{
  BOOL hasEmail;
  NSString *currentEmail, *cmpEmail;
  NSEnumerator *emails;

  hasEmail = NO;
  if (!allEmails)
    [self _fetchAllEmails];
  cmpEmail = [email lowercaseString];
  emails = [allEmails objectEnumerator];
  currentEmail = [emails nextObject];
  while (currentEmail && !hasEmail)
    if ([[currentEmail lowercaseString] isEqualToString: cmpEmail])
      hasEmail = YES;
    else
      currentEmail = [emails nextObject];

  return hasEmail;
}

- (NSString *) cn
{
  if (!cn)
    [self _fetchCN];

  return cn;
}

- (NSString *) primaryIMAP4AccountString
{
  return [NSString stringWithFormat: @"%@@%@", login, fallbackIMAP4Server];
}

// - (NSString *) primaryMailServer
// {
//   return [[self userManager] getServerForUID: [self login]];
// }

// - (NSArray *) additionalIMAP4AccountStrings
// {
//   return [[self userManager]getSharedMailboxAccountStringsForUID: [self login]];
// }

// - (NSArray *) additionalEMailAddresses
// {
//   return [[self userManager] getSharedMailboxEMailsForUID: [self login]];
// }

// - (NSDictionary *) additionalIMAP4AccountsAndEMails
// {
//   return [[self userManager] getSharedMailboxesAndEMailsForUID: [self login]];
// }

- (NSURL *) freeBusyURL
{
  return nil;
}

/* defaults */

- (NSUserDefaults *) userDefaults
{
  if (!userDefaults)
    userDefaults = [[AgenorUserDefaults alloc] initWithTableURL: AgenorProfileURL
					       uid: login
					       fieldName: @"defaults"];

  return userDefaults;
}

- (NSUserDefaults *) userSettings
{
  if (!userSettings)
    userSettings = [[AgenorUserDefaults alloc] initWithTableURL: AgenorProfileURL
					       uid: login
					       fieldName: @"settings"];

  return userSettings;
}

- (NSTimeZone *) timeZone
{
  NSString *timeZoneName;

  if (!userTimeZone)
    {
      timeZoneName = [[self userDefaults] stringForKey: @"TimeZone"];
      if ([timeZoneName length] > 0)
	userTimeZone = [NSTimeZone timeZoneWithName: timeZoneName];
      if (!userTimeZone)
	userTimeZone = serverTimeZone;
      [userTimeZone retain];
    }

  return userTimeZone;
}

- (NSTimeZone *) serverTimeZone
{
  return serverTimeZone;
}

/* folders */

// TODO: those methods should check whether the traversal stack in the context
//       already contains proper folders to improve caching behaviour

- (id) homeFolderInContext: (id) _ctx
{
  /* Note: watch out for cyclic references */
  // TODO: maybe we should add an [activeUser reset] method to SOPE
  id folder;
  
  folder = [(WOContext *)_ctx objectForKey:@"ActiveUserHomeFolder"];
  if (folder != nil)
    return [folder isNotNull] ? folder : nil;
  
  folder = [[WOApplication application] lookupName:[self login]
					inContext:_ctx acquire:NO];
  if ([folder isKindOfClass:[NSException class]])
    return folder;
  
  [(WOContext *)_ctx setObject:folder ? folder : [NSNull null] 
                forKey: @"ActiveUserHomeFolder"];
  return folder;
}

// - (id) schedulingCalendarInContext: (id) _ctx
// {
//   /* Note: watch out for cyclic references */
//   id folder;

//   folder = [(WOContext *)_ctx objectForKey:@"ActiveUserCalendar"];
//   if (folder != nil)
//     return [folder isNotNull] ? folder : nil;

//   folder = [self homeFolderInContext:_ctx];
//   if ([folder isKindOfClass:[NSException class]])
//     return folder;
  
//   folder = [folder lookupName:@"Calendar" inContext:_ctx acquire:NO];
//   if ([folder isKindOfClass:[NSException class]])
//     return folder;
  
//   [(WOContext *)_ctx setObject:folder ? folder : [NSNull null] 
//                 forKey:@"ActiveUserCalendar"];
//   return folder;
// }

- (NSArray *) rolesForObject: (NSObject *) object
                   inContext: (WOContext *) context
{
  NSMutableArray *rolesForObject;
  NSArray *sogoRoles;

  rolesForObject = [NSMutableArray new];
  [rolesForObject autorelease];

  sogoRoles = [super rolesForObject: object inContext: context];
  if (sogoRoles)
    [rolesForObject addObjectsFromArray: sogoRoles];

  if ([[object ownerInContext: context] isEqualToString: [self login]])
    [rolesForObject addObject: SoRole_Owner];
  if ([object isKindOfClass: [SOGoObject class]])
    {
      sogoRoles = [(SOGoObject *) object aclsForUser: login];
      if (sogoRoles)
        [rolesForObject addObjectsFromArray: sogoRoles];
    }

  return rolesForObject;
}

@end /* SOGoUser */
