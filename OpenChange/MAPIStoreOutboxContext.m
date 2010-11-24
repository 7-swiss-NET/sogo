/* MAPIStoreOutboxContext.m - this file is part of SOGo
 *
 * Copyright (C) 2010 Wolfgang Sourdeau
 *
 * Author: Wolfgang Sourdeau <root@inverse.ca>
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

#import <Foundation/NSString.h>

#import <NGObjWeb/WOContext+SoObjects.h>

#import <SOGo/SOGoUserFolder.h>

#import <Mailer/SOGoDraftsFolder.h>
#import <Mailer/SOGoMailAccount.h>
#import <Mailer/SOGoMailAccounts.h>

#import "MAPIApplication.h"
#import "MAPIStoreAuthenticator.h"
#import "MAPIStoreMapping.h"
#import "MAPIStoreTypes.h"

#import "MAPIStoreOutboxContext.h"

@implementation MAPIStoreOutboxContext

+ (NSString *) MAPIModuleName
{
  return @"outbox";
}

+ (void) registerFixedMappings: (MAPIStoreMapping *) mapping
{
  [mapping registerURL: @"sogo://openchange:openchange@outbox/"
                withID: 0x150001];
}

- (void) setupModuleFolder
{
  SOGoUserFolder *userFolder;
  SOGoMailAccounts *accountsFolder;
  SOGoMailAccount *accountFolder;

  userFolder = [SOGoUserFolder objectWithName: [authenticator username]
                                  inContainer: MAPIApp];
  [woContext setClientObject: userFolder];
  [userFolder retain]; // LEAK

  accountsFolder = [userFolder lookupName: @"Mail"
                                inContext: woContext
                                  acquire: NO];
  [woContext setClientObject: accountsFolder];
  [accountsFolder retain]; // LEAK

  accountFolder = [accountsFolder lookupName: @"0"
                                  inContext: woContext
                                    acquire: NO];
  [accountFolder retain]; // LEAK

  moduleFolder = [accountFolder draftsFolderInContext: nil];
  [moduleFolder retain];
}

- (id) createMessageInFolder: (id) parentFolder
{
  return [moduleFolder newDraft];
}

@end
