/* UIxContactsListViewContainer.m - this file is part of SOGo
 *
 * Copyright (C) 2006 Inverse inc.
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
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#import <NGObjWeb/SoObjects.h>
#import <NGExtensions/NSObject+Values.h>

#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/Contacts/SOGoContactFolder.h>
#import <SoObjects/Contacts/SOGoContactFolders.h>

#import "UIxContactsListViewContainer.h"

@class SOGoContactFolders;

@implementation UIxContactsListViewContainer

- (void) _setupContext
{
  SOGoUser *activeUser;
  NSString *module;
  SOGoContactFolders *clientObject;

  activeUser = [context activeUser];
  clientObject = [[self clientObject] container];

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

- (id) init
{
  if ((self = [super init]))
    {
      selectorComponentClass = nil;
    }

  return self;
}

- (void) setSelectorComponentClass: (NSString *) aComponentClass
{
  selectorComponentClass = aComponentClass;
}

- (NSString *) selectorComponentName
{
  return selectorComponentClass;
}

- (WOElement *) selectorComponent
{
  WOElement *newComponent;
//   Class componentClass;

//   componentClass = NSClassFromString(selectorComponentClass);
//   if (componentClass)
//     {
  newComponent = [self pageWithName: selectorComponentClass];
//     }
//   else
//     newComponent = nil;

  return newComponent;
}

- (void) setCurrentFolder: (id) folder
{
  currentFolder = folder;
}

- (NSArray *) contactFolders
{
  SOGoContactFolders *folderContainer;

  folderContainer = [[self clientObject] container];

  return [folderContainer subFolders];
}

- (NSString *) currentContactFolderId
{
  return [NSString stringWithFormat: @"/%@",
                   [currentFolder nameInContainer]];
}

- (NSString *) currentContactFolderName
{
  return [currentFolder displayName];
}

- (NSString *) currentContactFolderOwner
{
  return [currentFolder ownerInContext: context];
}

- (NSString *) currentContactFolderClass
{
   return ([currentFolder isKindOfClass: [SOGoContactLDAPFolder class]]? @"remote" : @"local");
}

- (BOOL) hasContactSelectionButtons
{
  return (selectorComponentClass != nil);
}

- (BOOL) isPopup
{
  return [[self queryParameterForKey: @"popup"] boolValue];
}

- (NSString *) verticalDragHandleStyle
{
   NSString *vertical;

   [self _setupContext];
   vertical = [moduleSettings objectForKey: @"DragHandleVertical"];

   return ((vertical && [vertical intValue] > 0) ? [vertical stringByAppendingFormat: @"px"] : nil);
}

- (NSString *) horizontalDragHandleStyle
{
   NSString *horizontal;

   [self _setupContext];
   horizontal = [moduleSettings objectForKey: @"DragHandleHorizontal"];

   return ((horizontal && [horizontal intValue] > 0) ? [horizontal stringByAppendingFormat: @"px"] : nil);
}

- (NSString *) contactsListContentStyle
{
  NSString *height;

  [self _setupContext];
  height = [moduleSettings objectForKey: @"DragHandleVertical"];

   return ((height && [height intValue] > 0) ? [NSString stringWithFormat: @"%ipx", ([height intValue] - 27)] : nil);
}

@end
