/*
  Copyright (C) 2004-2005 SKYRIX Software AG
  Copyright (C) 2006-2010 Inverse inc.

  This file is part of SOGo

  SOGo is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  SOGo is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with OGo; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

/*
  UIxMailListActions
  
  This component represent a list of mails and is attached to an SOGoMailFolder
  object.
*/

#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSValue.h>

#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGObjWeb/WOResponse.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/SoObject+SoDAV.h>
#import <NGObjWeb/NSException+HTTP.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGExtensions/NSString+misc.h>
#import <NGExtensions/NSObject+Logs.h>
#import <NGImap4/NGImap4Envelope.h>

#import <EOControl/EOQualifier.h>

#import <Mailer/NSString+Mail.h>
#import <Mailer/SOGoDraftsFolder.h>
#import <Mailer/SOGoMailFolder.h>
#import <Mailer/SOGoMailObject.h>
#import <Mailer/SOGoSentFolder.h>
#import <SOGo/NSArray+Utilities.h>
#import <SOGo/NSDictionary+Utilities.h>
#import <SOGo/SOGoDateFormatter.h>
#import <SOGo/SOGoUser.h>
#import <SOGo/SOGoUserDefaults.h>

#import <UI/Common/WODirectAction+SOGo.h>

#import "WOContext+UIxMailer.h"
#import "UIxMailFormatter.h"

#import "UIxMailListActions.h"

@implementation UIxMailListActions

- (id) initWithRequest: (WORequest *) newRequest
{
  SOGoUser *user;

  if ((self = [super initWithRequest: newRequest]))
    {
      user = [[self context] activeUser];
      ASSIGN (dateFormatter, [user dateFormatterInContext: context]);
      ASSIGN (userTimeZone, [[user userDefaults] timeZone]);
      folderType = 0;
      specificMessageNumber = 0;
    }

  return self;
}

- (void) dealloc 
{
  [sortedUIDs release];
  [messages release];
  [message release];
  [dateFormatter release];
  [userTimeZone release];
  [super dealloc];
}

/* accessors */

- (void) setMessage: (id) _msg
{
  ASSIGN (message, _msg);
}

- (id) message 
{
  return message;
}

- (NSString *) messageDate
{
  NSCalendarDate *messageDate;

  messageDate = [[message valueForKey: @"envelope"] date];
  [messageDate setTimeZone: userTimeZone];

  return [dateFormatter formattedDateAndTime: messageDate];
}

- (NSString *) messageSize
{
  NSString *rc;
  int size;

  size = [[message valueForKey: @"size"] intValue];
  if (size > 1024*1024)
    rc = [NSString stringWithFormat: @"%.1f MB", (float) size/1024/1024];
  else if (size > 1024*100)
    rc = [NSString stringWithFormat: @"%d KB", size/1024];    
  else
    rc = [NSString stringWithFormat: @"%.1f KB", (float) size/1024];
  
  return rc;
}

