/* MAPIStoreMailMessage.m - this file is part of SOGo
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

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <NGExtensions/NSObject+Logs.h>
#import <SOGo/NSArray+Utilities.h>
#import <SOGo/NSString+Utilities.h>
#import <NGImap4/NGImap4EnvelopeAddress.h>
#import <Mailer/NSData+Mail.h>
#import <Mailer/SOGoMailBodyPart.h>
#import <Mailer/SOGoMailObject.h>

#import "NSData+MAPIStore.h"
#import "NSObject+MAPIStore.h"
#import "NSString+MAPIStore.h"
#import "MAPIStoreContext.h"
#import "MAPIStoreFolder.h"
#import "MAPIStoreMailFolder.h"
#import "MAPIStoreTypes.h"
#import "MAPIStoreMailAttachment.h"

#import "MAPIStoreMailMessage.h"

#undef DEBUG
#include <stdbool.h>
#include <gen_ndr/exchange.h>
#include <mapistore/mapistore.h>
#include <mapistore/mapistore_errors.h>
#include <mapistore/mapistore_nameid.h>

static Class NSExceptionK, MAPIStoreSentItemsFolderK, MAPIStoreDraftsFolderK;

@interface NSString (MAPIStoreMIME)

- (NSString *) _strippedBodyKey;

@end

@implementation NSString (MAPIStoreMIME)

- (NSString *) _strippedBodyKey
{
  NSRange bodyRange;
  NSString *strippedKey;

  bodyRange = [self rangeOfString: @"body["];
  if (bodyRange.length > 0)
    {
      strippedKey = [self substringFromIndex: NSMaxRange (bodyRange)];
      strippedKey = [strippedKey substringToIndex: [strippedKey length] - 1];
    }
  else
    strippedKey = nil;

  return strippedKey;
}

@end

@implementation MAPIStoreMailMessage

+ (void) initialize
{
  NSExceptionK = [NSException class];
  MAPIStoreSentItemsFolderK = [MAPIStoreSentItemsFolder class];
  MAPIStoreDraftsFolderK = [MAPIStoreDraftsFolder class];
}

- (id) init
{
  if ((self = [super init]))
    {
      bodySetup = NO;
      bodyContent = nil;
      bodyMimeType = nil;
      bodyCharset = nil;
      fetchedAttachments = NO;
    }

  return self;
}

- (void) dealloc
{
  [bodyContent release];
  [bodyMimeType release];
  [bodyCharset release];
  [super dealloc];
}

- (int) getPrIconIndex: (void **) data
              inMemCtx: (TALLOC_CTX *) memCtx
{
  uint32_t longValue;

  /* see http://msdn.microsoft.com/en-us/library/cc815472.aspx */
  if ([sogoObject isNewMail])
    longValue = 0xffffffff;
  else if ([sogoObject replied])
    longValue = 0x105;
  else if ([sogoObject forwarded])
    longValue = 0x106;
  else if ([sogoObject read])
    longValue = 0x100;
  else
    longValue = 0x101;
  *data = MAPILongValue (memCtx, longValue);

  return MAPISTORE_SUCCESS;
}

- (int) getPidLidImapDeleted: (void **) data
                    inMemCtx: (TALLOC_CTX *) memCtx
{
  uint32_t longValue;

  if ([sogoObject deleted])
    longValue = 1;
  else
    longValue = 0;
  *data = MAPILongValue (memCtx, longValue);

  return MAPISTORE_SUCCESS;
}

