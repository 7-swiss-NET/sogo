/* SOGoUserManager.h - this file is part of SOGo
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

#ifndef SOGOUSERMANAGER_H
#define SOGOUSERMANAGER_H

#import <Foundation/NSObject.h>

@class NSDictionary;
@class NSMutableDictionary;
@class NSString;
@class NSTimer;
@class NGLdapEntry;

@class LDAPSource;

@protocol SOGoSource;

@interface SOGoUserManager : NSObject
{
  @private
    NSMutableDictionary *_sources;
    NSMutableDictionary *_sourcesMetadata;
}

+ (id) sharedUserManager;

- (NSArray *) sourceIDsInDomain: (NSString *) domain;
- (NSArray *) authenticationSourceIDs;
- (NSArray *) addressBookSourceIDsInDomain: (NSString *) domain;

- (NSObject <SOGoSource> *) sourceWithID: (NSString *) sourceID;
- (NSDictionary *) metadataForSourceID: (NSString *) sourceID;
- (NSString *) displayNameForSourceWithID: (NSString *) sourceID;
- (NSDictionary *) contactInfosForUserWithUIDorEmail: (NSString *) uid;
- (NSArray *) fetchContactsMatching: (NSString *) match
                           inDomain: (NSString *) domain;
- (NSArray *) fetchUsersMatching: (NSString *) filter;

- (NSString *) getCNForUID: (NSString *) uid;
- (NSString *) getEmailForUID: (NSString *) uid;
- (NSString *) getFullEmailForUID: (NSString *) uid;
- (NSString *) getImapLoginForUID: (NSString *) uid;
- (NSString *) getUIDForEmail: (NSString *) email;
- (NSString *) getLoginForDN: (NSString *) theDN;

- (BOOL) checkLogin: (NSString *) login
	andPassword: (NSString *) password;

@end

#endif /* SOGOUSERMANAGER_H */