//
// Priorities are defined like this:
//
// X-Priority: 1 (Highest)
// X-Priority: 2 (High)
// X-Priority: 3 (Normal)
// X-Priority: 4 (Low)
// X-Priority: 5 (Lowest)
//
// Sometimes, the MUAs don't send over the string in () so we ignore it.
//
- (NSString *) messagePriority
{
  NSString *result;
  NSData *data;
    
  data = [message objectForKey: @"header"];
  result = @"";

  if (data)
    {
      NSString *s;
      
      s = [[NSString alloc] initWithData: data
			    encoding: NSASCIIStringEncoding];

      if (s)
	{
	  NSRange r;

	  [s autorelease];
	  r = [s rangeOfString: @":"];

	  if (r.length)
	    {
	      s = [[s substringFromIndex: r.location+1]
		    stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	      if ([s hasPrefix: @"1"]) result = [self labelForKey: @"highest"];
	      else if ([s hasPrefix: @"2"]) result = [self labelForKey: @"high"];
	      else if ([s hasPrefix: @"4"]) result = [self labelForKey: @"low"];
	      else if ([s hasPrefix: @"5"]) result = [self labelForKey: @"lowest"];
	    }
	}
    }
  
  return result;
}

- (NSString *) messageSubject
{
  id baseSubject;
  NSString *subject;

  baseSubject = [[message valueForKey: @"envelope"] subject];
  subject = [baseSubject decodedHeader];
  if (![subject length])
    subject = [self labelForKey: @"Untitled"];

  return subject;
}

- (BOOL) showToAddress 
{
  SOGoMailFolder *co;

  if (!folderType)
    {
      co = [self clientObject];
      if ([co isKindOfClass: [SOGoSentFolder class]]
	  || [co isKindOfClass: [SOGoDraftsFolder class]])
	folderType = 1;
      else
	folderType = -1;
    }

  return (folderType == 1);
}

/* title */

- (NSString *) objectTitle 
{
  return [[self clientObject] nameInContainer];
}

- (NSString *) panelTitle 
{
  NSString *s;
  
  s = [self labelForKey:@"View Mail Folder"];
  s = [s stringByAppendingString:@": "];
  s = [s stringByAppendingString:[self objectTitle]];
  return s;
}

/* derived accessors */

- (BOOL) isMessageDeleted
{
  NSArray *flags;
  
  flags = [[self message] valueForKey:@"flags"];
  return [flags containsObject:@"deleted"];
}

- (BOOL) isMessageRead
{
  NSArray *flags;
  
  flags = [[self message] valueForKey:@"flags"];
  return [flags containsObject:@"seen"];
}

- (BOOL) isMessageFlagged
{
  NSArray *flags;
  
  flags = [[self message] valueForKey:@"flags"];
  return [flags containsObject:@"flagged"];
}

- (NSString *) messageUidString 
{
  return [[[self message] valueForKey:@"uid"] stringValue];
}

- (NSString *) messageRowStyleClass 
{
  NSArray *flags;
  NSString *cellClass = @"";

  flags = [[self message] valueForKey:@"flags"];

  if ([self isMessageDeleted])
    cellClass = [cellClass stringByAppendingString: @"mailer_listcell_deleted "];

  if (![self isMessageRead])
    cellClass = [cellClass stringByAppendingString: @"mailer_unreadmail "];
  
  if ([flags containsObject: @"answered"])
    {
      if ([flags containsObject: @"$forwarded"])
	cellClass = [cellClass stringByAppendingString: @"mailer_forwardedrepliedmailsubject"];
      else
	cellClass = [cellClass stringByAppendingString: @"mailer_repliedmailsubject"];
    }
  else if ([flags containsObject: @"$forwarded"])
    cellClass = [cellClass stringByAppendingString: @"mailer_forwardedmailsubject"];
  else
    cellClass = [cellClass stringByAppendingString: @"mailer_readmailsubject"];

  return cellClass;
}

- (BOOL) hasMessageAttachment 
{
  NSArray *parts;
  NSEnumerator *dispositions;
  NSDictionary *currentDisp;
  BOOL hasAttachment;

  hasAttachment = NO;

  parts = [[message objectForKey: @"body"] objectForKey: @"parts"];
  if ([parts count] > 1)
    {
      dispositions = [[parts objectsForKey: @"disposition"
			     notFoundMarker: nil] objectEnumerator];
      while (!hasAttachment
	     && (currentDisp = [dispositions nextObject]))
	hasAttachment = ([[currentDisp objectForKey: @"type"] length]);
    }

  return hasAttachment;
}

/* fetching messages */

- (NSArray *) fetchKeys 
{
  /* Note: see SOGoMailManager.m for allowed IMAP4 keys */
  static NSArray *keys = nil;

  if (!keys)
    keys = [[NSArray alloc] initWithObjects: @"UID",
    			    @"FLAGS", @"ENVELOPE", @"RFC822.SIZE",
    			    @"BODYSTRUCTURE", @"BODY.PEEK[HEADER.FIELDS (X-PRIORITY)]", nil];
  return keys;
}

- (NSString *) defaultSortKey
{
  return @"ARRIVAL";
}

- (NSString *) imap4SortKey
{
  NSString *sort;
  
  sort = [[context request] formValueForKey: @"sort"];

  if (![sort length])
    sort = [self defaultSortKey];

  return [sort uppercaseString];
}

- (NSString *) imap4SortOrdering 
{
  NSString *sort, *ascending;
  NSString *module; //*login
  NSMutableDictionary *moduleSettings;
  BOOL asc;
  SOGoUser *activeUser;
  SOGoUserSettings *us;
  SOGoMailAccounts *clientObject;

  sort = [self imap4SortKey];
  ascending = [[context request] formValueForKey: @"asc"];
  asc = [ascending boolValue];

  if (![sort isEqualToString: [self defaultSortKey]])
      {
	// Save the sorting state in the user settings
	activeUser = [context activeUser];
	clientObject = [self clientObject];
	module = [[[clientObject container] container] nameInContainer];
	us = [activeUser userSettings];
	moduleSettings = [us objectForKey: module];
	if (!moduleSettings)
	  {
	    moduleSettings = [NSMutableDictionary dictionary];
	    [us setObject: moduleSettings forKey: module];
	  }
	[moduleSettings setObject: [NSArray arrayWithObjects: [sort lowercaseString], [NSString stringWithFormat: @"%d", (asc?1:0)], nil]
			   forKey: @"SortingState"];
	[us synchronize];
      }

  // Construct and return the final IMAP ordering constraint
  if (!asc)
    sort = [@"REVERSE " stringByAppendingString: sort];

  return sort;
}

- (EOQualifier *) searchQualifier
{
  NSString *criteria, *value;
  EOQualifier *qualifier;
  WORequest *request;  

  request = [context request];
  criteria = [request formValueForKey: @"search"];
  value = [request formValueForKey: @"value"];
  qualifier = nil;
  if ([value length])
    {
      if ([criteria isEqualToString: @"subject"])
	qualifier = [EOQualifier qualifierWithQualifierFormat:
				       @"(subject doesContain: %@)", value];
      else if ([criteria isEqualToString: @"sender"])
	qualifier = [EOQualifier qualifierWithQualifierFormat:
					  @"(from doesContain: %@)", value];
      else if ([criteria isEqualToString: @"subject_or_sender"])
	qualifier = [EOQualifier qualifierWithQualifierFormat:
				      @"((subject doesContain: %@)"
				      @" OR (from doesContain: %@))",
				 value, value];
      else if ([criteria isEqualToString: @"to_or_cc"])
	qualifier = [EOQualifier qualifierWithQualifierFormat:
					   @"((to doesContain: %@)"
					@" OR (cc doesContain: %@))",
				 value, value];
      else if ([criteria isEqualToString: @"entire_message"])
	qualifier = [EOQualifier qualifierWithQualifierFormat:
					  @"(body doesContain: %@)", value];
    }
  
  return qualifier;
}

- (NSArray *) sortedUIDs 
{
  EOQualifier *qualifier, *fetchQualifier, *notDeleted;
  SOGoMailFolder *folder;

  if (!sortedUIDs)
    {
      notDeleted = [EOQualifier qualifierWithQualifierFormat:
				  @"(not (flags = %@))",
				@"deleted"];
      qualifier = [self searchQualifier];
      if (qualifier)
	{
	  fetchQualifier = [[EOAndQualifier alloc] initWithQualifiers:
						     notDeleted, qualifier,
						   nil];
	  [fetchQualifier autorelease];
	}
      else
	fetchQualifier = notDeleted;

      folder = [self clientObject];
      sortedUIDs
        = [folder fetchUIDsMatchingQualifier: fetchQualifier
				sortOrdering: [self imap4SortOrdering]];
      [sortedUIDs retain];
    }

  return sortedUIDs;
}

- (int) indexOfMessageUID: (int) messageNbr
{
  NSArray *messageNbrs;
  int index;

  messageNbrs = [self sortedUIDs];
  index
    = [messageNbrs indexOfObject: [NSNumber numberWithInt: messageNbr]];
//   if (index < 0)
//     index = 0;

  return index;
}

/* JavaScript */

- (NSString *) msgRowID
{
  return [@"row_" stringByAppendingString:[self messageUidString]];
}

- (NSString *) msgIconReadImgID
{
  return [@"readdiv_" stringByAppendingString:[self messageUidString]];
}

- (NSString *) msgIconUnreadImgID
{
  return [@"unreaddiv_" stringByAppendingString:[self messageUidString]];
}

/* error redirects */

/*
- (id) redirectToViewWithError: (id) _error 
{
  // TODO: DUP in UIxMailAccountView
  // TODO: improve, localize
  // TODO: there is a bug in the treeview which preserves the current URL for
  //       the active object (displaying the error again)
  id url;
  
  if (![_error isNotNull])
    return [self redirectToLocation:@"view"];
  
  if ([_error isKindOfClass:[NSException class]])
    _error = [_error reason];
  else if ([_error isKindOfClass:[NSString class]])
    _error = [_error stringValue];
  
  url = [_error stringByEscapingURL];
  url = [@"view?error=" stringByAppendingString:url];
  return [self redirectToLocation:url];
}
*/

/* actions */

- (id) getMailAction 
{
  // TODO: we might want to flush the caches?
  id client;

  if ((client = [self clientObject]) == nil) {
    return [NSException exceptionWithHTTPStatus:404 /* Not Found */
			reason:@"did not find mail folder"];
  }

  if (![client respondsToSelector:@selector(flushMailCaches) ]) 
    {
      return [NSException exceptionWithHTTPStatus: 500 /* Server Error */
                          reason:
                            @"invalid client object (does not support flush)"];
    }

  [client flushMailCaches];

  return [self redirectToLocation:@"view"];
}

- (id <WOActionResults>) getSortedUIDsAction
{
  NSArray *uids;
  NSRange r;
  WORequest *request;
  WOResponse *response;
  int firstUID, firstIndex, count;
  
  request = [context request];
  uids = [self sortedUIDs]; // retrieves the form parameters "sort" and "asc"

  if ([request formValueForKey: @"start"] != nil)
    {
      firstUID = [[request formValueForKey: @"start"] intValue];
      firstIndex = [self indexOfMessageUID: firstUID];
      if (firstIndex == NSNotFound)
	return [NSException exceptionWithHTTPStatus: 404
					     reason: @"Message not found"];
    }
  else
    firstIndex = -1;

  if ([request formValueForKey: @"count"] != nil)
    {
      count = [[request formValueForKey: @"count"] intValue];
    }
  else
    count = 0;

  if (firstIndex > -1)
    {
      if (count <= 0 || (count + firstIndex) > [uids count])
	count = [uids count] - firstIndex;
      r = NSMakeRange(firstIndex, count);
      uids = [uids subarrayWithRange: r];
    }
  
  response = [context response];
  [response setHeader: @"text/plain; charset=utf-8"
	       forKey: @"content-type"];
  [response appendContentString: [uids jsonRepresentation]];

  return response;
}

- (id <WOActionResults>) getHeadersAction
{
  NSArray *uids, *to;
  NSDictionary *msgs;
  NSMutableArray *headers;
  NSMutableDictionary *msg;
  NSEnumerator *msgsList;
  NSString *msgIconStatus;
  SOGoMailFolder *mailFolder;
  WORequest *request;
  WOResponse *response;
  UIxEnvelopeAddressFormatter *addressFormatter;
  
  request = [context request];
  
  if ([request formValueForKey: @"uids"] == nil)
    {
      return [NSException exceptionWithHTTPStatus: 404
					   reason: @"No UID specified"];
    }

  uids = [[request formValueForKey: @"uids"] componentsSeparatedByString: @","]; // Should we support ranges? ie "x-y"
  headers = [NSMutableArray arrayWithCapacity: [uids count]];
  mailFolder = [self clientObject];
  addressFormatter = [context mailEnvelopeAddressFormatter];
  
  // Fetch headers
  msgs = (NSDictionary *)[mailFolder fetchUIDs: uids
					 parts: [self fetchKeys]];

  msgsList = [[msgs objectForKey: @"fetch"] objectEnumerator];
  [self setMessage: [msgsList nextObject]];
  while (message)
    {
      msg = [NSMutableDictionary dictionaryWithCapacity: 11];

      // Columns data

      to = [[message objectForKey: @"envelope"] to];
      if ([to count] > 0)
	[msg setObject: [addressFormatter stringForArray: to]
		forKey: @"To"];

      if ([self hasMessageAttachment])
	[msg setObject: [NSString stringWithFormat: @"<img src=\"%@\"/>", [self urlForResourceFilename: @"title_attachment_14x14.png"]]
		forKey: @"Attachment"];

      if ([self isMessageFlagged])
	{
	  [msg setObject: [NSString stringWithFormat: @"<img src=\"%@\" class=\"messageIsFlagged\">",
				    [self urlForResourceFilename: @"flag.png"]]
		  forKey: @"Flagged"];
	}
      else
	{
	  [msg setObject: [NSString stringWithFormat: @"<img src=\"%@\">",
				    [self urlForResourceFilename: @"dot.png"]]
		  forKey: @"Flagged"];
	}

      [msg setObject: [NSString stringWithFormat: @"<span>%@</span>",
				[self messageSubject]]
	      forKey: @"Subject"];
      
      [msg setObject: [addressFormatter stringForArray: [[message objectForKey: @"envelope"] from]] forKey: @"From"];

      if ([self isMessageRead])
	msgIconStatus = @"dot.png";
      else
	msgIconStatus = @"icon_unread.gif";
      
      [msg setObject: [self messageRowStyleClass] forKey: @"rowClasses"];
      [msg setObject: [NSString stringWithFormat: @"<img src=\"%@\" class=\"mailerReadIcon\" title=\"%@\" title-markread=\"%@\" title-markunread=\"%@\" id=\"%@\"/>",
				[self urlForResourceFilename: msgIconStatus],
 			       [self labelForKey: @"Mark Unread"],
 			       [self labelForKey: @"Mark Read"],
 			       [self labelForKey: @"Mark Unread"],
 				[self msgIconReadImgID]]
	      forKey: @"Unread"];
      
      [msg setObject: [self messagePriority] forKey: @"Priority"];

      [msg setObject: [self messageDate] forKey: @"Date"];

      [msg setObject: [self messageSize] forKey: @"Size"];
      
      [msg setObject: [self msgLabels] forKey: @"labels"];

      [msg setObject: [self msgRowID] forKey: @"rowID"];

      [msg setObject: [message objectForKey: @"uid"] forKey: @"uid"];

      [headers addObject: msg];
      
      [self setMessage: [msgsList nextObject]];
    }

  response = [context response];
  [response setHeader: @"text/plain; charset=utf-8"
	    forKey: @"content-type"];
  [response appendContentString: [headers jsonRepresentation]];

  return response;
}

- (NSString *) msgLabels
{
  NSMutableArray *labels;
  NSEnumerator *flags;
  NSString *currentFlag;

  labels = [NSMutableArray array];

  flags = [[message objectForKey: @"flags"] objectEnumerator];
  while ((currentFlag = [flags nextObject]))
    if ([currentFlag hasPrefix: @"$label"])
      [labels addObject: [currentFlag substringFromIndex: 1]];
  
  return [labels componentsJoinedByString: @" "];
}

@end

/* UIxMailListActions */
