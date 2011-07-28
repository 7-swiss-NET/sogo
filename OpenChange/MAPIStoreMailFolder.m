/* MAPIStoreMailFolder.m - this file is part of SOGo
 *
 * Copyright (C) 2011 Inverse inc
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

#include <talloc.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <NGObjWeb/WOContext+SoObjects.h>
#import <EOControl/EOQualifier.h>
#import <EOControl/EOSortOrdering.h>
#import <NGExtensions/NSObject+Logs.h>
#import <NGExtensions/NSString+misc.h>
#import <Mailer/SOGoDraftsFolder.h>
#import <Mailer/SOGoMailAccount.h>
#import <Mailer/SOGoMailAccounts.h>
#import <Mailer/SOGoMailFolder.h>
#import <Mailer/SOGoSentFolder.h>
#import <Mailer/SOGoTrashFolder.h>
#import <SOGo/NSArray+Utilities.h>
#import <SOGo/NSString+Utilities.h>

#import "MAPIApplication.h"
#import "MAPIStoreAppointmentWrapper.h"
#import "MAPIStoreContext.h"
#import "MAPIStoreDraftsMessage.h"
#import "MAPIStoreMailMessage.h"
#import "MAPIStoreMailMessageTable.h"
#import "MAPIStoreTypes.h"
#import "NSString+MAPIStore.h"
#import "SOGoMAPIFSMessage.h"

#import "MAPIStoreMailFolder.h"

static Class MAPIStoreDraftsMessageK;
static Class MAPIStoreMailMessageK;
static Class SOGoMailFolderK;

#undef DEBUG
#include <libmapi/libmapi.h>
#include <mapistore/mapistore.h>

@implementation MAPIStoreMailFolder

+ (void) initialize
{
  MAPIStoreMailMessageK = [MAPIStoreMailMessage class];
  SOGoMailFolderK = [SOGoMailFolder class];
  [MAPIStoreAppointmentWrapper class];
}

- (id) initWithURL: (NSURL *) newURL
         inContext: (MAPIStoreContext *) newContext
{
  SOGoUserFolder *userFolder;
  SOGoMailAccounts *accountsFolder;
  SOGoMailAccount *accountFolder;
  SOGoFolder *currentContainer;
  WOContext *woContext;

  if ((self = [super initWithURL: newURL
                       inContext: newContext]))
    {
      woContext = [newContext woContext];
      userFolder = [SOGoUserFolder objectWithName: [newURL user]
                                      inContainer: MAPIApp];
      [parentContainersBag addObject: userFolder];
      [woContext setClientObject: userFolder];

      accountsFolder = [userFolder lookupName: @"Mail"
                                    inContext: woContext
                                      acquire: NO];
      [parentContainersBag addObject: accountsFolder];
      [woContext setClientObject: accountsFolder];
      
      accountFolder = [accountsFolder lookupName: @"0"
                                       inContext: woContext
                                         acquire: NO];
      [parentContainersBag addObject: accountFolder];
      [woContext setClientObject: accountFolder];

      sogoObject = [self specialFolderFromAccount: accountFolder
                                        inContext: woContext];
      [sogoObject retain];
      currentContainer = [sogoObject container];
      while (currentContainer != (SOGoFolder *) accountFolder)
        {
          [parentContainersBag addObject: currentContainer];
          currentContainer = [currentContainer container];
        }

      ASSIGN (versionsMessage,
              [SOGoMAPIFSMessage objectWithName: @"versions.plist"
                                    inContainer: propsFolder]);
    }

  return self;
}

- (id) initWithSOGoObject: (id) newSOGoObject
              inContainer: (MAPIStoreObject *) newContainer
{
  NSURL *propsURL;
  NSString *urlString;

  if ((self = [super initWithSOGoObject: newSOGoObject inContainer: newContainer]))
    {
      urlString = [[self url] stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
      propsURL = [NSURL URLWithString: urlString];
      ASSIGN (versionsMessage,
              [SOGoMAPIFSMessage objectWithName: @"versions.plist"
                                 inContainer: propsFolder]);
    }

  return self;
}

- (void) dealloc
{
  [versionsMessage release];
  [messageTable release];
  [super dealloc];
}

- (SOGoMailFolder *) specialFolderFromAccount: (SOGoMailAccount *) accountFolder
                                    inContext: (WOContext *) woContext
{
  [self subclassResponsibility: _cmd];

  return nil;
}

- (MAPIStoreMessageTable *) messageTable
{
  if (!messageTable)
    {
      [self synchroniseCache];
      ASSIGN (messageTable, [MAPIStoreMailMessageTable tableForContainer: self]);
    }

  return messageTable;
}

- (Class) messageClass
{
  return MAPIStoreMailMessageK;
}

- (NSString *) createFolder: (struct SRow *) aRow
                    withFID: (uint64_t) newFID
{
  NSString *folderName, *nameInContainer;
  SOGoMailFolder *newFolder;
  int i;

  nameInContainer = nil;

  folderName = nil;
  for (i = 0; !folderName && i < aRow->cValues; i++)
    {
      if (aRow->lpProps[i].ulPropTag == PR_DISPLAY_NAME_UNICODE)
        folderName = [NSString stringWithUTF8String: aRow->lpProps[i].value.lpszW];
      else if (aRow->lpProps[i].ulPropTag == PR_DISPLAY_NAME)
        folderName = [NSString stringWithUTF8String: aRow->lpProps[i].value.lpszA];
    }

  if (folderName)
    {
      nameInContainer = [NSString stringWithFormat: @"folder%@",
                                  [folderName asCSSIdentifier]];
      newFolder = [SOGoMailFolderK objectWithName: nameInContainer
                                      inContainer: sogoObject];
      if (![newFolder create])
        nameInContainer = nil;
    }

  return nameInContainer;
}

- (int) getPrContentUnread: (void **) data
                  inMemCtx: (TALLOC_CTX *) memCtx
{
  EOQualifier *searchQualifier;
  uint32_t longValue;

  searchQualifier
    = [EOQualifier qualifierWithQualifierFormat: @"flags = %@", @"unseen"];
  longValue = [[sogoObject fetchUIDsMatchingQualifier: searchQualifier
                                         sortOrdering: nil]
                count];
  *data = MAPILongValue (memCtx, longValue);
  
  return MAPISTORE_SUCCESS;
}

- (int) getPrContainerClass: (void **) data
                   inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = [@"IPF.Note" asUnicodeInMemCtx: memCtx];
  
  return MAPISTORE_SUCCESS;
}

- (int) getPrMessageClass: (void **) data
                 inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = [@"IPM.Note" asUnicodeInMemCtx: memCtx];
  
  return MAPISTORE_SUCCESS;
}

- (EOQualifier *) nonDeletedQualifier
{
  static EOQualifier *nonDeletedQualifier = nil;
  EOQualifier *deletedQualifier;

  if (!nonDeletedQualifier)
    {
      deletedQualifier
        = [[EOKeyValueQualifier alloc] 
                 initWithKey: @"FLAGS"
            operatorSelector: EOQualifierOperatorContains
                       value: [NSArray arrayWithObject: @"Deleted"]];
      nonDeletedQualifier = [[EONotQualifier alloc]
                              initWithQualifier: deletedQualifier];
      [deletedQualifier release];
    }

  return nonDeletedQualifier;
}

- (NSArray *) messageKeysMatchingQualifier: (EOQualifier *) qualifier
                          andSortOrderings: (NSArray *) sortOrderings
{
  NSArray *uidKeys;
  EOQualifier *fetchQualifier;

  if (!sortOrderings)
    sortOrderings = [NSArray arrayWithObject: @"ARRIVAL"];

  if (qualifier)
    {
      fetchQualifier
        = [[EOAndQualifier alloc] initWithQualifiers:
                                    [self nonDeletedQualifier], qualifier,
                                  nil];
      [fetchQualifier autorelease];
    }
  else
    fetchQualifier = [self nonDeletedQualifier];

  uidKeys = [sogoObject fetchUIDsMatchingQualifier: fetchQualifier
                                      sortOrdering: sortOrderings];
  return [uidKeys stringsWithFormat: @"%@.eml"];
}

- (NSArray *) folderKeys
{
  if (!folderKeys)
    folderKeys = [[sogoObject toManyRelationshipKeys] mutableCopy];

  return folderKeys;
}

- (id) lookupFolder: (NSString *) childKey
{
  id childObject = nil;
  SOGoMailFolder *childFolder;

  [self folderKeys];
  if ([folderKeys containsObject: childKey])
    {
      childFolder = [sogoObject lookupName: childKey inContext: nil
                                   acquire: NO];
      childObject = [MAPIStoreMailFolder mapiStoreObjectWithSOGoObject: childFolder
                                                           inContainer: self];
    }

  return childObject;
}

- (NSCalendarDate *) creationTime
{
  return [NSCalendarDate dateWithTimeIntervalSince1970: 0x4dbb2dbe]; /* oc_version_time */
}

