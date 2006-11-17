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

#ifndef __SoObjects_SOGoObject_H__
#define __SoObjects_SOGoObject_H__

#import <Foundation/NSObject.h>

/*
  SOGoObject
  
  This is the abstract class used by all SOGo SoObjects. It contains the
  ability to track a container as well as the key the object was invoked with.
  
  In addition it provides some generic methods like user or group folder
  lookup.
*/

@class NSString, NSArray, NSMutableString, NSException, NSTimeZone;
@class GCSFolderManager, GCSFolder;
@class SOGoUserFolder, SOGoGroupsFolder;

@interface SOGoObject : NSObject
{
  NSString *nameInContainer;
  id       container;
  NSTimeZone *userTimeZone;
}

+ (id) objectWithName: (NSString *)_name inContainer:(id)_container;

- (id)initWithName:(NSString *)_name inContainer:(id)_container;

/* accessors */

- (NSString *)nameInContainer;
- (id)container;

- (NSTimeZone *) serverTimeZone;
- (NSTimeZone *) userTimeZone;
- (NSTimeZone *) userTimeZone: (NSString *) username;

/* ownership */

- (NSString *)ownerInContext:(id)_ctx;

/* looking up shared objects */

- (SOGoUserFolder *)lookupUserFolder;
- (SOGoGroupsFolder *)lookupGroupsFolder;

- (void)sleep;

/* hierarchy */

- (NSArray *)fetchSubfolders; /* uses toManyRelationshipKeys */

/* operations */

- (NSException *)delete;
- (id)GETAction:(id)_ctx;

/* etag support */

- (NSException *)matchesRequestConditionInContext:(id)_ctx;

/* description */

- (void)appendAttributesToDescription:(NSMutableString *)_ms;

@end

#endif /* __SoObjects_SOGoObject_H__ */