- (int) getPrSubject: (void **) data
            inMemCtx: (TALLOC_CTX *) memCtx
{
  NSString *stringValue;

  stringValue = [sogoObject decodedSubject];
  if (!stringValue)
    stringValue = @"";
  *data = [stringValue asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getPrSubjectPrefix: (void **) data
                  inMemCtx: (TALLOC_CTX *) memCtx
{
  NSString *subject;
  NSUInteger colIdx;
  NSString *stringValue;

  subject = [sogoObject decodedSubject];
  colIdx = [subject rangeOfString: @":"].location;
  if (colIdx != NSNotFound && colIdx < 4)
    stringValue = [NSString stringWithFormat: @"%@: ",
                            [subject substringToIndex: colIdx]];
  else
    stringValue = @"";
  *data = [stringValue asUnicodeInMemCtx: memCtx];
  
  return MAPISTORE_SUCCESS;
}

- (int) getPrNormalizedSubject: (void **) data
                      inMemCtx: (TALLOC_CTX *) memCtx
{
  NSString *subject;
  NSUInteger colIdx;
  NSString *stringValue;

  subject = [sogoObject decodedSubject];
  colIdx = [subject rangeOfString: @":"].location;
  if (colIdx != NSNotFound && colIdx < 4)
    stringValue = [[subject substringFromIndex: colIdx + 1]
                    stringByTrimmingLeadSpaces];
  else
    stringValue = subject;
  if (!stringValue)
    stringValue = @"";
  *data = [stringValue asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getPrMessageClass: (void **) data
                 inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = talloc_strdup (memCtx, "IPM.Note");

  return MAPISTORE_SUCCESS;
}

- (int) getPrReplyRequested: (void **) data // TODO
                   inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getNo: data inMemCtx: memCtx];
}

- (int) getPrResponseRequested: (void **) data // TODO
                      inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = MAPIBoolValue (memCtx, NO);

  return MAPISTORE_SUCCESS;
}

- (NSCalendarDate *) creationTime
{
  return [sogoObject date];
}

- (NSCalendarDate *) lastModificationTime
{
  return [sogoObject date];
}

- (int) getPrLatestDeliveryTime: (void **) data // DOUBT
                       inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrCreationTime: data inMemCtx: memCtx];
}

- (int) getPrOriginalSubmitTime: (void **) data
                       inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrCreationTime: data inMemCtx: memCtx];
}

- (int) getPrClientSubmitTime: (void **) data
                     inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrCreationTime: data inMemCtx: memCtx];
}

- (int) getPrMessageDeliveryTime: (void **) data
                        inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrCreationTime: data inMemCtx: memCtx];
}

- (int) getPrMessageFlags: (void **) data // TODO
                 inMemCtx: (TALLOC_CTX *) memCtx
{
  NSDictionary *coreInfos;
  NSArray *flags;
  unsigned int v = 0;
    
  coreInfos = [sogoObject fetchCoreInfos];
  flags = [coreInfos objectForKey: @"flags"];

  if ([container isKindOfClass: MAPIStoreSentItemsFolderK]
      || [container isKindOfClass: MAPIStoreDraftsFolderK])
    v |= MSGFLAG_FROMME;
  if ([flags containsObject: @"seen"])
    v |= MSGFLAG_READ;
  if ([[self childKeysMatchingQualifier: nil
                       andSortOrderings: nil] count] > 0)
    v |= MSGFLAG_HASATTACH;
    
  *data = MAPILongValue (memCtx, v);

  return MAPISTORE_SUCCESS;
}

- (int) getPrFlagStatus: (void **) data
               inMemCtx: (TALLOC_CTX *) memCtx
{
  NSDictionary *coreInfos;
  NSArray *flags;
  unsigned int v;

  coreInfos = [sogoObject fetchCoreInfos];

  flags = [coreInfos objectForKey: @"flags"];
  if ([flags containsObject: @"flagged"])
    v = 2;
  else
    v = 0;
    
  *data = MAPILongValue (memCtx, v);

  return MAPISTORE_SUCCESS;
}

- (int) getPrFollowupIcon: (void **) data
                 inMemCtx: (TALLOC_CTX *) memCtx
{
  NSDictionary *coreInfos;
  NSArray *flags;
  unsigned int v;
    
  coreInfos = [sogoObject fetchCoreInfos];
  
  flags = [coreInfos objectForKey: @"flags"];
  if ([flags containsObject: @"flagged"])
    v = 6;
  else
    v = 0;
    
  *data = MAPILongValue (memCtx, v);

  return MAPISTORE_SUCCESS;
}