- (NSDate *) lastMessageModificationTime
{
  NSNumber *ti;
  NSDate *value = nil;

  ti = [[versionsMessage properties]
         objectForKey: @"SyncLastSynchronisationDate"];
  if (ti)
    value = [NSDate dateWithTimeIntervalSince1970: [ti doubleValue]];
  else
    value = [NSDate date];

  [self logWithFormat: @"lastMessageModificationTime: %@", value];

  return value;
}

/* synchronisation */

/* Tree:
{
  SyncLastModseq = x;
  SyncLastSynchronisationDate = x; ** not updated until something changed
  Messages = {
    MessageKey = {
      Version = x;
      Modseq = x;
      Deleted = b;
    };
    ...
  };
  VersionMapping = {
    Version = MessageKey;
    ...
  }
}
*/

static NSComparisonResult
_compareFetchResultsByMODSEQ (id entry1, id entry2, void *data)
{
  static NSNumber *zeroNumber = nil;
  NSNumber *modseq1, *modseq2;

  if (!zeroNumber)
    zeroNumber = [NSNumber numberWithUnsignedLongLong: 0];

  modseq1 = [entry1 objectForKey: @"modseq"];
  if (!modseq1)
    modseq1 = zeroNumber;
  modseq2 = [entry2 objectForKey: @"modseq"];
  if (!modseq2)
    modseq2 = zeroNumber;

  return [modseq1 compare: modseq2];
}

