/* SOGoContactFolders.m - this file is part of SOGo
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

/* exchange folder types:                   */
/* MailItems                IPF.Note
   ContactItems             IPF.Contact
   AppointmentItems         IPF.Appointment
   NoteItems                IPF.StickyNote
   TaskItems                IPF.Task
   JournalItems             IPF.Journal     */

#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/WOApplication.h>
#import <NGObjWeb/WOContext.h>
#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGObjWeb/WOResponse.h>
#import <NGObjWeb/SoUser.h>

#import <GDLContentStore/GCSFolderManager.h>
#import <GDLContentStore/GCSChannelManager.h>
#import <GDLAccess/EOAdaptorChannel.h>
#import <GDLContentStore/NSURL+GCS.h>

#import <SoObjects/SOGo/LDAPUserManager.h>
#import <SoObjects/SOGo/SOGoPermissions.h>

#import "SOGoContactGCSFolder.h"
#import "SOGoContactLDAPFolder.h"
#import "SOGoContactFolders.h"

@implementation SOGoContactFolders

- (id) init
{
  if ((self = [super init]))
    {
      contactFolders = nil;
      OCSPath = nil;
    }

  return self;
}

- (void) dealloc
{
  if (contactFolders)
    [contactFolders release];
  if (OCSPath)
    [OCSPath release];
  [super dealloc];
}

- (void) appendPersonalSources
{
  SOGoContactGCSFolder *ab;
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
      sql = [NSString
	      stringWithFormat: (@"SELECT c_path4, c_foldername FROM %@"
				 @" WHERE c_path2 = '%@'"
				 @" AND c_folder_type = 'Contact'"),
	      [folderLocation gcsTableName], [self ownerInContext: context]];
      [fc evaluateExpressionX: sql];
      attrs = [fc describeResults: NO];
      row = [fc fetchAttributes: attrs withZone: NULL];
      while (row)
        {
          ab = [SOGoContactGCSFolder contactFolderWithName: [row objectForKey: @"c_path4"]
                                     andDisplayName: [row objectForKey: @"c_foldername"]
                                     inContainer: self];
          [ab setOCSPath: [NSString stringWithFormat: @"%@/%@",
                                    OCSPath, [row objectForKey: @"c_path4"]]];
          [contactFolders setObject: ab forKey: [row objectForKey: @"c_path4"]];
          row = [fc fetchAttributes: attrs withZone: NULL];
        }

      [cm releaseChannel: fc];
//       sql = [sql stringByAppendingFormat:@" WHERE %@ = '%@'", 
//                  uidColumnName, [self uid]];
    }
}

- (void) appendSystemSources
{
  LDAPUserManager *um;
  NSEnumerator *sourceIDs;
  NSString *currentSourceID, *displayName;
  SOGoContactLDAPFolder *currentFolder;

  um = [LDAPUserManager sharedUserManager];
  sourceIDs = [[um addressBookSourceIDs] objectEnumerator]; 
  currentSourceID = [sourceIDs nextObject];
  while (currentSourceID)
    {
      displayName = [um displayNameForSourceWithID: currentSourceID];
      currentFolder = [SOGoContactLDAPFolder contactFolderWithName: currentSourceID
					     andDisplayName: displayName
					     inContainer: self];
      [currentFolder setLDAPSource: [um sourceWithID: currentSourceID]];
      [contactFolders setObject: currentFolder forKey: currentSourceID];
      currentSourceID = [sourceIDs nextObject];
    }
}

- (WOResponse *) newFolderWithName: (NSString *) name
{
  SOGoContactGCSFolder *newFolder;
  WOResponse *response;

  newFolder = [SOGoContactGCSFolder contactFolderWithName: name
                                    andDisplayName: name
                                    inContainer: self];
  if ([newFolder isKindOfClass: [NSException class]])
    response = (WOResponse *) newFolder;
  else
    {
      [newFolder setOCSPath: [NSString stringWithFormat: @"%@/%@",
                                       OCSPath, name]];
      if ([newFolder create])
        {
          response = [WOResponse new];
          [response setStatus: 201];
          [response autorelease];
        }
      else
        response = [NSException exceptionWithHTTPStatus: 400
                                reason: @"The new folder could not be created"];
    }

  return response;
}

- (void) initContactSources
{
  if (!contactFolders)
    {
      contactFolders = [NSMutableDictionary new];
      [self appendPersonalSources];
      [self appendSystemSources];
    }
}

- (id) lookupName: (NSString *) name
        inContext: (WOContext *) lookupContext
          acquire: (BOOL) acquire
{
  id obj;

  /* first check attributes directly bound to the application */
  obj = [super lookupName: name inContext: lookupContext acquire: NO];
  if (!obj)
    {
      if (!contactFolders)
        [self initContactSources];

      obj = [contactFolders objectForKey: name];
      if (!obj)
	obj = [NSException exceptionWithHTTPStatus: 404];
    }

  return obj;
}

- (NSArray *) toManyRelationshipKeys
{
  if (!contactFolders)
    [self initContactSources];

  return [contactFolders allKeys];
}

- (NSArray *) contactFolders
{
  if (!contactFolders)
    [self initContactSources];

  return [contactFolders allValues];
}

/* acls */
- (NSArray *) aclsForUser: (NSString *) uid
{
  return nil;
}

// - (NSString *) roleOfUser: (NSString *) uid
// {
//   NSArray *roles, *traversalPath;
//   NSString *objectName, *role;

//   role = nil;
//   traversalPath = [context objectForKey: @"SoRequestTraversalPath"];
//   if ([traversalPath count] > 2)
//     {
//       objectName = [traversalPath objectAtIndex: 2];
//       roles = [[context activeUser]
// 		rolesForObject: [self lookupName: objectName
// 				      inContext: context
// 				      acquire: NO]
// 		inContext: context];
//       if ([roles containsObject: SOGoRole_Assistant]
// 	  || [roles containsObject: SOGoRole_Delegate])
// 	role = SOGoRole_Assistant;
//     }

//   return role;
// }

- (BOOL) davIsCollection
{
  return YES;
}

- (void) setBaseOCSPath: (NSString *) newOCSPath
{
  if (OCSPath)
    [OCSPath release];
  OCSPath = newOCSPath;
  if (OCSPath)
    [OCSPath retain];
}

/* web interface */
- (NSString *) defaultSourceName
{
  return @"personal";
}

@end
