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

#ifndef __SOGoUser_H__
#define __SOGoUser_H__

#include <NGObjWeb/SoUser.h>

/*
  SOGoUser

  This adds some additional SOGo properties to the SoUser object. The
  properties are (currently) looked up using the AgenorUserManager.

  You have access to this object from the WOContext:
    context.activeUser
*/

@class NSString;
@class NSArray;
@class NSDictionary;
@class NSURL;
@class NSUserDefaults;
@class NSTimeZone;
@class WOContext;

@interface SOGoUser : SoUser
{
  NSString *cn;
  NSString *email;
  NSString *systemEMail;
  NSUserDefaults *userDefaults;
  NSUserDefaults *userSettings;
  NSTimeZone *userTimeZone;
}

+ (SOGoUser *) userWithLogin: (NSString *) login
		    andRoles: (NSArray *) roles;

/* properties */

- (NSString *) email;
- (NSString *) systemEMail;
- (NSString *) cn;
- (NSURL *) freeBusyURL;

/* shares and identities */

- (NSString *) primaryIMAP4AccountString;
- (NSString *) primaryMailServer;
- (NSArray *) additionalIMAP4AccountStrings;
- (NSArray *) additionalEMailAddresses;
- (NSDictionary *) additionalIMAP4AccountsAndEMails;

/* defaults */

- (NSUserDefaults *) userDefaults;
- (NSUserDefaults *) userSettings;

- (NSTimeZone *) timeZone;
- (NSTimeZone *) serverTimeZone;

/* folders */

- (id) homeFolderInContext: (id) _ctx;
- (id) schedulingCalendarInContext: (id) _ctx;

- (NSArray *) rolesForObject: (NSObject *) object
                   inContext: (WOContext *) context;

@end

#endif /* __SOGoUser_H__ */
