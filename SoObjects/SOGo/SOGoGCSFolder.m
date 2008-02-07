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

#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSUserDefaults.h>

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/SoObject.h>
#import <NGObjWeb/SoObject+SoDAV.h>
#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGObjWeb/WOApplication.h>
#import <NGObjWeb/WOResponse.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGExtensions/NSObject+Logs.h>
#import <EOControl/EOQualifier.h>
#import <GDLAccess/EOAdaptorChannel.h>
#import <GDLContentStore/GCSChannelManager.h>
#import <GDLContentStore/GCSFolderManager.h>
#import <GDLContentStore/GCSFolder.h>
#import <GDLContentStore/GCSFolderType.h>
#import <GDLContentStore/NSURL+GCS.h>
#import <SaxObjC/XMLNamespaces.h>
#import <UI/SOGoUI/SOGoFolderAdvisory.h>
#import "NSDictionary+Utilities.h"

#import "NSArray+Utilities.h"
#import "NSString+Utilities.h"

#import "SOGoContentObject.h"
#import "SOGoParentFolder.h"
#import "SOGoPermissions.h"
#import "SOGoUser.h"
#import "WORequest+SOGo.h"

#import "SOGoGCSFolder.h"

static NSString *defaultUserID = @"<default>";
static BOOL sendFolderAdvisories = NO;

@implementation SOGoGCSFolder

+ (void) initialize
{
  NSUserDefaults *ud;

  ud = [NSUserDefaults standardUserDefaults];
  sendFolderAdvisories = [ud boolForKey: @"SOGoFoldersSendEMailNotifications"];
}

+ (id) folderWithSubscriptionReference: (NSString *) reference
			   inContainer: (id) aContainer
{
  id newFolder;
  NSArray *elements, *pathElements;
  NSString *path, *objectPath, *login, *ocsName, *folderName;

  elements = [reference componentsSeparatedByString: @":"];
  login = [elements objectAtIndex: 0];
  objectPath = [elements objectAtIndex: 1];
  pathElements = [objectPath componentsSeparatedByString: @"/"];
  if ([pathElements count] > 1)
    ocsName = [pathElements objectAtIndex: 1];
  else
    ocsName = @"personal";

  path = [NSString stringWithFormat: @"/Users/%@/%@/%@",
		   login, [pathElements objectAtIndex: 0], ocsName];
  folderName = [NSString stringWithFormat: @"%@_%@", login, ocsName];
  newFolder = [self objectWithName: folderName inContainer: aContainer];
  [newFolder setOCSPath: path];
  [newFolder setOwner: login];
  if (![newFolder displayName])
    newFolder = nil;

  return newFolder;
}

- (id) init
{
  if ((self = [super init]))
    {
      ocsPath = nil;
      ocsFolder = nil;
      aclCache = [NSMutableDictionary new];
    }

  return self;
}

- (void) dealloc
{
  [ocsFolder release];
  [ocsPath release];
  [aclCache release];
  [super dealloc];
}

/* accessors */

- (void) _setDisplayNameFromRow: (NSDictionary *) row
{
  NSString *currentLogin, *ownerLogin, *primaryDN;
  NSDictionary *ownerIdentity;

  primaryDN = [row objectForKey: @"c_foldername"];
  if ([primaryDN length])
    {
      displayName = [NSMutableString new];
      if ([primaryDN isEqualToString: [container defaultFolderName]])
	[displayName appendString: [self labelForKey: primaryDN]];
      else
	[displayName appendString: primaryDN];

      currentLogin = [[context activeUser] login];
      ownerLogin = [self ownerInContext: context];
      if (![currentLogin isEqualToString: ownerLogin])
	{
	  ownerIdentity = [[SOGoUser userWithLogin: ownerLogin roles: nil]
			    primaryIdentity];
	  [displayName
	    appendString: [ownerIdentity keysWithFormat:
					   @" (%{fullName} <%{email}>)"]];
	}
    }
}

