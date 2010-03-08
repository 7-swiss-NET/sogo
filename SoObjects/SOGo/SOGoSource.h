/* SOGoSource.h - this file is part of SOGo
 *
 * Copyright (C) 2009-2010 Inverse inc.
 *
 * Author: Ludovic Marcotte <lmarcotte@inverse.ca>
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

#ifndef SOGOSOURCE_H
#define SOGOSOURCE_H

#import <Foundation/NSObject.h>

#import "SOGoConstants.h"

@class NSDictionary;
@class NSString;

@protocol SOGoSource

+ (id) sourceFromUDSource: (NSDictionary *) udSource
                 inDomain: (NSString *) domain;

- (id) initFromUDSource: (NSDictionary *) udSource
               inDomain: (NSString *) domain;

- (NSString *) domain;

- (BOOL) checkLogin: (NSString *) _login
	   password: (NSString *) _pwd
	       perr: (SOGoPasswordPolicyError *) _perr
	     expire: (int *) _expire
	      grace: (int *) _grace;

- (BOOL) changePasswordForLogin: (NSString *) login
		    oldPassword: (NSString *) oldPassword
		    newPassword: (NSString *) newPassword
			   perr: (SOGoPasswordPolicyError *) perr;

- (NSDictionary *) lookupContactEntry: (NSString *) theID;
- (NSDictionary *) lookupContactEntryWithUIDorEmail: (NSString *) entryID;

- (NSArray *) allEntryIDs;
- (NSArray *) fetchContactsMatching: (NSString *) filter;
- (NSString *) sourceID;

@end

@protocol SOGoDNSource <SOGoSource>

- (NSString *) lookupLoginByDN: (NSString *) theDN;
- (NSString *) baseDN;

@end

#endif /* SOGOSOURCE_H */
