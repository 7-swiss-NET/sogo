/*
  Copyright (C) 2004-2005 SKYRIX Software AG

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

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>

#import <NGCards/NGVCard.h>
#import <NGObjWeb/WOContext.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/WOResponse.h>
#import <NGObjWeb/SoComponent.h>
#import <NGExtensions/NSString+misc.h>

#import <Contacts/SOGoContactObject.h>
#import <Contacts/SOGoContactFolders.h>

#import <SoObjects/Mailer/SOGoMailObject.h>
#import <SoObjects/Mailer/SOGoMailAccount.h>
#import <SoObjects/Mailer/SOGoMailAccounts.h>
#import <SoObjects/SOGo/NSDictionary+URL.h>
#import <SoObjects/SOGo/NSArray+Utilities.h>
#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/SOGo/SOGoUserFolder.h>
#import <SOGoUI/UIxComponent.h>

#import "UIxMailMainFrame.h"

@implementation UIxMailMainFrame

- (void) _setupContext
{
  SOGoUser *activeUser;
  NSString *login, *module;
  SOGoMailAccounts *clientObject;

  activeUser = [context activeUser];
  login = [activeUser login];
  clientObject = [self clientObject];

  module = [clientObject nameInContainer];

  ud = [activeUser userSettings];
  moduleSettings = [ud objectForKey: module];
  if (!moduleSettings)
    {
      moduleSettings = [NSMutableDictionary new];
      [moduleSettings autorelease];
    }
  [ud setObject: moduleSettings forKey: module];
}

/* accessors */
- (NSString *) mailAccounts
{
  NSArray *accounts, *accountNames;

  accounts = [[context activeUser] mailAccounts];
  accountNames = [accounts objectsForKey: @"name"];

  return [accountNames jsonRepresentation];
}

- (NSString *) quotaSupport
{
  NSEnumerator *accountNames;
  NSMutableArray *quotas;
  NSString *currentAccount;
  SOGoMailAccounts *co;
  BOOL supportsQuota;

  co = [self clientObject];
  accountNames = [[co toManyRelationshipKeys] objectEnumerator];

  quotas = [NSMutableArray array];
  while ((currentAccount = [accountNames nextObject]))
    {
      supportsQuota = [[co lookupName: currentAccount
			   inContext: context
			   acquire: NO] supportsQuotas];
      [quotas addObject: [NSNumber numberWithInt: supportsQuota]];
    }

  return [quotas jsonRepresentation];
}

- (NSString *) pageFormURL
{
  NSString *u;
  NSRange  r;
  
  u = [[[self context] request] uri];
  if ((r = [u rangeOfString:@"?"]).length > 0) {
    /* has query parameters */
    // TODO: this is ugly, create reusable link facility in SOPE
    // TODO: remove 'search' and 'filterpopup', preserve sorting
    NSMutableString *ms;
    NSArray  *qp;
    unsigned i, count;
    
    qp    = [[u substringFromIndex:(r.location + r.length)] 
	        componentsSeparatedByString:@"&"];
    count = [qp count];
    ms    = [NSMutableString stringWithCapacity:count * 12];
    
    for (i = 0; i < count; i++) {
      NSString *s;
      
      s = [qp objectAtIndex:i];
      
      /* filter out */
      if ([s hasPrefix:@"search="]) continue;
      if ([s hasPrefix:@"filterpopup="]) continue;
      
      if ([ms length] > 0) [ms appendString:@"&"];
      [ms appendString:s];
    }
    
    if ([ms length] == 0) {
      /* no other query params */
      u = [u substringToIndex:r.location];
    }
    else {
      u = [u substringToIndex:r.location + r.length];
      u = [u stringByAppendingString:ms];
    }
    return u;
  }
  return [u hasSuffix:@"/"] ? @"view" : @"#";
}