- (int) getPrSensitivity: (void **) data // TODO
                inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getLongZero: data inMemCtx: memCtx];
}

- (int) getPrOriginalSensitivity: (void **) data // TODO
                        inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrSensitivity: data inMemCtx: memCtx];
}

- (int) getPrSentRepresentingAddrtype: (void **) data
                             inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getSMTPAddrType: data inMemCtx: memCtx];
}

- (int) getPrRcvdRepresentingAddrtype: (void **) data
                             inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getSMTPAddrType: data inMemCtx: memCtx];
}

- (int) getPrReceivedByAddrtype: (void **) data
                       inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getSMTPAddrType: data inMemCtx: memCtx];
}

- (int) getPrSenderAddrtype: (void **) data
                   inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getSMTPAddrType: data inMemCtx: memCtx];
}

- (int) getPrSenderEmailAddress: (void **) data
                       inMemCtx: (TALLOC_CTX *) memCtx
{
  NSString *stringValue;

  stringValue = [sogoObject from];
  if (!stringValue)
    stringValue = @"";

  *data = [stringValue asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getPrSenderName: (void **) data
               inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrSenderEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrOriginalAuthorName: (void **) data
                       inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrSenderEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrSentRepresentingEmailAddress: (void **) data
                                 inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrSenderEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrSentRepresentingName: (void **) data
                         inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrSenderEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrReceivedByEmailAddress: (void **) data
                           inMemCtx: (TALLOC_CTX *) memCtx
{
  NSString *stringValue;

  stringValue = [sogoObject to];
  if (!stringValue)
    stringValue = @"";

  *data = [stringValue asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getPrReceivedByName: (void **) data
                   inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrReceivedByEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrRcvdRepresentingName: (void **) data
                         inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrReceivedByEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrRcvdRepresentingEmailAddress: (void **) data
                                 inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrReceivedByEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrDisplayTo: (void **) data
              inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrReceivedByEmailAddress: data inMemCtx: memCtx];
}

- (int) getPrOriginalDisplayTo: (void **) data
                      inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrDisplayTo: data inMemCtx: memCtx];
}

- (int) getPrDisplayCc: (void **) data
              inMemCtx: (TALLOC_CTX *) memCtx
{
  NSString *stringValue;

  stringValue = [sogoObject cc];
  if (!stringValue)
    stringValue = @"";

  *data = [stringValue asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getPrOriginalDisplayCc: (void **) data
                      inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrDisplayCc: data inMemCtx: memCtx];
}

- (int) getPrDisplayBcc: (void **) data
               inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getEmptyString: data inMemCtx: memCtx];
}

- (int) getPrOriginalDisplayBcc: (void **) data
                       inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getPrDisplayBcc: data inMemCtx: memCtx];
}

