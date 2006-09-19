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

#import <SOGoUI/UIxComponent.h>
#import <SOGo/SOGoUser.h>

#include "common.h"
#include <NGObjWeb/SoComponent.h>
#include "UIxPageFrame.h"

@implementation UIxPageFrame

- (void)dealloc {
  [self->item  release];
  [self->title release];
  [super dealloc];
}

/* accessors */

- (void)setTitle:(NSString *)_value {
  ASSIGNCOPY(self->title, _value);
}

- (NSString *)title {
  if ([self isUIxDebugEnabled])
    return self->title;

  return [self labelForKey: @"SOGo"];
}

- (void)setItem:(id)_item {
  ASSIGN(self->item, _item);
}

- (id)item {
  return self->item;
}

- (NSString *)ownerInContext {
  return [[self clientObject] ownerInContext:[self context]];
}

/* Help URL/target */

- (NSString *)helpURL
{
  return [NSString stringWithFormat: @"help/%@.html", self->title];
}

- (NSString *)helpWindowTarget
{
  return [NSString stringWithFormat: @"Help_%@", self->title];
}

/* notifications */

- (void)sleep {
  [self->item release]; self->item = nil;
  [super sleep];
}

/* URL generation */
// TODO: I think all this should be done by the clientObject?!

- (NSString *) relativeHomePath
{
  return [self relativePathToUserFolderSubPath: @""];
}

- (NSString *)relativeCalendarPath
{
  return [self relativePathToUserFolderSubPath: @"Calendar/"];
}

- (NSString *)relativeContactsPath
{
  return [self relativePathToUserFolderSubPath: @"Contacts/"];
}

- (NSString *)relativeMailPath
{
  return [self relativePathToUserFolderSubPath: @"Mail/"];
}

- (NSString *)logoffPath
{
  return [self relativePathToUserFolderSubPath: @"logoff"];
}

/* popup handling */
- (void) setPopup: (BOOL) popup
{
  isPopup = popup;
}

- (BOOL) isPopup
{
  return isPopup;
}

/* page based JavaScript */

- (NSString *) pageJavaScriptURL
{
  WOComponent *page;
  NSString *pageJSFilename;
  
  page     = [[self context] page];
  pageJSFilename = [NSString stringWithFormat: @"%@.js",
			     NSStringFromClass([page class])];

  return [self urlForResourceFilename: pageJSFilename];
}

- (NSString *) productJavaScriptURL
{
  WOComponent *page;
  NSString *fwJSFilename;

  page = [[self context] page];
  fwJSFilename = [NSString stringWithFormat: @"%@.js",
			   [page frameworkName]];
  
  return [self urlForResourceFilename: fwJSFilename];
}

- (NSString *) productFrameworkName
{
  WOComponent *page;

  page = [[self context] page];

  return [NSString stringWithFormat: @"%@.SOGo", [page frameworkName]];
}

- (BOOL) hasPageSpecificJavaScript
{
  return ([[self pageJavaScriptURL] length] > 0);
}

- (BOOL) hasProductSpecificJavaScript
{
  return ([[self productJavaScriptURL] length] > 0);
}

- (NSString *) pageCSSURL
{
  WOComponent *page;
  NSString *pageJSFilename;
  
  page     = [[self context] page];
  pageJSFilename = [NSString stringWithFormat: @"%@.css",
			     NSStringFromClass([page class])];

  return [self urlForResourceFilename: pageJSFilename];
}

- (NSString *) productCSSURL
{
  WOComponent *page;
  NSString *fwJSFilename;

  page = [[self context] page];
  fwJSFilename = [NSString stringWithFormat: @"%@.css",
			   [page frameworkName]];
  
  return [self urlForResourceFilename: fwJSFilename];
}

- (NSString *) thisPageURL
{
  return [[[self context] page] uri];
}

- (BOOL) hasPageSpecificCSS
{
  return ([[self pageCSSURL] length] > 0);
}

- (BOOL) hasProductSpecificCSS
{
  return ([[self productCSSURL] length] > 0);
}

@end /* UIxPageFrame */