- (void) _fetchDisplayName
{
  GCSChannelManager *cm;
  EOAdaptorChannel *fc;
  NSURL *folderLocation;
  NSString *sql;
  NSArray *attrs;
  NSDictionary *row;

  cm = [GCSChannelManager defaultChannelManager];
  folderLocation
    = [[GCSFolderManager defaultFolderManager] folderInfoLocation];
  fc = [cm acquireOpenChannelForURL: folderLocation];
  if (fc)
    {
      sql
	= [NSString stringWithFormat: (@"SELECT c_foldername FROM %@"
				       @" WHERE c_path = '%@'"),
		    [folderLocation gcsTableName], ocsPath];
      [fc evaluateExpressionX: sql];
      attrs = [fc describeResults: NO];
      row = [fc fetchAttributes: attrs withZone: NULL];
      if (row)
	[self _setDisplayNameFromRow: row];
      [fc cancelFetch];
      [cm releaseChannel: fc];
    }
}

- (NSString *) displayName
{
  if (!displayName)
    [self _fetchDisplayName];

  return displayName;
}

- (void) setOCSPath: (NSString *) _path
{
  if (![ocsPath isEqualToString:_path])
    {
      if (ocsPath)
	[self warnWithFormat: @"GCS path is already set! '%@'", _path];
      ASSIGN (ocsPath, _path);
    }
}

- (NSString *) ocsPath
{
  return ocsPath;
}

- (GCSFolderManager *) folderManager
{
  static GCSFolderManager *folderManager = nil;

  if (!folderManager)
    folderManager = [GCSFolderManager defaultFolderManager];

  return folderManager;
}

- (GCSFolder *) ocsFolderForPath: (NSString *) _path
{
  return [[self folderManager] folderAtPath: _path];
}

- (BOOL) folderIsMandatory
{
  return [nameInContainer isEqualToString: @"personal"];
}

- (NSString *) davDisplayName
{
  return [self displayName];
}

- (GCSFolder *) ocsFolder
{
  GCSFolder *folder;
  NSString *userLogin;

  if (!ocsFolder)
    {
      ocsFolder = [self ocsFolderForPath: [self ocsPath]];
      userLogin = [[context activeUser] login];
      if (!ocsFolder
	  && [userLogin isEqualToString: [self ownerInContext: context]]
	  && [self folderIsMandatory]
	  && [self create])
	ocsFolder = [self ocsFolderForPath: [self ocsPath]];
      [ocsFolder retain];
    }

  if ([ocsFolder isNotNull])
    folder = ocsFolder;
  else
    folder = nil;

  return folder;
}

- (void) sendFolderAdvisoryTemplate: (NSString *) template
{
  NSString *pageName;
  SOGoUser *user;
  SOGoFolderAdvisory *page;

  user = [context activeUser];
  pageName = [NSString stringWithFormat: @"SOGoFolder%@%@Advisory",
		       [user language], template];

  page = [[WOApplication application] pageWithName: pageName
				      inContext: context];
  [page setFolderObject: self];
  [page setRecipientUID: [user login]];
  [page send];
}

- (BOOL) create
{
  NSException *result;

  result = [[self folderManager] createFolderOfType: [self folderType]
				 withName: displayName
                                 atPath: ocsPath];

  if (!result
      && [[context request] handledByDefaultHandler]
      && sendFolderAdvisories)
    [self sendFolderAdvisoryTemplate: @"Addition"];

  return (result == nil);
}

- (NSException *) delete
{
  NSException *error;

  // We just fetch our displayName since our table will use it!
  [self displayName];
  
  if ([nameInContainer isEqualToString: @"personal"])
    error = [NSException exceptionWithHTTPStatus: 403
			 reason: @"folder 'personal' cannot be deleted"];
  else
    error = [[self folderManager] deleteFolderAtPath: ocsPath];

  if (!error && sendFolderAdvisories
      && [[context request] handledByDefaultHandler])
    [self sendFolderAdvisoryTemplate: @"Removal"];

  return error;
}

- (void) renameTo: (NSString *) newName
{
  GCSChannelManager *cm;
  EOAdaptorChannel *fc;
  NSURL *folderLocation;
  NSString *sql;

  [displayName release];
  displayName = nil;

  cm = [GCSChannelManager defaultChannelManager];
  folderLocation
    = [[GCSFolderManager defaultFolderManager] folderInfoLocation];
  fc = [cm acquireOpenChannelForURL: folderLocation];
  if (fc)
    {
      sql
	= [NSString stringWithFormat: (@"UPDATE %@ SET c_foldername = '%@'"
				       @" WHERE c_path = '%@'"),
		    [folderLocation gcsTableName], newName, ocsPath];
      [fc evaluateExpressionX: sql];
      [cm releaseChannel: fc];
//       sql = [sql stringByAppendingFormat:@" WHERE %@ = '%@'", 
//                  uidColumnName, [self uid]];
    }
}

