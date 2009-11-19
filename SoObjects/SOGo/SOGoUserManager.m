/* SOGoUserManager.m - this file is part of SOGo
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
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>
#import <NGExtensions/NSObject+Logs.h>

#import "NSDictionary+BSJSONAdditions.h"
#import "NSArray+Utilities.h"
#import "SOGoSource.h"
#import "SOGoUserManager.h"
#import "SOGoCache.h"
#import "SOGoSource.h"

#import "LDAPSource.h"
#import "SQLSource.h"

static NSString *defaultMailDomain = nil;
static NSString *LDAPContactInfoAttribute = nil;
static BOOL defaultMailDomainIsConfigured = NO;
static BOOL forceImapLoginWithEmail = NO;

#if defined(THREADSAFE)
static NSLock *lock = nil;
#endif

@implementation SOGoUserManager

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

      LDAPContactInfoAttribute = [[ud stringForKey: @"SOGoLDAPContactInfoAttribute"] lowercaseString];
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
  NSString *sourceID, *value, *type;
  NSMutableDictionary *metadata;
  id<SOGoSource> ldapSource;
  BOOL isAddressBook;
  Class c;
  
  sourceID = [udSource objectForKey: @"id"];
  if ([sourceID length] > 0)
    {
      type = [udSource objectForKey: @"type"];

      if (!type || [type caseInsensitiveCompare: @"ldap"] == NSOrderedSame)
        c = [LDAPSource class];
      else
        c = [SQLSource class];

      ldapSource = [c sourceFromUDSource: udSource];
      if (sourceID)
        [_sources setObject: ldapSource forKey: sourceID];
      else
        [self errorWithFormat: @"id field missing in an user source,"
              @" check the SOGoUserSources defaults"];
      metadata = [NSMutableDictionary dictionary];
      value = [udSource objectForKey: @"canAuthenticate"];
      if (value)
        [metadata setObject: value forKey: @"canAuthenticate"];
      value = [udSource objectForKey: @"isAddressBook"];
      if (value)
        {
          [metadata setObject: value forKey: @"isAddressBook"];
          isAddressBook = [value boolValue];
        }
      else
        isAddressBook = NO;
      value = [udSource objectForKey: @"displayName"];
      if (value)
        [metadata setObject: value forKey: @"displayName"];
      else
        {
          if (isAddressBook)
            [self errorWithFormat: @"addressbook source '%@' has"
                  @" no displayname", sourceID];
        }
      value = [udSource objectForKey: @"MailFieldNames"];
      if (value)
        [metadata setObject: value forKey: @"MailFieldNames"];
      [_sourcesMetadata setObject: metadata forKey: sourceID];
    }
  else
    [self errorWithFormat: @"attempted to register a contact/user source"
          @" without id (skipped)"];
}

- (void) _prepareSourcesWithDefaults: (NSUserDefaults *) ud
{
  id o, sources;
  unsigned int count, max;

  _sources = [[NSMutableDictionary alloc] init];
  _sourcesMetadata = [[NSMutableDictionary alloc] init];

  sources = [NSMutableArray array];
  o = [ud arrayForKey: @"SOGoLDAPSources"];

  if (o)
    {
      [self errorWithFormat: @"Using depecrated SOGoLDAPSources default. You should now use SOGoUserSources."];

      if ([o isKindOfClass: [NSArray class]])
	  [sources addObjectsFromArray: o];
      else
	[self errorWithFormat: @"SOGoLDAPSources is NOT an array. Check your defaults. You should now use SOGoUserSources nonetheless."];
    }
  
  o = [ud arrayForKey: @"SOGoUserSources"];

  if (o)
    {
      if ([o isKindOfClass: [NSArray class]])
	  [sources addObjectsFromArray: o];
      else
	[self errorWithFormat: @"SOGoUserSources is NOT an array. Check your defaults."];
    }

  if ([sources count])
    {
      max = [sources count];
      for (count = 0; count < max; count++)
	[self _registerSource: [sources objectAtIndex: count]];
    }
  else
    {
      [self errorWithFormat: @"No authentication sources defined - nobody will be able to login. Check your defaults."];
    }
}

- (id) init
{
  NSUserDefaults *ud;

  if ((self = [super init]))
    {
      ud = [NSUserDefaults standardUserDefaults];

      _sources = nil;
      _sourcesMetadata = nil;
      [self _prepareSourcesWithDefaults: ud];
    }

  return self;
}

- (void) dealloc
{
  [_sources release];
  [_sourcesMetadata release];
  [super dealloc];
}

- (NSArray *) sourceIDs
{
  return [_sources allKeys];
}

- (NSArray *) _sourcesOfType: (NSString *) sourceType
{
  NSMutableArray *sourceIDs;
  NSEnumerator *allIDs;
  NSString *currentID;
  NSNumber *canAuthenticate;

  sourceIDs = [NSMutableArray array];
  allIDs = [[_sources allKeys] objectEnumerator];
  while ((currentID = [allIDs nextObject])) 
    {
      canAuthenticate = [[_sourcesMetadata objectForKey: currentID]
			  objectForKey: sourceType];
      if ([canAuthenticate boolValue])
	[sourceIDs addObject: currentID];
    }

  return sourceIDs;
}

- (NSDictionary *) metadataForSourceID: (NSString *) sourceID
{
  return [_sourcesMetadata objectForKey: sourceID];
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
  return [_sources objectForKey: sourceID];
}

- (NSString *) displayNameForSourceWithID: (NSString *) sourceID
{
  NSDictionary *metadata;

  metadata = [_sourcesMetadata objectForKey: sourceID];

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

- (BOOL) _sourceCheckLogin: (NSString *) login
               andPassword: (NSString *) password
{ 
  id<SOGoSource> ldapSource;
  NSEnumerator *authIDs;
  NSString *currentID;
  BOOL checkOK;
  
  checkOK = NO;

  authIDs = [[self authenticationSourceIDs] objectEnumerator];
  while (!checkOK && (currentID = [authIDs nextObject]))
    {
      ldapSource = [_sources objectForKey: currentID];
      checkOK = [ldapSource checkLogin: login andPassword: password];
    }

  return checkOK;
}

- (BOOL) checkLogin: (NSString *) login
	andPassword: (NSString *) password
{
  NSMutableDictionary *currentUser;
  NSString *dictPassword, *jsonUser;
  BOOL checkOK;

#if defined(THREADSAFE)
  [lock lock];
#endif

  jsonUser = [[SOGoCache sharedCache] userAttributesForLogin: login];
  currentUser = [NSMutableDictionary dictionaryWithJSONString: jsonUser];
  dictPassword = [currentUser objectForKey: @"password"];
  if (currentUser && dictPassword)
    checkOK = ([dictPassword isEqualToString: password]);
  else if ([self _sourceCheckLogin: login andPassword: password])
    {
      checkOK = YES;
      if (!currentUser)
	{
	  currentUser = [NSMutableDictionary dictionary];
	}

      // It's important to cache the password here as we might have cached the
      // user's entry in -contactInfosForUserWithUIDorEmail: and if we don't
      // set the password and recache the entry, the password would never be
      // cached for the user unless its entry expires from memcached's
      // internal cache.
      [currentUser setObject: password forKey: @"password"];
      [[SOGoCache sharedCache]
        setUserAttributes: [currentUser jsonStringValue]
                 forLogin: login];
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
  NSString *uid, *systemEmail;
  NSMutableArray *emails;

  emails = [contact objectForKey: @"emails"];
  uid = [contact objectForKey: @"c_uid"];
  if ([uid rangeOfString: @"@"].location == NSNotFound)
    systemEmail
      = [NSString stringWithFormat: @"%@@%@", uid, defaultMailDomain];
  else
    systemEmail = uid;
  [emails addObject: systemEmail];
  [contact setObject: [emails objectAtIndex: 0] forKey: @"c_email"];
}

- (void) _fillContactInfosForUser: (NSMutableDictionary *) currentUser
		   withUIDorEmail: (NSString *) uid
{
  NSMutableArray *emails;
  NSDictionary *userEntry;
  NSEnumerator *ldapSources;
  LDAPSource *currentSource;
  NSString *sourceID, *cn, *c_uid, *c_imaphostname;
  NSArray *c_emails;
  BOOL access;

  emails = [NSMutableArray array];
  cn = nil;
  c_uid = nil;
  c_imaphostname = nil;

  [currentUser setObject: [NSNumber numberWithBool: YES]
	       forKey: @"CalendarAccess"];
  [currentUser setObject: [NSNumber numberWithBool: YES]
	       forKey: @"MailAccess"];

  ldapSources = [[self authenticationSourceIDs] objectEnumerator];
  while ((sourceID = [ldapSources nextObject]))
    {
      currentSource = [_sources objectForKey: sourceID];
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
	  if (!c_imaphostname)
	    c_imaphostname = [userEntry objectForKey: @"c_imaphostname"];
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
  
  if (c_imaphostname)
    [currentUser setObject: c_imaphostname forKey: @"c_imaphostname"];
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
  
  key = [newUser objectForKey: @"c_uid"];
  if (key)
    [[SOGoCache sharedCache]
        setUserAttributes: [newUser jsonStringValue]
                 forLogin: key];

  emails = [[newUser objectForKey: @"emails"] objectEnumerator];
  while ((key = [emails nextObject]))
    [[SOGoCache sharedCache]
        setUserAttributes: [newUser jsonStringValue]
                 forLogin: key];
}

- (NSDictionary *) contactInfosForUserWithUIDorEmail: (NSString *) uid
{
  NSMutableDictionary *currentUser, *contactInfos;
  NSString *aUID, *jsonUser;
  BOOL newUser;

  if ([uid length] > 0)
    {
      // Remove the "@" prefix used to identified groups in the ACL tables.
      aUID = [uid hasPrefix: @"@"] ? [uid substringFromIndex: 1] : uid;
      contactInfos = [NSMutableDictionary dictionary];
      jsonUser = [[SOGoCache sharedCache] userAttributesForLogin: aUID];
      currentUser = [NSDictionary dictionaryWithJSONString: jsonUser];
#if defined(THREADSAFE)
      [lock lock];
#endif
      if (!([currentUser objectForKey: @"emails"]
	    && [currentUser objectForKey: @"cn"]))
	{
	  // We make sure that we either have no occurence of a cache entry or that
	  // we have an occurence with only a cached password. In the latter case, we
	  // update the entry with the remaining information and recache the value.
	  if (!currentUser || ([currentUser count] == 1 && [currentUser objectForKey: @"password"]))
	    {
	      newUser = YES;

	      if (!currentUser)
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
	  email = [userEntry objectForKey: @"mozillasecondemail"];
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
  NSEnumerator *sources;
  NSString *sourceID;
  id currentSource;

  contacts = [NSMutableArray array];
  sources = [sourcesList objectEnumerator];
  while ((sourceID = [sources nextObject]))
    {
      currentSource = [_sources objectForKey: sourceID];
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
  ldapSources = [[_sources allValues] objectEnumerator];
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
