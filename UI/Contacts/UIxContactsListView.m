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

#import <Contacts/SOGoContactObject.h>
#import <Contacts/SOGoContactFolder.h>
#import <Contacts/SOGoContactFolders.h>

#import "common.h"

#import "UIxContactsListView.h"

@implementation UIxContactsListView

- (id) init
{
  if ((self = [super init]))
    {
      selectorComponentClass = nil;
    }

  return self;
}

- (void) dealloc
{
  if (searchText)
    [searchText release];
  [super dealloc];
}

/* accessors */

- (void) setCurrentContact: (NSDictionary *) _contact
{
  currentContact = _contact;
}

- (NSDictionary *) currentContact
{
  return currentContact;
}

- (void) setSearchText: (NSString *) _txt
{
  ASSIGNCOPY (searchText, _txt);
}

- (id) searchText
{
  if (!searchText)
    [self setSearchText: [self queryParameterForKey:@"search"]];

  return searchText;
}

- (NSString *) selectorComponentClass
{
  return selectorComponentClass;
}

- (id) mailerContactsAction
{
  selectorComponentClass = @"UIxContactsMailerSelection";

  return self;
}

- (id) calendarsContactsAction
{
  selectorComponentClass = @"UIxContactsCalendarsSelection";

  return self;
}

- (NSString *) defaultSortKey
{
  return @"fn";
}

- (NSString *) displayName
{
  NSString *displayName;

  displayName = [currentContact objectForKey: @"displayName"];
  if (!(displayName && [displayName length] > 0))
    displayName = [currentContact objectForKey: @"cn"];

  return displayName;
}

- (NSString *) sortKey
{
  NSString *s;
  
  s = [self queryParameterForKey: @"sort"];
  if ([s length] == 0)
    s = [self defaultSortKey];

  return s;
}

- (NSComparisonResult) sortOrdering
{
  return ([[self queryParameterForKey:@"desc"] boolValue]
          ? NSOrderedDescending
          : NSOrderedAscending);
}

- (NSArray *) contactInfos
{
  id <SOGoContactFolder> folder;

  folder = [self clientObject];

  return [folder lookupContactsWithFilter: [self searchText]
                 sortBy: [self sortKey]
                 ordering: [self sortOrdering]];
}

/* notifications */

- (void) sleep
{
  if (searchText)
    {
      [searchText release];
      searchText = nil;
    }
  currentContact = nil;
//   [allRecords release];
//   allRecords = nil;
//   [filteredRecords release];
//   filteredRecords = nil;
  [super sleep];
}

/* actions */

- (BOOL) shouldTakeValuesFromRequest: (WORequest *) _rq
                           inContext: (WOContext*) _c
{
  return YES;
}

- (BOOL) isPopup
{
  return [[self queryParameterForKey: @"popup"] boolValue];
}

@end /* UIxContactsListView */
