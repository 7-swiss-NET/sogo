/* LDAPUserManager.m - this file is part of SOGo
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
#import <Foundation/NSDictionary.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>
#import <NGExtensions/NSObject+Logs.h>

#import "NSArray+Utilities.h"
#import "LDAPSource.h"
#import "LDAPUserManager.h"
#import "SOGoCache.h"

static NSString *defaultMailDomain = nil;
static NSString *LDAPContactInfoAttribute = nil;
static BOOL defaultMailDomainIsConfigured = NO;
static BOOL forceImapLoginWithEmail = NO;

#if defined(THREADSAFE)
static NSLock *lock = nil;
#endif

@implementation LDAPUserManager

+ (void) initialize
{
  NSUserDefaults *ud;

  ud = [NSUserDefaults standardUserDefaults];
  if (!defaultMailDomain)
    {
      defaultMailDomain = [ud stringForKey: @"SOGoDefaultMailDomain"];
      [defaultMailDomain retain];
      defaultMailDomainIsConfigured = YES;

      if (!defaultMailDomain)
	{
	  [self warnWithFormat:
		  @"no domain specified for SOGoDefaultMailDomain,"
		@" value set to 'localhost'"];
	  defaultMailDomain = @"localhost";
	}

      LDAPContactInfoAttribute = [ud stringForKey: @"SOGoLDAPContactInfoAttribute"];
      [LDAPContactInfoAttribute retain];
    }
  if (!forceImapLoginWithEmail)
    forceImapLoginWithEmail = [ud boolForKey: @"SOGoForceIMAPLoginWithEmail"];
#if defined(THREADSAFE)
  lock = [NSLock new];
#endif
}

+ (BOOL) defaultMailDomainIsConfigured
{
  return defaultMailDomainIsConfigured;
}

+ (id) sharedUserManager
{
  static id sharedUserManager = nil;

#if defined(THREADSAFE)
  [lock lock];
#endif
  if (!sharedUserManager)
    sharedUserManager = [self new];
#if defined(THREADSAFE)
  [lock unlock];
#endif

  return sharedUserManager;
}

- (void) _registerSource: (NSDictionary *) udSource
{
  NSMutableDictionary *metadata;
  LDAPSource *ldapSource;
  NSString *sourceID, *value;
  
  sourceID = [udSource objectForKey: @"id"];
  ldapSource = [LDAPSource sourceFromUDSource: udSource];
  if (sourceID)
    [sources setObject: ldapSource forKey: sourceID];
  else
    [self errorWithFormat: @"id field missing in a LDAP source,"
	  @" check the SOGoLDAPSources defaults"];
  metadata = [NSMutableDictionary dictionary];
  value = [udSource objectForKey: @"canAuthenticate"];
  if (value)
    [metadata setObject: value forKey: @"canAuthenticate"];
  value = [udSource objectForKey: @"isAddressBook"];
  if (value)
    [metadata setObject: value forKey: @"isAddressBook"];
  value = [udSource objectForKey: @"displayName"];
  if (value)
    [metadata setObject: value forKey: @"displayName"];
  value = [udSource objectForKey: @"MailFieldNames"];
  if (value)
    [metadata setObject: value forKey: @"MailFieldNames"];
  [sourcesMetadata setObject: metadata forKey: sourceID];
}

- (void) _prepareLDAPSourcesWithDefaults: (NSUserDefaults *) ud
{
  id udSources;
  unsigned int count, max;

  sources = [NSMutableDictionary new];
  sourcesMetadata = [NSMutableDictionary new];

  udSources = [ud arrayForKey: @"SOGoLDAPSources"];
  
  if (udSources && [udSources isKindOfClass: [NSArray class]])
    {
      max = [udSources count];
      for (count = 0; count < max; count++)
	[self _registerSource: [udSources objectAtIndex: count]];
    } 
  else
    [self errorWithFormat: @"SOGoLDAPSources is not defined or it is not an array. Check your defaults."];
}

- (id) init
{
  NSUserDefaults *ud;

  if ((self = [super init]))
    {
      ud = [NSUserDefaults standardUserDefaults];

      sources = nil;
      sourcesMetadata = nil;
      [self _prepareLDAPSourcesWithDefaults: ud];
    }

  return self;
}

- (void) dealloc
{
  [sources release];
  [sourcesMetadata release];
  [super dealloc];
}

- (NSArray *) sourceIDs
{
  return [sources allKeys];
}

- (NSArray *) _sourcesOfType: (NSString *) sourceType
{
  NSMutableArray *sourceIDs;
  NSEnumerator *allIDs;
  NSString *currentID;
  NSNumber *canAuthenticate;

  sourceIDs = [NSMutableArray array];
  allIDs = [[sources allKeys] objectEnumerator];
  while ((currentID = [allIDs nextObject])) 
    {
      canAuthenticate = [[sourcesMetadata objectForKey: currentID]
			  objectForKey: sourceType];
      if ([canAuthenticate boolValue])
	[sourceIDs addObject: currentID];
    }

  return sourceIDs;
}

- (NSDictionary *) metadataForSourceID: (NSString *) sourceID
{
  return [sourcesMetadata objectForKey: sourceID];
}

- (NSArray *) authenticationSourceIDs
{
  return [self _sourcesOfType: @"canAuthenticate"];
}

- (NSArray *) addressBookSourceIDs
{
  return [self _sourcesOfType: @"isAddressBook"];
}

- (LDAPSource *) sourceWithID: (NSString *) sourceID
{
  return [sources objectForKey: sourceID];
}

- (NSString *) displayNameForSourceWithID: (NSString *) sourceID
{
  NSDictionary *metadata;

  metadata = [sourcesMetadata objectForKey: sourceID];

  return [metadata objectForKey: @"displayName"];
}

- (NSString *) getCNForUID: (NSString *) uid
{
  NSDictionary *contactInfos;

//   NSLog (@"getCNForUID: %@", uid);
  contactInfos = [self contactInfosForUserWithUIDorEmail: uid];

  return [contactInfos objectForKey: @"cn"];
}

- (NSString *) getEmailForUID: (NSString *) uid
{
  NSDictionary *contactInfos;

//   NSLog (@"getEmailForUID: %@", uid);
  contactInfos = [self contactInfosForUserWithUIDorEmail: uid];

  return [contactInfos objectForKey: @"c_email"];
}

- (NSString *) getFullEmailForUID: (NSString *) uid
{
  NSDictionary *contactInfos;

  contactInfos = [self contactInfosForUserWithUIDorEmail: uid];

  return [NSString stringWithFormat: @"%@ <%@>",
		   [contactInfos objectForKey: @"cn"],
		   [contactInfos objectForKey: @"c_email"]];
}

- (NSString *) getImapLoginForUID: (NSString *) uid
{
  return ((forceImapLoginWithEmail) ? [self getEmailForUID: uid] : uid);
}

- (NSString *) getUIDForEmail: (NSString *) email
{
  NSDictionary *contactInfos;

//   NSLog (@"getUIDForEmail: %@", email);
  contactInfos = [self contactInfosForUserWithUIDorEmail: email];

  return [contactInfos objectForKey: @"c_uid"];
}

- (BOOL) _ldapCheckLogin: (NSString *) login
	     andPassword: (NSString *) password
{ 
  BOOL checkOK;
  LDAPSource *ldapSource;
  NSEnumerator *authIDs;
  NSString *currentID;

  checkOK = NO;

  authIDs = [[self authenticationSourceIDs] objectEnumerator];
  while (!checkOK && (currentID = [authIDs nextObject]))
    {
      ldapSource = [sources objectForKey: currentID];
      checkOK = [ldapSource checkLogin: login andPassword: password];
    }

  return checkOK;
}

- (BOOL) checkLogin: (NSString *) login
	andPassword: (NSString *) password
{
  NSMutableDictionary *currentUser;
  NSString *dictPassword;
  BOOL checkOK;

#if defined(THREADSAFE)
  [lock lock];
#endif

  currentUser = [[SOGoCache sharedCache] userAttributesForLogin: login];
  dictPassword = [currentUser objectForKey: @"password"];
  if (currentUser && dictPassword)
    checkOK = ([dictPassword isEqualToString: password]);
  else if ([self _ldapCheckLogin: login andPassword: password])
    {
      checkOK = YES;
      if (!currentUser)
	{
	  currentUser = [NSMutableDictionary dictionary];
	  [[SOGoCache sharedCache] cacheAttributes: currentUser  forLogin: login];
	}
      [currentUser setObject: password forKey: @"password"];
    }
  else
    checkOK = NO;

#if defined(THREADSAFE)
  [lock unlock];
#endif

  return checkOK;
}

- (void) _fillContactMailRecords: (NSMutableDictionary *) contact
{
  NSMutableArray *emails;
  NSString *uid, *systemEmail;

  emails = [contact objectForKey: @"emails"];
  uid = [contact objectForKey: @"c_uid"];
  systemEmail = [NSString stringWithFormat: @"%@@%@", uid, defaultMailDomain];
  [emails addObjectUniquely: systemEmail];
  [contact setObject: [emails objectAtIndex: 0] forKey: @"c_email"];
}

- (void) _fillContactInfosForUser: (NSMutableDictionary *) currentUser
		   withUIDorEmail: (NSString *) uid
{
  NSMutableArray *emails;
  NSDictionary *userEntry;
  NSEnumerator *ldapSources;
  LDAPSource *currentSource;
  NSString *sourceID, *cn, *c_uid;
  NSArray *c_emails;
  BOOL access;

  emails = [NSMutableArray array];
  cn = nil;
  c_uid = nil;

  [currentUser setObject: [NSNumber numberWithBool: YES]
	       forKey: @"CalendarAccess"];
  [currentUser setObject: [NSNumber numberWithBool: YES]
	       forKey: @"MailAccess"];

  ldapSources = [[self authenticationSourceIDs] objectEnumerator];
  while ((sourceID = [ldapSources nextObject]))
    {
      currentSource = [sources objectForKey: sourceID];
      userEntry = [currentSource lookupContactEntryWithUIDorEmail: uid];
      if (userEntry)
	{
	  if (!cn)
	    cn = [userEntry objectForKey: @"c_cn"];
	  if (!c_uid)
	    c_uid = [userEntry objectForKey: @"c_uid"];
	  c_emails = [userEntry objectForKey: @"c_emails"];
	  if ([c_emails count])
	    [emails addObjectsFromArray: c_emails];
	  access = [[userEntry objectForKey: @"CalendarAccess"] boolValue];
	  if (!access)
	    [currentUser setObject: [NSNumber numberWithBool: NO]
			 forKey: @"CalendarAccess"];
	  access = [[userEntry objectForKey: @"MailAccess"] boolValue];
	  if (!access)
	    [currentUser setObject: [NSNumber numberWithBool: NO]
			 forKey: @"MailAccess"];
	}
    }

  if (!cn)
    cn = @"";
  if (!c_uid)
    c_uid = @"";

  [currentUser setObject: emails forKey: @"emails"];
  [currentUser setObject: cn forKey: @"cn"];
  [currentUser setObject: c_uid forKey: @"c_uid"];

  // If our LDAP queries gave us nothing, we add at least one default
  // email address based on the default domain.
  [self _fillContactMailRecords: currentUser];
}

//
// We cache here all identities, including those
// associated with email addresses.
//
- (void) _retainUser: (NSDictionary *) newUser
{
  NSEnumerator *emails;
  NSString *key;
  
#if defined(THREADSAFE)
  [lock lock];
#endif
  key = [newUser objectForKey: @"c_uid"];
  if (key)
    [[SOGoCache sharedCache] cacheAttributes: newUser  forLogin: key];
  emails = [[newUser objectForKey: @"emails"] objectEnumerator];
  while ((key = [emails nextObject]))
    {
      [[SOGoCache sharedCache] cacheAttributes: newUser  forLogin: key];
    }
#if defined(THREADSAFE)
  [lock unlock];
#endif

  // We propagate the loaded LDAP attributes to other sogod instances
  // which will cache them in SOGoCache (excluding for the instance
  // that actually posts the notification)
  if ([newUser objectForKey: @"c_uid"]) 
    {
      NSMutableDictionary *d;
      
      d = [NSMutableDictionary dictionary];
      [d setObject: newUser  forKey: @"values"];
      [d setObject: [newUser objectForKey: @"c_uid"]
	 forKey: @"uid"];
      
      [(NSDistributedNotificationCenter *)[NSDistributedNotificationCenter defaultCenter]
	postNotificationName: @"SOGoUserAttributesHaveLoaded"
	object: nil
	userInfo: d
	deliverImmediately: YES];
    }
}

- (NSDictionary *) contactInfosForUserWithUIDorEmail: (NSString *) uid
{
  NSMutableDictionary *currentUser, *contactInfos;
  NSString *aUID;
  BOOL newUser;

  if ([uid length] > 0)
    {
      // Remove the "@" prefix used to identified groups in the ACL tables.
      aUID = [uid hasPrefix: @"@"] ? [uid substringFromIndex: 1] : uid;
      contactInfos = [NSMutableDictionary dictionary];
      currentUser = [[SOGoCache sharedCache] userAttributesForLogin: aUID];
#if defined(THREADSAFE)
      [lock lock];
#endif
      if (!([currentUser objectForKey: @"emails"]
	    && [currentUser objectForKey: @"cn"]))
	{
	  if (!currentUser)
	    {
	      newUser = YES;
	      currentUser = [NSMutableDictionary dictionary];
	    }
	  else
	    newUser = NO;
	  [self _fillContactInfosForUser: currentUser
		withUIDorEmail: aUID];
	  if (newUser)
	    {
	      if ([[currentUser objectForKey: @"c_uid"] length] > 0)
		[self _retainUser: currentUser];
	      else
		currentUser = nil;
	    }
	}

#if defined(THREADSAFE)
      [lock unlock];
#endif
    }
  else
    currentUser = nil;

  return currentUser;
}

- (NSArray *) _compactAndCompleteContacts: (NSEnumerator *) contacts
{
  NSMutableDictionary *compactContacts, *returnContact;
  NSDictionary *userEntry;
  NSArray *newContacts;
  NSMutableArray *emails;
  NSString *uid, *email, *infoAttribute;

  compactContacts = [NSMutableDictionary dictionary];
  while ((userEntry = [contacts nextObject]))
    {
      uid = [userEntry objectForKey: @"c_uid"];
      if ([uid length])
	{
	  returnContact = [compactContacts objectForKey: uid];
	  if (!returnContact)
	    {
	      returnContact = [NSMutableDictionary dictionary];
	      [returnContact setObject: uid forKey: @"c_uid"];
	      [compactContacts setObject: returnContact forKey: uid];
	    }
	  if (![[returnContact objectForKey: @"c_name"] length])
	    [returnContact setObject: [userEntry objectForKey: @"c_name"]
			   forKey: @"c_name"];
	  if (![[returnContact objectForKey: @"cn"] length])
	    [returnContact setObject: [userEntry objectForKey: @"c_cn"]
			   forKey: @"cn"];
	  emails = [returnContact objectForKey: @"emails"];
	  if (!emails)
	    {
	      emails = [NSMutableArray array];
	      [returnContact setObject: emails forKey: @"emails"];
	    }
	  email = [userEntry objectForKey: @"mail"];
	  if (email && ![emails containsObject: email])
	    [emails addObject: email];
	  email = [userEntry objectForKey: @"mozillaSecondEmail"];
	  if (email && ![emails containsObject: email])
	    [emails addObject: email];
	  email = [userEntry objectForKey: @"xmozillasecondemail"];
	  if (email && ![emails containsObject: email])
	    [emails addObject: email];
	  if ([LDAPContactInfoAttribute length]
	      && ![[returnContact
		     objectForKey: LDAPContactInfoAttribute] length])
	    {
	      infoAttribute
		= [userEntry objectForKey: LDAPContactInfoAttribute];
	      if ([infoAttribute length])
		[returnContact setObject: infoAttribute
			   forKey: LDAPContactInfoAttribute];
	    }
	  [self _fillContactMailRecords: returnContact];
	}
    }

  newContacts = [compactContacts allValues];

  return newContacts;
}

- (NSArray *) _fetchEntriesInSources: (NSArray *) sourcesList
			    matching: (NSString *) filter
{
  NSMutableArray *contacts;
  NSEnumerator *ldapSources;
  NSString *sourceID;
  LDAPSource *currentSource;

  contacts = [NSMutableArray array];
  ldapSources = [sourcesList objectEnumerator];
  while ((sourceID = [ldapSources nextObject]))
    {
      currentSource = [sources objectForKey: sourceID];
      [contacts addObjectsFromArray:
		  [currentSource fetchContactsMatching: filter]];
    }

  return [self _compactAndCompleteContacts: [contacts objectEnumerator]];
}

- (NSArray *) fetchContactsMatching: (NSString *) filter
{
  return [self _fetchEntriesInSources: [self addressBookSourceIDs]
	       matching: filter];
}

- (NSArray *) fetchUsersMatching: (NSString *) filter
{
  return [self _fetchEntriesInSources: [self authenticationSourceIDs]
	       matching: filter];
}

- (NSString *) getLoginForDN: (NSString *) theDN
{
  NSEnumerator *ldapSources;
  NSString *login;
  LDAPSource *currentSource;

  login = nil;
  ldapSources = [[sources allValues] objectEnumerator];
  while ((currentSource = [ldapSources nextObject]))
    {
      if ([theDN hasSuffix: [currentSource baseDN]])
	{
	  login = [currentSource lookupLoginByDN: theDN];
	  if (login)
	    break;
	}
    }
  return login;
}

@end
