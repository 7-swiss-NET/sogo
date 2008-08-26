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

#import <Foundation/NSException.h>
#import <Foundation/NSUserDefaults.h>

#import <NGObjWeb/WOApplication.h>
#import <NGObjWeb/WOContext.h>
#import <NGObjWeb/WOCookie.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/WOResponse.h>

#import <NGExtensions/NGBase64Coding.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGExtensions/NSString+misc.h>
#import <NGExtensions/NSObject+Logs.h>

#import <SoObjects/SOGo/SOGoWebAuthenticator.h>
#import <SoObjects/SOGo/SOGoUser.h>

#import "SOGoRootPage.h"

@interface SOGoRootPage (crashAdditions)

- (void) segfault;

@end

@implementation SOGoRootPage

/* accessors */

- (NSString *) connectURL
{
  return [NSString stringWithFormat: @"%@connect", [self applicationPath]];
}

/* actions */
- (id <WOActionResults>) connectAction
{
  WOResponse *response;
  WORequest *request;
  WOCookie *authCookie;
  SOGoWebAuthenticator *auth;
  NSString *cookieValue, *cookieString;
  NSString *userName, *password;

  auth = [[WOApplication application]
	   authenticatorInContext: context];
  request = [context request];
  userName = [request formValueForKey: @"userName"];
  password = [request formValueForKey: @"password"];
  if ([auth checkLogin: userName password: password])
    {
      response = [self responseWith204];
      cookieString = [NSString stringWithFormat: @"%@:%@",
			       userName, password];
      cookieValue = [NSString stringWithFormat: @"basic %@",
			      [cookieString stringByEncodingBase64]];
      authCookie = [WOCookie cookieWithName: [auth cookieNameInContext: context]
			     value: cookieValue];
      [authCookie setPath: @"/"];
      [response addCookie: authCookie];
    }
  else
    response = [self responseWithStatus: 403];

  return response;
}

- (id <WOActionResults>) defaultAction
{
  id <WOActionResults> response;
  NSString *login, *oldLocation;

  login = [[context activeUser] login];
  if (!login || [login isEqualToString: @"anonymous"])
    response = self;
  else
    {
      oldLocation = [[self clientObject] baseURLInContext: context];
      response
	= [self redirectToLocation: [NSString stringWithFormat: @"%@/%@",
					      oldLocation, login]];
    }

  return response;
}

- (BOOL) isPublicInContext: (WOContext *) localContext
{
  return YES;
}

- (id <WOActionResults>) crashAction
{
  [self segfault];

  return nil;
}

- (id <WOActionResults>) exceptionAction
{
  return (id <WOActionResults>)
    [NSException exceptionWithName: @"ExceptionAction"
		 reason: @"This exception is brought to you by SOGo"
		 userInfo: nil];
}

- (id <WOActionResults>) raisedExceptionAction
{
  [NSException raise: @"ExceptionAction"
	       format: @"This exception is brought to you by SOGo"];

  return nil;
}

- (NSString *) loginSuffix
{
  NSUserDefaults *ud;

  ud = [NSUserDefaults standardUserDefaults];

  return [ud stringForKey: @"SOGoLoginSuffix"];
}

- (BOOL) hasLoginSuffix
{
  return ([[self loginSuffix] length]);
}

@end /* SOGoRootPage */
