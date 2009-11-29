/* LDAPSource.h - this file is part of SOGo
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

#ifndef LDAPSOURCE_H
#define LDAPSOURCE_H

#import <Foundation/NSObject.h>

#include "SOGoSource.h"

@class NSDictionary;
@class NSString;
@class NGLdapConnection;
@class NGLdapEntry;

@interface LDAPSource : NSObject <SOGoSource>
{
  int queryLimit;
  int queryTimeout;

  NSString *sourceID;
  NSString *bindDN;
  NSString *hostname;
  unsigned int port;
  NSString *password;
  NSString *encryption;
  NSString *_filter;
  NSString *_scope;

  NSString *baseDN;
  NSString *IDField; /* the first part of a user DN */
  NSString *CNField;
  NSString *UIDField;
  NSArray *mailFields;
  NSString *IMAPHostField;
  NSString *bindFields;

  NSString *domain;
  NSString *contactInfoAttribute;
  NSString *domainAttribute;

  NSDictionary *modulesConstraints;

  NSMutableArray *searchAttributes;
}

- (void) setBindDN: (NSString *) newBindDN
	  password: (NSString *) newBindPassword
	  hostname: (NSString *) newBindHostname
	      port: (NSString *) newBindPort
	encryption: (NSString *) newEncryption;

- (void) setBaseDN: (NSString *) newBaseDN
	   IDField: (NSString *) newIDField
	   CNField: (NSString *) newCNField
	  UIDField: (NSString *) newUIDField
	mailFields: (NSArray *) newMailFields
     IMAPHostField: (NSString *) newIMAPHostField
     andBindFields: (NSString *) newBindFields;

- (NSString *) lookupLoginByDN: (NSString *) theDN;

- (NGLdapEntry *) lookupGroupEntryByUID: (NSString *) theUID;
- (NGLdapEntry *) lookupGroupEntryByEmail: (NSString *) theEmail;
- (NGLdapEntry *) lookupGroupEntryByAttribute: (NSString *) theAttribute 
				     andValue: (NSString *) theValue;

- (NSString *) baseDN;

@end

#endif /* LDAPSOURCE_H */