- (int) getPidNameContentType: (void **) data
                     inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = [@"message/rfc822" asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getPrImportance: (void **) data
               inMemCtx: (TALLOC_CTX *) memCtx
{
  uint32_t v;
  NSString *s;
    
  s = [[sogoObject mailHeaders] objectForKey: @"x-priority"];
  v = 0x1;
    
  if ([s hasPrefix: @"1"]) v = 0x2;
  else if ([s hasPrefix: @"2"]) v = 0x2;
  else if ([s hasPrefix: @"4"]) v = 0x0;
  else if ([s hasPrefix: @"5"]) v = 0x0;
    
  *data = MAPILongValue (memCtx, v);

  return MAPISTORE_SUCCESS;
}

- (int) getPrInternetCpid: (void **) data
                 inMemCtx: (TALLOC_CTX *) memCtx
{
  /* ref:
  http://msdn.microsoft.com/en-us/library/dd317756%28v=vs.85%29.aspx
  
  minimal list that should be handled:
  us-ascii: 20127
  iso-8859-1: 28591
  iso-8859-15: 28605
  utf-8: 65001 */
  *data = MAPILongValue(memCtx, 65001);

  return MAPISTORE_SUCCESS;
}

static NSComparisonResult
_compareBodyKeysByPriority (id entry1, id entry2, void *data)
{
  NSComparisonResult result;
  NSArray *keys;
  NSString *data1, *data2;
  NSUInteger count1, count2;

  keys = data;

  data1 = [entry1 objectForKey: @"mimeType"];
  count1 = [keys indexOfObject: data1];
  data2 = [entry2 objectForKey: @"mimeType"];
  count2 = [keys indexOfObject: data2];
  
  if (count1 == count2)
    {
      data1 = [entry1 objectForKey: @"key"];
      count1 = [data1 countOccurrencesOfString: @"."];
      data2 = [entry2 objectForKey: @"key"];
      count2 = [data2 countOccurrencesOfString: @"."];
      if (count1 == count2)
        {
          data1 = [data1 _strippedBodyKey];
          count1 = [data1 intValue];
          data2 = [data2 _strippedBodyKey];
          count2 = [data2 intValue];
          if (count1 == count2)
            result = NSOrderedSame;
          else if (count1 < count2)
            result = NSOrderedAscending;
          else
            result = NSOrderedDescending;
        }
      else if (count1 < count2)
        result = NSOrderedAscending;
      else
        result = NSOrderedDescending;
    }
  else if (count1 < count2)
    result = NSOrderedAscending;
  else
    result = NSOrderedDescending;

  return result;
}

- (void) _setupBodyData
{
  NSMutableArray *keys;
  NSArray *acceptedTypes;
  NSDictionary *messageData, *partHeaderData;
  NSString *messageKey, *encoding;
  NSData *rawContent;
  id result;

  acceptedTypes = [NSArray arrayWithObjects: // @"text/calendar",
                           // @"application/ics",
                           @"text/html",
                           @"text/plain", nil];
  keys = [NSMutableArray array];
  [sogoObject addRequiredKeysOfStructure: [sogoObject bodyStructure]
                                    path: @"" toArray: keys
                           acceptedTypes: acceptedTypes];
  [keys sortUsingFunction: _compareBodyKeysByPriority context: acceptedTypes];
  if ([keys count] > 0)
    {
      messageData = [keys objectAtIndex: 0];
      ASSIGN (bodyMimeType, [messageData objectForKey: @"mimeType"]);
      messageKey = [messageData objectForKey: @"key"];
      result = [sogoObject fetchParts: [NSArray arrayWithObject: messageKey]];
      result = [[result valueForKey: @"RawResponse"] objectForKey: @"fetch"];
      rawContent = [[result objectForKey: messageKey] objectForKey: @"data"];
      partHeaderData = [sogoObject
                         lookupInfoForBodyPart: [messageKey _strippedBodyKey]];
      encoding = [partHeaderData objectForKey: @"encoding"];
      ASSIGN (bodyContent, [rawContent bodyDataFromEncoding: encoding]);
      ASSIGN (bodyCharset, [[partHeaderData objectForKey: @"parameterList"]
                             objectForKey: @"charset"]);
    }

  bodySetup = YES;
}

- (int) getPrBody: (void **) data
         inMemCtx: (TALLOC_CTX *) memCtx
{
  NSString *stringValue;
  int rc = MAPISTORE_SUCCESS;

  if (!bodySetup)
    [self _setupBodyData];

  if ([bodyMimeType isEqualToString: @"text/plain"])
    {
      stringValue = [bodyContent bodyStringFromCharset: bodyCharset];
      *data = [stringValue asUnicodeInMemCtx: memCtx];
    }
  else
    {
      *data = NULL;
      rc = MAPISTORE_ERR_NOT_FOUND;
    }

  return rc;
}

- (int) getPrHtml: (void **) data
         inMemCtx: (TALLOC_CTX *) memCtx
{
  int rc = MAPISTORE_SUCCESS;

  if (!bodySetup)
    [self _setupBodyData];

  if ([bodyMimeType isEqualToString: @"text/html"])
    *data = [bodyContent asBinaryInMemCtx: memCtx];
  else
    {
      *data = NULL;
      rc = MAPISTORE_ERR_NOT_FOUND;
    }

  return rc;
}

- (int) getPrRtfCompressed: (void **) data
                  inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = NULL;

  return MAPISTORE_ERR_NOT_FOUND;
}