- (id <WOActionResults>) composeAction
{
  id <SOGoContactObject> contact;
  NSArray *accounts, *contactsId;
  NSString *firstAccount, *newLocation, *parameters, *folderId, *uid, *email;
  NSMutableString *fn;
  NSEnumerator *uids;
  NSMutableArray *addresses;
  NGVCard *card;
  SOGoMailAccounts *co;
  SOGoContactFolders *folders;
  SOGoParentFolder *folder;
  WORequest *request;

  parameters = nil;
  co = [self clientObject];
  
  // We use the first mail account
  accounts = [[context activeUser] mailAccounts];
  firstAccount = [[accounts objectsForKey: @"name"] objectAtIndex: 0];
  request = [context request];
  
  if ((folderId = [request formValueForKey: @"folder"]) &&
      (contactsId = [request formValuesForKey: @"uid"]))
    {
      // Retrieve the email addresses from the specified address book
      // and contact IDs
      folders = [[[self clientObject] container] privateContacts: @"Contacts"
						 inContext: nil];
      folder = [folders lookupName: folderId
			inContext: nil
			acquire: NO];
      if (folder)
	{
	  uids = [contactsId objectEnumerator];
	  uid = [uids nextObject];
        
	  addresses = [NSMutableArray new];
        
	  while (uid)
	    {
	      contact = [folder lookupName: uid
				inContext: [self context]
				acquire: NO];
	      if (![(NSObject*)contact isKindOfClass: [NSException class]])
		{
		  // We fetch the preferred email address of the contact or
		  // the first defined email address
		  card = [contact vCard];
		  email = [card preferredEMail];
		  if (email == nil)
		    email = (NSString*)[card firstChildWithTag: @"EMAIL"];
		  if (email)
		    {
		      email = [NSString stringWithFormat: @"<%@>", email];
		      fn = [NSMutableString stringWithString: [card fn]];
		      if (fn)
			{
			  [fn appendFormat: @" %@", email];
			  [addresses addObject: fn];
			}
		      else
			[addresses addObject: email];
		    }
		}
	      uid = [uids nextObject];
	    }

	  if ([addresses count] > 0)
	    parameters = [NSString stringWithFormat: @"?mailto=%@", [addresses componentsJoinedByString: @","]];
	}
    }
  else if ([[request formValues] objectForKey: @"mailto"])
    // We use the email addresses defined in the request
    parameters = [[request formValues] asURLParameters];
  
  if (!parameters)
    // No parameter passed; simply open the compose window
    parameters = @"?mailto=";

  newLocation = [NSString stringWithFormat: @"%@/%@/compose%@",
			  [co baseURLInContext: context],
			  firstAccount,
			  parameters];

  return [self redirectToLocation: newLocation];
}

- (WOResponse *) getFoldersStateAction
{
  NSString *expandedFolders;

  [self _setupContext];
  expandedFolders = [moduleSettings objectForKey: @"ExpandedFolders"];

  return [self responseWithStatus: 200 andString: expandedFolders];
}

- (NSString *) verticalDragHandleStyle
{
   NSString *vertical;

   [self _setupContext];
   vertical = [moduleSettings objectForKey: @"DragHandleVertical"];
   
   return (vertical ? [vertical stringByAppendingFormat: @"px"] : nil);
}

- (NSString *) horizontalDragHandleStyle
{
   NSString *horizontal;

   [self _setupContext];
   horizontal = [moduleSettings objectForKey: @"DragHandleHorizontal"];

   return (horizontal ? [horizontal stringByAppendingFormat: @"px"] : nil);
}

- (NSString *) mailboxContentStyle
{
   NSString *height;

   [self _setupContext];
   height = [moduleSettings objectForKey: @"DragHandleVertical"];

   return (height ? [NSString stringWithFormat: @"%ipx", ([height intValue] - 27)] : nil);
}

- (WOResponse *) saveDragHandleStateAction
{
  WORequest *request;
  NSString *dragHandle;
  
  [self _setupContext];
  request = [context request];

  if ((dragHandle = [request formValueForKey: @"vertical"]) != nil)
    [moduleSettings setObject: dragHandle
		    forKey: @"DragHandleVertical"];
  else if ((dragHandle = [request formValueForKey: @"horizontal"]) != nil)
    [moduleSettings setObject: dragHandle
		    forKey: @"DragHandleHorizontal"];
  else
    return [self responseWithStatus: 400];
  
  [ud synchronize];
  
  return [self responseWithStatus: 204];
}

- (WOResponse *) saveFoldersStateAction
{
  WORequest *request;
  NSString *expandedFolders;
  
  [self _setupContext];
  request = [context request];
  expandedFolders = [request formValueForKey: @"expandedFolders"];

  [moduleSettings setObject: expandedFolders
		  forKey: @"ExpandedFolders"];

  [ud synchronize];

  return [self responseWithStatus: 204];
}

@end /* UIxMailMainFrame */
