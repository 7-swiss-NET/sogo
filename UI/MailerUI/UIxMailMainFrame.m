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

#import <Foundation/NSUserDefaults.h>
#import <NGObjWeb/WOContext.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/SoComponent.h>
#import <NGExtensions/NSString+misc.h>

#import <SoObjects/Mailer/SOGoMailObject.h>
#import <SoObjects/Mailer/SOGoMailAccounts.h>
#import <SoObjects/SOGo/NSDictionary+URL.h>
#import <SoObjects/SOGo/NSArray+Utilities.h>
#import <SoObjects/SOGo/SOGoUser.h>
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
  NSArray *accounts;
  NSString *firstAccount, *newLocation;
  SOGoMailAccounts *co;
  NSDictionary *formValues;

  co = [self clientObject];
  accounts = [[context activeUser] mailAccounts];
  firstAccount = [[accounts objectsForKey: @"name"] objectAtIndex: 0];
  formValues = [[context request] formValues];
  newLocation = [NSString stringWithFormat: @"%@/%@/compose%@",
			  [co baseURLInContext: context],
			  firstAccount,
			  [formValues asURLParameters]];

  return [self redirectToLocation: newLocation];
}

- (WOResponse *) getFoldersStateAction
{
  NSString *expandedFolders;

  [self _setupContext];
  expandedFolders = [moduleSettings objectForKey: @"ExpandedFolders"];

  return [self responseWithStatus: 200 andString: expandedFolders];
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