- (NSArray *) fetchContentObjectNames
{
  NSArray *fields, *records;
  
  fields = [NSArray arrayWithObject: @"c_name"];
  records = [[self ocsFolder] fetchFields:fields matchingQualifier:nil];
  if (![records isNotNull])
    {
      [self errorWithFormat: @"(%s): fetch failed!", __PRETTY_FUNCTION__];
      return nil;
    }
  if ([records isKindOfClass: [NSException class]])
    return records;
  return [records objectsForKey: @"c_name"];
}

- (BOOL) nameExistsInFolder: (NSString *) objectName
{
  NSArray *fields, *records;
  EOQualifier *qualifier;

  qualifier
    = [EOQualifier qualifierWithQualifierFormat:
                     [NSString stringWithFormat: @"c_name='%@'", objectName]];

  fields = [NSArray arrayWithObject: @"c_name"];
  records = [[self ocsFolder] fetchFields: fields
                              matchingQualifier: qualifier];
  return (records
          && ![records isKindOfClass:[NSException class]]
          && [records count] > 0);
}

- (void) deleteEntriesWithIds: (NSArray *) ids
{
  unsigned int count, max;
  NSString *currentID;
  SOGoContentObject *deleteObject;

  max = [ids count];
  for (count = 0; count < max; count++)
    {
      currentID = [ids objectAtIndex: count];
      deleteObject = [self lookupName: currentID
			   inContext: context acquire: NO];
      if (![deleteObject isKindOfClass: [NSException class]])
	{
	  if ([deleteObject respondsToSelector: @selector (prepareDelete)])
	    [deleteObject prepareDelete];
	  [deleteObject delete];
	}
    }
}

- (NSDictionary *) fetchContentStringsAndNamesOfAllObjects
{
  NSDictionary *files;
  
  files = [[self ocsFolder] fetchContentsOfAllFiles];
  if (![files isNotNull])
    {
      [self errorWithFormat:@"(%s): fetch failed!", __PRETTY_FUNCTION__];
      return nil;
    }
  if ([files isKindOfClass:[NSException class]])
    return files;
  return files;
}

/* reflection */

- (NSString *) defaultFilenameExtension
{
  /* 
     Override to add an extension to a filename
     
     Note: be careful with that, needs to be consistent with object lookup!
  */
  return nil;
}

- (NSArray *) toOneRelationshipKeys
{
  /* toOneRelationshipKeys are the 'files' contained in a folder */
  NSMutableArray *ma;
  NSArray  *names;
  NSString *name, *ext;
  unsigned i, count;
  NSRange  r;

  names = [self fetchContentObjectNames];
  count = [names count];
  ext = [self defaultFilenameExtension];
  if (count && [ext length] > 0)
    {
      ma = [NSMutableArray arrayWithCapacity: count];
      for (i = 0; i < count; i++)
        {
          name = [names objectAtIndex: i];
          r = [name rangeOfString: @"."];
          if (r.length == 0)
	    name = [NSMutableString stringWithFormat: @"%@.%@", name, ext];
          [ma addObject: name];
        }

      names = ma;
    }

  return names;
}

#warning this code should be cleaned up
#warning this code is a dup of UIxFolderActions,\
         we should remove the methods there instead
