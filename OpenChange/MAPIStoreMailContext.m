/* MAPIStoreMailContext.m - this file is part of SOGo
 *
 * Copyright (C) 2010 Inverse inc.
 *
 * Author: Wolfgang Sourdeau <wsourdeau@inverse.ca>
 *
 * This file is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
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
#import <Foundation/NSString.h>

#import <Mailer/SOGoMailAccount.h>
#import <Mailer/SOGoMailFolder.h>

#import "MAPIStoreMailFolder.h"
#import "MAPIStoreUserContext.h"
#import "NSString+MAPIStore.h"

#import "MAPIStoreMailContext.h"

#include <dlinklist.h>
#undef DEBUG
#include <mapistore/mapistore.h>

static Class MAPIStoreMailFolderK;

@implementation MAPIStoreMailContext

+ (void) initialize
{
  MAPIStoreMailFolderK = [MAPIStoreMailFolder class];
}

+ (NSString *) MAPIModuleName
{
  return @"mail";
}

+ (struct mapistore_contexts_list *) listContextsForUser: (NSString *) userName
                                         withTDBIndexing: (struct tdb_wrap *) indexingTdb
                                                inMemCtx: (TALLOC_CTX *) memCtx
{
  struct mapistore_contexts_list *firstContext = NULL, *context;
  NSString *urlBase, *stringData, *currentName, *inboxName, *draftsName, *sentName, *trashName;
  NSMutableArray *secondaryFolders;
  enum mapistore_context_role role[] = {MAPISTORE_MAIL_ROLE,
                                        MAPISTORE_DRAFTS_ROLE,
                                        MAPISTORE_SENTITEMS_ROLE};
  NSString *folderName[3];
  NSUInteger count, max;
  SOGoMailAccount *accountFolder;
  MAPIStoreUserContext *userContext;
  WOContext *woContext;

  userContext = [MAPIStoreUserContext userContextWithUsername: userName
                                               andTDBIndexing: indexingTdb];
  accountFolder = [[userContext rootFolders] objectForKey: @"mail"];
  woContext = [userContext woContext];

  inboxName = @"folderINBOX";
  folderName[0] = inboxName;

  draftsName = [NSString stringWithFormat: @"folder%@",
                         [accountFolder draftsFolderNameInContext: woContext]];
  folderName[1] = draftsName;
  sentName = [NSString stringWithFormat: @"folder%@",
                       [accountFolder sentFolderNameInContext: woContext]];
  folderName[2] = sentName;
  trashName = [NSString stringWithFormat: @"folder%@",
                       [accountFolder trashFolderNameInContext: woContext]];

  urlBase = [NSString stringWithFormat: @"sogo://%@:%@@mail/", userName, userName];

  for (count = 0; count < 3; count++)
    {
      context = talloc_zero (memCtx, struct mapistore_contexts_list);
      stringData = [NSString stringWithFormat: @"%@%@", urlBase,
                      folderName[count]];
      context->url = [stringData asUnicodeInMemCtx: context];
      /* remove "folder" prefix */
      stringData = [folderName[count] substringFromIndex: 6];
      context->name = [stringData asUnicodeInMemCtx: context];
      context->main_folder = true;
      context->role = role[count];
      context->tag = "tag";
      DLIST_ADD_END (firstContext, context, void);
    }

  secondaryFolders = [[accountFolder toManyRelationshipKeysWithNamespaces: NO]
                       mutableCopy];
  [secondaryFolders autorelease];
  [secondaryFolders removeObject: inboxName];
  [secondaryFolders removeObject: draftsName];
  [secondaryFolders removeObject: draftsName];
  [secondaryFolders removeObject: sentName];
  [secondaryFolders removeObject: trashName];
  max = [secondaryFolders count];
  for (count = 0; count < max; count++)
    {
      context = talloc_zero (memCtx, struct mapistore_contexts_list);
      currentName = [secondaryFolders objectAtIndex: count];
      stringData = [NSString stringWithFormat: @"%@%@", urlBase, currentName];
      context->url = [stringData asUnicodeInMemCtx: context];
      stringData = [currentName substringFromIndex: 6];
      context->name = [stringData asUnicodeInMemCtx: context];
      context->main_folder = false;
      context->role = MAPISTORE_MAIL_ROLE;
      context->tag = "tag";
      DLIST_ADD_END (firstContext, context, void);
    }

  return firstContext;
}

- (Class) MAPIStoreFolderClass
{
  return MAPIStoreMailFolderK;
}

- (id) rootSOGoFolder
{
  return [[userContext rootFolders] objectForKey: @"mail"];
}

@end

@implementation MAPIStoreOutboxContext

+ (NSString *) MAPIModuleName
{
  return @"outbox";
}

+ (struct mapistore_contexts_list *) listContextsForUser: (NSString *) userName
                                         withTDBIndexing: (struct tdb_wrap *) indexingTdb
                                                inMemCtx: (TALLOC_CTX *) memCtx
{
  struct mapistore_contexts_list *context;
  NSString *url, *folderName;
  SOGoMailAccount *accountFolder;
  MAPIStoreUserContext *userContext;
  WOContext *woContext;

  userContext = [MAPIStoreUserContext userContextWithUsername: userName
                                               andTDBIndexing: indexingTdb];
  accountFolder = [[userContext rootFolders] objectForKey: @"mail"];
  woContext = [userContext woContext];
  folderName = [NSString stringWithFormat: @"folder%@",
                         [accountFolder draftsFolderNameInContext: woContext]];
  url = [NSString stringWithFormat: @"sogo://%@:%@@outbox/%@", userName,
                  userName, folderName];

  context = talloc_zero (memCtx, struct mapistore_contexts_list);
  context->url = [url asUnicodeInMemCtx: context];
  /* TODO: use a localized version of this display name */
  context->name = [@"Outbox" asUnicodeInMemCtx: context];
  context->main_folder = true;
  context->role = MAPISTORE_OUTBOX_ROLE;
  context->tag = "tag";
  context->prev = context;

  return context;
}

@end
