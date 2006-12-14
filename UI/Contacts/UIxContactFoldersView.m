/* UIxContactFoldersView.m - this file is part of SOGo
 *
 * Copyright (C) 2006 Inverse groupe conseil
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

#import <Foundation/NSString.h>

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/SoObject.h>
#import <NGObjWeb/WOResponse.h>

#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/SOGo/NSString+Utilities.h>
#import <SoObjects/Contacts/SOGoContactFolders.h>
#import <SoObjects/Contacts/SOGoContactFolder.h>

#import "common.h"

#import "UIxContactFoldersView.h"

@implementation UIxContactFoldersView

- (id) _selectActionForApplication: (NSString *) actionName
{
  SOGoContactFolders *folders;
  NSString *url, *action;
  WORequest *request;

  folders = [self clientObject];
  action = [NSString stringWithFormat: @"../%@/%@",
                     [folders defaultSourceName],
                     actionName];

  request = [[self context] request];

  url = [[request uri] composeURLWithAction: action
                       parameters: [self queryParameters]
                       andHash: NO];

  return [self redirectToLocation: url];
}

- (id) defaultAction
{
  return [self _selectActionForApplication: @"view"];
}

- (id) newAction
{
  return [self _selectActionForApplication: @"new"];
}

- (id) selectForSchedulerAction
{
  return [self _selectActionForApplication: @"scheduler-contacts"];
}

- (id) selectForMailerAction
{
  return [self _selectActionForApplication: @"mailer-contacts"];
}

- (id) selectForCalendarsAction
{
  return [self _selectActionForApplication: @"calendars-contacts"];
}

- (id) selectForAddressBooksAction
{
  return [self _selectActionForApplication: @"addressbooks-contacts"];
}

- (id) selectForAclsAction
{
  return [self _selectActionForApplication: @"acls-contacts"];
}

- (NSArray *) _searchResults: (NSString *) contact
{
  NSMutableArray *results;
  SOGoContactFolders *topFolder;
  NSEnumerator *sogoContactFolders;
  id <SOGoContactFolder> currentFolder;

  results = [NSMutableArray new];
  [results autorelease];

  topFolder = [self clientObject];
  sogoContactFolders = [[topFolder contactFolders] objectEnumerator];
  currentFolder = [sogoContactFolders nextObject];
  while (currentFolder)
    {
      [results addObjectsFromArray: [currentFolder
                                      lookupContactsWithFilter: contact
                                      sortBy: @"cn"
                                      ordering: NSOrderedAscending]];
      currentFolder = [sogoContactFolders nextObject];
    }
  [topFolder release];

  return results;
}

- (NSString *) _emailForResult: (NSDictionary *) result
{
  NSMutableString *email;
  NSString *name, *mail;

  email = [NSMutableString string];
  name = [result objectForKey: @"displayName"];
  if (![name length])
    name = [result objectForKey: @"cn"];
  mail = [result objectForKey: @"mail"];
  if ([name length])
    [email appendFormat: @"%@ <%@>", name, mail];
  else
    [email appendString: mail];

  return email;
}

- (NSDictionary *) _nextResultWithUid: (NSEnumerator *) results
{
  NSDictionary *result, *possibleResult;

  result = nil;
  possibleResult = [results nextObject];
  while (possibleResult && !result)
    if ([[possibleResult objectForKey: @"c_uid"] length])
      result = possibleResult;
    else
      possibleResult = [results nextObject];

  return result;
}

- (WOResponse *) _responseForResults: (NSArray *) results
{
  WOResponse *response;
  NSString *email, *responseString;
  NSDictionary *result;

  response = [context response];

  if ([results count])
    {
      result = [self _nextResultWithUid: [results objectEnumerator]];
      if (!result)
        result = [results objectAtIndex: 0];
      email = [self _emailForResult: result];
      responseString = [NSString stringWithFormat: @"%@:%@",
                                 [result objectForKey: @"c_uid"],
                                 email];
      [response setStatus: 200];
      [response setHeader: @"text/plain; charset=iso-8859-1"
                forKey: @"Content-Type"];
      [response appendContentString: responseString];
    }
  else
    [response setStatus: 404];

  return response;
}

- (id <WOActionResults>) contactSearchAction
{
  NSString *contact;
  id <WOActionResults> result;

  contact = [self queryParameterForKey: @"search"];
  if ([contact length])
    result = [self _responseForResults: [self _searchResults: contact]];
  else
    result = [NSException exceptionWithHTTPStatus: 400
                          reason: @"missing 'search' parameter"];

  return result;
}

- (id <WOActionResults>) updateAdditionalAddressBooksAction
{
  WOResponse *response;
  NSUserDefaults *ud;

  ud = [[context activeUser] userDefaults];
  [ud setObject: [self queryParameterForKey: @"ids"]
      forKey: @"additionaladdressbooks"];
  [ud synchronize];
  response = [context response];
  [response setStatus: 200];
  [response setHeader: @"text/html; charset=\"utf-8\"" forKey: @"content-type"];

  return response;
}

@end
