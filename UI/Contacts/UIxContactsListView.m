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

#import <Foundation/Foundation.h>
#import <SoObjects/SOGo/NSArray+Utilities.h>
#import <SoObjects/SOGo/NSDictionary+Utilities.h>
#import <SoObjects/SOGo/NSString+Utilities.h>

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/WOContext.h>
#import <NGObjWeb/WOResponse.h>
#import <NGObjWeb/WORequest.h>
#import <NGExtensions/NSString+misc.h>
#import <NGExtensions/NSNull+misc.h>

#import <Contacts/SOGoContactObject.h>
#import <Contacts/SOGoContactFolder.h>
#import <Contacts/SOGoContactFolders.h>

#import <NGCards/NGVCard.h>
#import <NGCards/NGVList.h>
#import <SoObjects/Contacts/SOGoContactGCSEntry.h>
#import <SoObjects/Contacts/SOGoContactLDIFEntry.h>
#import <SoObjects/Contacts/SOGoContactGCSList.h>
#import <SoObjects/Contacts/SOGoContactGCSFolder.h>
#import <GDLContentStore/GCSFolder.h>

#import "UIxContactsListView.h"

@implementation UIxContactsListView

- (id) init
{
  if ((self = [super init]))
    contactInfos = nil;
  
  return self;
}