- (BOOL) synchroniseCache
{
  BOOL rc = YES;
  uint64_t newChangeNum;
  NSNumber *ti, *changeNumber, *modseq, *lastModseq, *nextModseq, *uid;
  EOQualifier *searchQualifier;
  NSArray *uids;
  NSUInteger count, max;
  NSArray *fetchResults;
  NSDictionary *result;
  NSMutableDictionary *currentProperties, *messages, *mapping, *messageEntry;
  NSCalendarDate *now;

  now = [NSCalendarDate date];
  [now setTimeZone: utcTZ];

  currentProperties = [[versionsMessage properties] mutableCopy];
  if (!currentProperties)
    currentProperties = [NSMutableDictionary new];
  [currentProperties autorelease];
  messages = [currentProperties objectForKey: @"Messages"];
  if (!messages)
    {
      messages = [NSMutableDictionary new];
      [currentProperties setObject: messages forKey: @"Messages"];
      [messages release];
    }
  mapping = [currentProperties objectForKey: @"VersionMapping"];
  if (!mapping)
    {
      mapping = [NSMutableDictionary new];
      [currentProperties setObject: mapping forKey: @"VersionMapping"];
      [mapping release];
    }

  lastModseq = [currentProperties objectForKey: @"SyncLastModseq"];
  if (lastModseq)
    {
      nextModseq = [NSNumber numberWithUnsignedLongLong:
                               [lastModseq unsignedLongLongValue] + 1];
      searchQualifier = [[EOKeyValueQualifier alloc]
                                initWithKey: @"modseq"
                           operatorSelector: EOQualifierOperatorGreaterThanOrEqualTo
                                      value: nextModseq];
      [searchQualifier autorelease];
    }
  else
    searchQualifier = [self nonDeletedQualifier];

  uids = [sogoObject fetchUIDsMatchingQualifier: searchQualifier
                                   sortOrdering: nil];
  max = [uids count];
  if (max > 0)
    {
      fetchResults
        = [(NSDictionary *) [sogoObject fetchUIDs: uids
                                            parts: [NSArray arrayWithObject: @"modseq"]]
                          objectForKey: @"fetch"];

      /* NOTE: we sort items manually because Cyrus does not properly sort
         entries with a MODSEQ of 0 */
      fetchResults
        = [fetchResults sortedArrayUsingFunction: _compareFetchResultsByMODSEQ
                                         context: NULL];
      for (count = 0; count < max; count++)
        {
          result = [fetchResults objectAtIndex: count];
          uid = [result objectForKey: @"uid"];
          modseq = [result objectForKey: @"modseq"];
          [self logWithFormat: @"uid '%@' has modseq '%@'", uid, modseq];
          newChangeNum = [[self context] getNewChangeNumber];
          changeNumber = [NSNumber numberWithUnsignedLongLong: newChangeNum];

          messageEntry = [NSMutableDictionary new];
          [messages setObject: messageEntry forKey: uid];
          [messageEntry release];

          [messageEntry setObject: modseq forKey: @"modseq"];
          [messageEntry setObject: changeNumber forKey: @"version"];

          [mapping setObject: modseq forKey: changeNumber];

          if (!lastModseq
              || ([lastModseq compare: modseq] == NSOrderedAscending))
            lastModseq = modseq;
        }

      ti = [NSNumber numberWithDouble: [now timeIntervalSince1970]];
      [currentProperties setObject: ti
                            forKey: @"SyncLastSynchronisationDate"];
      [currentProperties setObject: lastModseq forKey: @"SyncLastModseq"];
      [versionsMessage appendProperties: currentProperties];
      [versionsMessage save];
    }

  return rc;
}
 
