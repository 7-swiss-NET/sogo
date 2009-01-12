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

#ifndef __SOGo_SOGoGCSFolder_H__
#define __SOGo_SOGoGCSFolder_H__

#import "SOGoFolder.h"

@class NSArray;
@class NSDictionary;
@class NSMutableDictionary;
@class NSString;

@class GCSFolder;
@class WOContext;
@class WOResponse;

/*
  SOGoGCSFolder
  
  A common superclass for folders stored in GCS. Already deals with all GCS
  folder specific things.
  
  Important: folders should NOT retain the context! Otherwise you might get
             cyclic references.
*/

@interface SOGoGCSFolder : SOGoFolder
{
  NSString *ocsPath;
  GCSFolder *ocsFolder;
  NSMutableDictionary *childRecords;
  NSMutableDictionary *aclCache;
}

+ (id) folderWithSubscriptionReference: (NSString *) reference
			   inContainer: (id) aContainer;

/* accessors */

- (void) setOCSPath: (NSString *)_Path;
- (NSString *) ocsPath;

- (GCSFolder *) ocsFolderForPath: (NSString *)_path;
- (GCSFolder *) ocsFolder;

- (NSString *) folderReference;
- (NSArray *) pathArrayToFolder;

/* lower level fetches */
- (BOOL) nameExistsInFolder: (NSString *) objectName;

- (void) deleteEntriesWithIds: (NSArray *) ids;

- (Class) objectClassForComponentName: (NSString *) componentName;
- (Class) objectClassForContent: (NSString *) content;

- (NSArray *) fetchContentObjectNames;

/* folder type */

- (BOOL) folderIsMandatory;

- (BOOL) create;
- (NSException *) delete;
- (void) renameTo: (NSString *) newName;

- (WOResponse *) subscribe: (BOOL) reallyDo
	      inTheNamesOf: (NSArray *) delegatedUsers
	fromMailInvitation: (BOOL) isMailInvitation
		 inContext: (WOContext *) localContext;

/* acls as a container */
- (NSArray *) aclUsersForObjectAtPath: (NSArray *) objectPathArray;
- (NSArray *) aclsForUser: (NSString *) uid
          forObjectAtPath: (NSArray *) objectPathArray;
- (void) setRoles: (NSArray *) roles
          forUser: (NSString *) uid
  forObjectAtPath: (NSArray *) objectPathArray;
- (void) removeAclsForUsers: (NSArray *) users
            forObjectAtPath: (NSArray *) objectPathArray;

/* advisories */
- (void) sendFolderAdvisoryTemplate: (NSString *) template;

@end

#endif /* __SOGo_SOGoGCSFolder_H__ */