- (void) dealloc
{
  [contactInfos release];
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

- (NSString *) defaultSortKey
{
  return @"c_cn";
}

- (NSString *) sortKey
{
  NSString *s;
  
  s = [self queryParameterForKey: @"sort"];
  if (![s length])
    s = [self defaultSortKey];

  return s;
}

- (NSArray *) contactInfos
{
  id <SOGoContactFolder> folder;
  NSString *ascending, *searchText, *valueText;
  NSComparisonResult ordering;

  if (!contactInfos)
    {
      folder = [self clientObject];

      ascending = [self queryParameterForKey: @"asc"];
      ordering = ((![ascending length] || [ascending boolValue])
		  ? NSOrderedAscending : NSOrderedDescending);

      searchText = [self queryParameterForKey: @"search"];
      if ([searchText length] > 0)
	valueText = [self queryParameterForKey: @"value"];
      else
	valueText = nil;

      [contactInfos release];
      contactInfos = [folder lookupContactsWithFilter: valueText
			     sortBy: [self sortKey]
			     ordering: ordering];
      [contactInfos retain];
    }

  return contactInfos;
}

- (id <WOActionResults>) contactSearchAction
{
  id <WOActionResults> result;
  id <SOGoContactFolder> folder;
  NSString *searchText, *mail;
  NSDictionary *contact, *data;
  NSArray *contacts, *descriptors, *sortedContacts;
  NSMutableDictionary *uniqueContacts;
  unsigned int i;
  NSSortDescriptor *commonNameDescriptor;

  searchText = [self queryParameterForKey: @"search"];
  if ([searchText length] > 0)
    {
      NS_DURING
        folder = [self clientObject];
      NS_HANDLER
        if ([[localException name] isEqualToString: @"SOGoDBException"])
          folder = nil;
        else
          [localException raise];
      NS_ENDHANDLER

      uniqueContacts = [NSMutableDictionary dictionary];
      contacts = [folder lookupContactsWithFilter: searchText
                                           sortBy: @"c_cn"
                                         ordering: NSOrderedAscending];
      for (i = 0; i < [contacts count]; i++)
        {
          contact = [contacts objectAtIndex: i];
          mail = [contact objectForKey: @"c_mail"];
          if ([mail isNotNull] && [uniqueContacts objectForKey: mail] == nil)
            [uniqueContacts setObject: contact forKey: mail];
        }

      if ([uniqueContacts count] > 0)
        {
          // Sort the contacts by display name
          commonNameDescriptor = [[[NSSortDescriptor alloc] initWithKey: @"c_cn"
                                                              ascending:YES] autorelease];
          descriptors = [NSArray arrayWithObjects: commonNameDescriptor, nil];
          sortedContacts = [[uniqueContacts allValues] sortedArrayUsingDescriptors: descriptors];
        }
      else
        sortedContacts = [NSArray array];

      data = [NSDictionary dictionaryWithObjectsAndKeys: searchText, @"searchText",
           sortedContacts, @"contacts", nil];
      result = [self responseWithStatus: 200];

      [(WOResponse*)result appendContentString: [data jsonRepresentation]];
    }
  else
    result = [NSException exceptionWithHTTPStatus: 400
                                           reason: @"missing 'search' parameter"];  

  return result;
}


/* actions */

- (BOOL) shouldTakeValuesFromRequest: (WORequest *) _rq
                           inContext: (WOContext*) _c
{
  return YES;
}


- (id <WOActionResults>) exportAction
{
  WORequest *request;
  id <WOActionResults> response;
  NSArray *contactsId;
  NSEnumerator *uids;
  NSString *uid;
  id currentChild;
  SOGoContactGCSFolder *sourceFolder;
  NSMutableString *content;

  content = [NSMutableString string];
  request = [context request];
  if ( (contactsId = [request formValuesForKey: @"uid"]) )
    {
      sourceFolder = [self clientObject];
      uids = [contactsId objectEnumerator];
      while ((uid = [uids nextObject]))
        {
          currentChild = [sourceFolder lookupName: uid
                                        inContext: [self context]
                                          acquire: NO];
          if ([currentChild respondsToSelector: @selector (vCard)])
            [content appendFormat: [[currentChild vCard] ldifString]];
          else if ([currentChild respondsToSelector: @selector (vList)])
            [content appendFormat: [[currentChild vList] ldifString]];
        }
    }
  response = [[WOResponse alloc] init];
  [response autorelease];
  [response setHeader: @"text/directory" 
               forKey:@"content-type"];
  [response setHeader: @"attachment;filename=SavedContacts.ldif" 
               forKey: @"Content-Disposition"];
  [response setContent: [content dataUsingEncoding: NSUTF8StringEncoding]];
  
  return response;
}

- (id <WOActionResults>) importAction
{
  WORequest *request;
  WOResponse *response;
  id data;
  NSMutableDictionary *rc;
  NSString *fileContent;
  int imported = 0;


  request = [context request];
  rc = [NSMutableDictionary dictionary];
  data = [request formValueForKey: @"contactsFile"];
  if ([data respondsToSelector: @selector(isEqualToString:)])
    fileContent = (NSString *) data;
  else
    {
      fileContent = [[NSString alloc] initWithData: (NSData *) data 
                                          encoding: NSUTF8StringEncoding];
      [fileContent autorelease];
    }

  if (fileContent && [fileContent length])
    {
      if ([fileContent hasPrefix: @"dn:"])
        imported = [self importLdifData: fileContent];
      else if ([fileContent hasPrefix: @"BEGIN:"])
        imported = [self importVcardData: fileContent];
      else
        imported = 0;
    }

  [rc setObject: [NSNumber numberWithInt: imported]
         forKey: @"imported"];
  if (imported <= 0)
    [rc setObject: [self labelForKey: @"An error occured while importing contacts."]
           forKey: @"message"];
  else
    [rc setObject: [NSString stringWithFormat: @"%@ %d", 
     [self labelForKey: @"Imported contacts:"], imported]
           forKey: @"message"];

  response = [self responseWithStatus: 200];
  [response setHeader: @"text/html" 
               forKey: @"content-type"];
  [(WOResponse*)response appendContentString: [rc jsonRepresentation]];

  return response;
}

- (int) importLdifData: (NSString *) ldifData
{
  SOGoContactGCSFolder *folder;
  NSString *key, *value;
  NSArray *ldifContacts, *lines, *components;
  NSMutableDictionary *entry;
  NGVCard *vCard;
  NSString *uid;
  int i,j,count,linesCount;
  int rc = 0;

  folder = [self clientObject];
  ldifContacts = [ldifData componentsSeparatedByString: @"\ndn"];
  count = [ldifContacts count];

  for (i = 0; i < count; i++)
    {
      SOGoContactLDIFEntry *ldifEntry;
      entry = [NSMutableDictionary dictionary];
      lines = [[ldifContacts objectAtIndex: i] 
               componentsSeparatedByString: @"\n"];

      linesCount = [lines count];
      for (j = 0; j < linesCount; j++)
        {
          components = [[lines objectAtIndex: j] 
                 componentsSeparatedByString: @": "];
          if ([components count] == 2)
            {
              key = [components objectAtIndex: 0];
              value = [components objectAtIndex: 1];

              if ([key length] == 0)
                key = @"dn";

              [entry setObject: value forKey: key];
            }
          else
            {
              break;
            }
        }
      uid = [folder globallyUniqueObjectId];
      ldifEntry = [SOGoContactLDIFEntry contactEntryWithName: uid
                                               withLDIFEntry: entry
                                                 inContainer: folder];
      if (ldifEntry)
        {
          vCard = [ldifEntry vCard];
          if ([self importVcard: vCard])
            rc++;
          
        }
    }
  return rc;
}

- (int) importVcardData: (NSString *) vcardData
{
  NGVCard *card;
  int rc;

  rc = 0;
  card = [NGVCard parseSingleFromSource: vcardData];
  if ([self importVcard: card])
    rc = 1;

  return rc;
}

- (BOOL) importVcard: (NGVCard *) card
{
  NSString *uid, *name;
  SOGoContactGCSFolder *folder;
  NSException *ex;
  BOOL rc = NO;

  if (card)
    {
      folder = [self clientObject];
      uid = [folder globallyUniqueObjectId];
      name = [NSString stringWithFormat: @"%@.vcf", uid];
      [card setUid: uid];
      ex = [[folder ocsFolder] writeContent: [card versitString]
                                     toName: name
                                baseVersion: 0];
      if (ex)
        NSLog (@"write failed: %@", ex);
      else
        rc = YES;
    }

  return rc;
}


@end /* UIxContactsListView */