- (NSNumber *) modseqFromMessageChangeNumber: (NSNumber *) changeNum
{
  NSDictionary *mapping;
  NSNumber *modseq;

  mapping = [[versionsMessage properties] objectForKey: @"VersionMapping"];
  modseq = [mapping objectForKey: changeNum];

  return modseq;
}

- (NSNumber *) messageUIDFromMessageKey: (NSString *) messageKey
{
  NSNumber *messageUid;
  NSString *uidString;
  NSRange dotRange;

  dotRange = [messageKey rangeOfString: @".eml"];
  if (dotRange.location != NSNotFound)
    {
      uidString = [messageKey substringToIndex: dotRange.location];
      messageUid = [NSNumber numberWithInt: [uidString intValue]];
    }
  else
    messageUid = nil;

  return messageUid;
}

- (NSNumber *) changeNumberForMessageUID: (NSNumber *) messageUid
{
  NSDictionary *messages;
  NSNumber *changeNumber;

  messages = [[versionsMessage properties] objectForKey: @"Messages"];
  changeNumber = [[messages objectForKey: messageUid]
                   objectForKey: @"version"];

  return changeNumber;
}

@end

@implementation MAPIStoreInboxFolder : MAPIStoreMailFolder

- (SOGoMailFolder *) specialFolderFromAccount: (SOGoMailAccount *) accountFolder
                                    inContext: (WOContext *) woContext
{
  return [accountFolder inboxFolderInContext: woContext];
}

@end

@implementation MAPIStoreSentItemsFolder : MAPIStoreMailFolder

- (SOGoMailFolder *) specialFolderFromAccount: (SOGoMailAccount *) accountFolder
                                    inContext: (WOContext *) woContext
{
  return [accountFolder sentFolderInContext: woContext];
}

@end

@implementation MAPIStoreDraftsFolder : MAPIStoreMailFolder

- (SOGoMailFolder *) specialFolderFromAccount: (SOGoMailAccount *) accountFolder
                                    inContext: (WOContext *) woContext
{
  return [accountFolder draftsFolderInContext: woContext];
}

@end

// @implementation MAPIStoreDeletedItemsFolder : MAPIStoreMailFolder

// - (SOGoMailFolder *) specialFolderFromAccount: (SOGoMailAccount *) accountFolder
//                                     inContext: (WOContext *) woContext
// {
//   return [accountFolder trashFolderInContext: woContext];
// }

// @end

@implementation MAPIStoreOutboxFolder : MAPIStoreMailFolder

+ (void) initialize
{
  MAPIStoreDraftsMessageK = [MAPIStoreDraftsMessage class];
}

- (SOGoMailFolder *) specialFolderFromAccount: (SOGoMailAccount *) accountFolder
                                    inContext: (WOContext *) woContext
{
  return [accountFolder draftsFolderInContext: woContext];
}

- (Class) messageClass
{
  return MAPIStoreDraftsMessageK;
}

- (MAPIStoreMessage *) createMessage
{
  MAPIStoreDraftsMessage *newMessage;
  SOGoDraftObject *newDraft;

  newDraft = [sogoObject newDraft];
  newMessage
    = [MAPIStoreDraftsMessage mapiStoreObjectWithSOGoObject: newDraft
                                                inContainer: self];

  
  return newMessage;
}

@end