- (WOResponse *) _subscribe: (BOOL) reallyDo
		  inContext: (WOContext *) localContext
{
  WOResponse *response;
  NSMutableArray *folderSubscription;
  NSString *subscriptionPointer, *baseFolder, *folder;
  SOGoUser *activeUser;
  NSUserDefaults *ud;
  NSArray *realFolderPath;
  NSMutableDictionary *moduleSettings;

  activeUser = [localContext activeUser];
  ud = [activeUser userSettings];
  baseFolder = [container nameInContainer];
  moduleSettings = [ud objectForKey: baseFolder];

  response = [localContext response];
  if ([owner isEqualToString: [activeUser login]])
    {
      [response setStatus: 403];
      [response appendContentString:
		 @"You cannot (un)subscribe to a folder that you own!"];
    }
  else
    {
      folderSubscription
	= [moduleSettings objectForKey: @"SubscribedFolders"];
      if (!(folderSubscription
	    && [folderSubscription isKindOfClass: [NSMutableArray class]]))
	{
	  folderSubscription = [NSMutableArray array];
	  [moduleSettings setObject: folderSubscription
			  forKey: @"SubscribedFolders"];
	}

      realFolderPath = [nameInContainer componentsSeparatedByString: @"_"];
      if ([realFolderPath count] > 1)
	folder = [realFolderPath objectAtIndex: 1];
      else
	folder = [realFolderPath objectAtIndex: 0];

      subscriptionPointer = [NSString stringWithFormat: @"%@:%@/%@",
				      owner, baseFolder, folder];
      if (reallyDo)
	[folderSubscription addObjectUniquely: subscriptionPointer];
      else
	[folderSubscription removeObject: subscriptionPointer];

      [ud synchronize];

      [response setStatus: 204];
    }

  return response;
}

- (id <WOActionResults>) davSubscribe: (WOContext *) localContext
{
  return [self _subscribe: YES inContext: localContext];
}

- (id <WOActionResults>) davUnsubscribe: (WOContext *) localContext
{
  return [self _subscribe: NO inContext: localContext];
}

- (NSException *) davSetProperties: (NSDictionary *) setProps
  	     removePropertiesNamed: (NSDictionary *) removedProps
			 inContext: (WOContext *) localContext
{
  NSString *newDisplayName;

  newDisplayName = [setProps objectForKey: @"davDisplayName"];
  if ([newDisplayName length])
    [self renameTo: newDisplayName];

  return nil;
}

/* acls as a container */

- (NSArray *) aclUsersForObjectAtPath: (NSArray *) objectPathArray;
{
  EOQualifier *qualifier;
  NSString *qs;
  NSArray *records;

  qs = [NSString stringWithFormat: @"c_object = '/%@'",
		 [objectPathArray componentsJoinedByString: @"/"]];
  qualifier = [EOQualifier qualifierWithQualifierFormat: qs];
  records = [[self ocsFolder] fetchAclMatchingQualifier: qualifier];

  return [records valueForKey: @"c_uid"];
}

- (NSArray *) _fetchAclsForUser: (NSString *) uid
		forObjectAtPath: (NSString *) objectPath
{
  EOQualifier *qualifier;
  NSArray *records;
  NSMutableArray *acls;
  NSString *qs;

  qs = [NSString stringWithFormat: @"(c_object = '/%@') AND (c_uid = '%@')",
		 objectPath, uid];
  qualifier = [EOQualifier qualifierWithQualifierFormat: qs];
  records = [[self ocsFolder] fetchAclMatchingQualifier: qualifier];

  acls = [NSMutableArray array];
  if ([records count] > 0)
    [acls addObjectsFromArray: [records valueForKey: @"c_role"]];

  return acls;
}

- (void) _cacheRoles: (NSArray *) roles
	     forUser: (NSString *) uid
     forObjectAtPath: (NSString *) objectPath
{
  NSMutableDictionary *aclsForObject;

  aclsForObject = [aclCache objectForKey: objectPath];
  if (!aclsForObject)
    {
      aclsForObject = [NSMutableDictionary dictionary];
      [aclCache setObject: aclsForObject
		forKey: objectPath];
    }
  if (roles)
    [aclsForObject setObject: roles forKey: uid];
  else
    [aclsForObject removeObjectForKey: uid];
}

- (NSArray *) aclsForUser: (NSString *) uid
          forObjectAtPath: (NSArray *) objectPathArray
{
  NSArray *acls;
  NSString *objectPath;
  NSDictionary *aclsForObject;

  objectPath = [objectPathArray componentsJoinedByString: @"/"];
  aclsForObject = [aclCache objectForKey: objectPath];
  if (aclsForObject)
    acls = [aclsForObject objectForKey: uid];
  else
    acls = nil;
  if (!acls)
    {
      acls = [self _fetchAclsForUser: uid forObjectAtPath: objectPath];
      [self _cacheRoles: acls forUser: uid forObjectAtPath: objectPath];
    }

  if (!([acls count] || [uid isEqualToString: defaultUserID]))
    acls = [self aclsForUser: defaultUserID
		 forObjectAtPath: objectPathArray];

  return acls;
}

