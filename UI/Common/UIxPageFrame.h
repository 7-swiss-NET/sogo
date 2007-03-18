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

#ifndef UIXPAGEFRAME_H
#define UIXPAGEFRAME_H

#import <SOGoUI/UIxComponent.h>

@interface WOComponent (PopupExtension)

- (BOOL) isPopup;

@end

@interface UIxPageFrame : UIxComponent
{
  NSString *title;
  NSString *toolbar;
  id item;
  BOOL isPopup;
}

- (NSString *) pageJavaScriptURL;
- (NSString *) productJavaScriptURL;
- (BOOL) hasPageSpecificJavaScript;
- (BOOL) hasProductSpecificJavaScript;

- (NSString *) pageCSSURL;
- (NSString *) productCSSURL;
- (BOOL) hasPageSpecificCSS;
- (BOOL) hasProductSpecificCSS;

- (NSString *) productFrameworkName;

- (void) setPopup: (BOOL) popup;
- (BOOL) isPopup;

- (void) setToolbar: (NSString *) newToolbar;
- (NSString *) toolbar;

@end

#endif /* UIXPAGEFRAME_H */