- (int) getPrRtfInSync: (void **) data
              inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getNo: data inMemCtx: memCtx];
}

- (int) getPrInternetMessageId: (void **) data
                      inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = [[sogoObject messageId] asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getPrReadReceiptRequested: (void **) data // TODO
                         inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getNo: data inMemCtx: memCtx];
}

- (int) getPrDeleteAfterSubmit: (void **) data // TODO
                      inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getNo: data inMemCtx: memCtx];
}

- (int) getPidLidPrivate: (void **) data
                inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getNo: data inMemCtx: memCtx];
}

- (int) getPrMsgEditorFormat: (void **) data
                    inMemCtx: (TALLOC_CTX *) memCtx
{
  NSMutableArray *keys;
  NSArray *acceptedTypes;
  uint32_t format;
    
  format = 0; /* EDITOR_FORMAT_DONTKNOW */
    
  acceptedTypes = [NSArray arrayWithObject: @"text/plain"];
  keys = [NSMutableArray array];
  [sogoObject addRequiredKeysOfStructure: [sogoObject bodyStructure]
                                    path: @"" toArray: keys
                           acceptedTypes: acceptedTypes];
  if ([keys count] == 1)
    format = EDITOR_FORMAT_PLAINTEXT;
  
  acceptedTypes = [NSArray arrayWithObject: @"text/html"];
  [keys removeAllObjects];
  [sogoObject addRequiredKeysOfStructure: [sogoObject bodyStructure]
                                    path: @"" toArray: keys
                           acceptedTypes: acceptedTypes];
  if ([keys count] == 1)
    format = EDITOR_FORMAT_HTML;
  
  *data = MAPILongValue (memCtx, format);

  return MAPISTORE_SUCCESS;
}

- (int) getPidLidReminderSet: (void **) data // TODO
                    inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getNo: data inMemCtx: memCtx];
}

- (int) getPidLidUseTnef: (void **) data // TODO
                inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getNo: data inMemCtx: memCtx];
}

- (int) getPidLidRemoteStatus: (void **) data // TODO
                     inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getLongZero: data inMemCtx: memCtx];
}

- (int) getPidLidAgingDontAgeMe: (void **) data // TODO
                       inMemCtx: (TALLOC_CTX *) memCtx
{
  return [self getYes: data inMemCtx: memCtx];
}

- (void) getMessageData: (struct mapistore_message **) dataPtr
               inMemCtx: (TALLOC_CTX *) memCtx
{
  struct SRowSet *recipients;
  NSArray *to;
  NSInteger count, max;
  NGImap4EnvelopeAddress *currentAddress;
  NSString *text;
  struct mapistore_message *msgData;

  [super getMessageData: &msgData inMemCtx: memCtx];
  /* Retrieve recipients from the message */
  to = [sogoObject toEnvelopeAddresses];
  max = [to count];
  recipients = talloc_zero (msgData, struct SRowSet);
  recipients->cRows = max;
  recipients->aRow = talloc_array (recipients, struct SRow, max);
  for (count = 0; count < max; count++)
    {
      recipients->aRow[count].ulAdrEntryPad = 0;
      recipients->aRow[count].cValues = 3;
      recipients->aRow[count].lpProps = talloc_array (recipients->aRow,
                                                      struct SPropValue,
                                                      4);

      // TODO (0x01 = primary recipient)
      set_SPropValue_proptag (recipients->aRow[count].lpProps + 0,
                              PR_RECIPIENT_TYPE,
                              MAPILongValue (recipients->aRow, 0x01));
     
      set_SPropValue_proptag (recipients->aRow[count].lpProps + 1,
                              PR_ADDRTYPE_UNICODE,
                              [@"SMTP" asUnicodeInMemCtx: recipients->aRow]);

      currentAddress = [to objectAtIndex: count];
      // text = [currentAddress personalName];
      // if (![text length])
      text = [currentAddress baseEMail];
      if (!text)
        text = @"";
      set_SPropValue_proptag (recipients->aRow[count].lpProps + 2,
                              PR_EMAIL_ADDRESS_UNICODE,
                              [text asUnicodeInMemCtx: recipients->aRow]);

      text = [currentAddress personalName];
      if ([text length] > 0)
        {
          recipients->aRow[count].cValues++;
          set_SPropValue_proptag (recipients->aRow[count].lpProps + 3,
                                  PR_DISPLAY_NAME_UNICODE,
                                  [text asUnicodeInMemCtx: recipients->aRow]);
        }
    }
  msgData->recipients = recipients;
  *dataPtr = msgData;
}