- (void) removeAclsForUsers: (NSArray *) users
            forObjectAtPath: (NSArray *) objectPathArray
{
  EOQualifier *qualifier;
  NSString *uids, *qs, *objectPath;
  NSMutableDictionary *aclsForObject;

  if ([users count] > 0)
    {
      objectPath = [objectPathArray componentsJoinedByString: @"/"];
      aclsForObject = [aclCache objectForKey: objectPath];
      if (aclsForObject)
	[aclsForObject removeObjectsForKeys: users];
      uids = [users componentsJoinedByString: @"') OR (c_uid = '"];
      qs = [NSString
	     stringWithFormat: @"(c_object = '/%@') AND ((c_uid = '%@'))",
	     objectPath, uids];
      qualifier = [EOQualifier qualifierWithQualifierFormat: qs];
      [[self ocsFolder] deleteAclMatchingQualifier: qualifier];
    }
}

- (void) _commitRoles: (NSArray *) roles
	       forUID: (NSString *) uid
	    forObject: (NSString *) objectPath
{
  EOAdaptorChannel *channel;
  GCSFolder *folder;
  NSEnumerator *userRoles;
  NSString *SQL, *currentRole;

  folder = [self ocsFolder];
  channel = [folder acquireAclChannel];
  userRoles = [roles objectEnumerator];
  currentRole = [userRoles nextObject];
  while (currentRole)
    {
      SQL = [NSString stringWithFormat: @"INSERT INTO %@"
		      @" (c_object, c_uid, c_role)"
		      @" VALUES ('/%@', '%@', '%@')",
		      [folder aclTableName],
		      objectPath, uid, currentRole];
      [channel evaluateExpressionX: SQL];
      currentRole = [userRoles nextObject];
    }

  [folder releaseChannel: channel];
}

- (void) setRoles: (NSArray *) roles
          forUser: (NSString *) uid
  forObjectAtPath: (NSArray *) objectPathArray
{
  NSString *objectPath;
  NSMutableArray *newRoles;

  [self removeAclsForUsers: [NSArray arrayWithObject: uid]
        forObjectAtPath: objectPathArray];

  newRoles = [NSMutableArray arrayWithArray: roles];
  [newRoles removeObject: SOGoRole_AuthorizedSubscriber];
  [newRoles removeObject: SOGoRole_None];
  objectPath = [objectPathArray componentsJoinedByString: @"/"];
  [self _cacheRoles: newRoles forUser: uid
	forObjectAtPath: objectPath];
  if (![newRoles count])
    [newRoles addObject: SOGoRole_None];

  [self _commitRoles: newRoles forUID: uid forObject: objectPath];
}

/* acls */
- (NSArray *) aclUsers
{
  return [self aclUsersForObjectAtPath: [self pathArrayToSOGoObject]];
}

- (NSArray *) aclsForUser: (NSString *) uid
{
  NSMutableArray *acls;
  NSArray *ownAcls, *containerAcls;

  acls = [NSMutableArray array];
  ownAcls = [self aclsForUser: uid
		  forObjectAtPath: [self pathArrayToSOGoObject]];
  [acls addObjectsFromArray: ownAcls];
  if ([container respondsToSelector: @selector (aclsForUser:)])
    {
      containerAcls = [container aclsForUser: uid];
      if ([containerAcls count] > 0)
	{
#warning this should be checked
	  if ([containerAcls containsObject: SOGoRole_ObjectEraser])
	    [acls addObject: SOGoRole_ObjectEraser];
	}
    }

  return acls;
}

- (void) setRoles: (NSArray *) roles
          forUser: (NSString *) uid
{
  return [self setRoles: roles
               forUser: uid
               forObjectAtPath: [self pathArrayToSOGoObject]];
}

- (void) removeAclsForUsers: (NSArray *) users
{
  return [self removeAclsForUsers: users
               forObjectAtPath: [self pathArrayToSOGoObject]];
}

- (NSString *) defaultUserID
{
  return defaultUserID;
}

/* description */

- (void) appendAttributesToDescription: (NSMutableString *) _ms
{
  [super appendAttributesToDescription:_ms];
  
  [_ms appendFormat:@" ocs=%@", [self ocsPath]];
}

@end /* SOGoFolder */