- (void) _fetchAttachmentPartsInBodyInfo: (NSDictionary *) bodyInfo
                              withPrefix: (NSString *) keyPrefix
{
  NSArray *parts;
  NSDictionary *parameters;
  NSUInteger count, max;

  parameters = [[bodyInfo objectForKey: @"disposition"]
                 objectForKey: @"parameterList"];
  if ([[parameters objectForKey: @"filename"] length] > 0)
    {
      if ([keyPrefix length] == 0)
        keyPrefix = @"0";
      [attachmentParts setObject: bodyInfo
                          forKey: keyPrefix];
      [attachmentKeys addObject: keyPrefix];
    }
  else
    {
      if ([keyPrefix length] > 0)
        keyPrefix = [NSString stringWithFormat: @"%@/", keyPrefix];
      parts = [bodyInfo objectForKey: @"parts"];
      max = [parts count];
      for (count = 0; count < max; count++)
        [self _fetchAttachmentPartsInBodyInfo: [parts objectAtIndex: count]
                                   withPrefix: [NSString stringWithFormat: @"%@%d",
                                                         keyPrefix, count + 1]];
    }
}

- (NSArray *) childKeysMatchingQualifier: (EOQualifier *) qualifier
                        andSortOrderings: (NSArray *) sortOrderings
{
  if (!fetchedAttachments)
    {
      [self _fetchAttachmentPartsInBodyInfo: [sogoObject bodyStructure]
                                 withPrefix: @""];
      fetchedAttachments = YES;
    }

  return [super childKeysMatchingQualifier: qualifier
                          andSortOrderings: sortOrderings];
}

- (id) lookupChild: (NSString *) childKey
{
  MAPIStoreMailAttachment *attachment;
  SOGoMailBodyPart *currentPart;
  NSArray *keyParts;
  NSUInteger count, max;

  attachment = nil;

  keyParts = [childKey componentsSeparatedByString: @"/"];
  max = [keyParts count];
  if (max > 0)
    {
      currentPart = [sogoObject lookupName: [keyParts objectAtIndex: 0]
                                 inContext: nil
                                   acquire: NO];
      if ([currentPart isKindOfClass: NSExceptionK])
        currentPart = nil;

      for (count = 1; currentPart && count < max; count++)
        {
          [parentContainersBag addObject: currentPart];
          currentPart = [currentPart lookupName: [keyParts objectAtIndex: count]
                                      inContext: nil
                                        acquire: NO];
          if ([currentPart isKindOfClass: NSExceptionK])
            currentPart = nil;
        }

      if (currentPart)
        {
          attachment = [MAPIStoreMailAttachment
                         mapiStoreObjectWithSOGoObject: currentPart
                                           inContainer: self];
          [attachment setBodyInfo: [attachmentParts objectForKey: childKey]];
          [attachment setAID: [attachmentKeys indexOfObject: childKey]];
        }
    }

  return attachment;
}

- (void) save
{
  NSNumber *value;

  value = [newProperties objectForKey: MAPIPropertyKey (PR_FLAG_STATUS)];
  if (value)
    {
      /* We don't handle the concept of "Follow Up" */
      if ([value intValue] == 2)
        [sogoObject addFlags: @"\\Flagged"];
      else /* 0: unflagged, 1: follow up complete */
        [sogoObject removeFlags: @"\\Flagged"];
    }
}

@end
