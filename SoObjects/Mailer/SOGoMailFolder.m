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

#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSTask.h>

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGObjWeb/WOResponse.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGExtensions/NSURL+misc.h>
#import <NGExtensions/NSObject+Logs.h>
#import <NGExtensions/NSString+misc.h>
#import <NGExtensions/NSFileManager+Extensions.h>

#import <DOM/DOMElement.h>
#import <DOM/DOMProtocols.h>
#import <SaxObjC/XMLNamespaces.h>

#import <EOControl/EOSortOrdering.h>

#import <NGImap4/NGImap4Connection.h>
#import <NGImap4/NGImap4Client.h>

#import <SOGo/DOMNode+SOGo.h>
#import <SOGo/NSArray+Utilities.h>
#import <SOGo/NSString+Utilities.h>
#import <SOGo/NSString+DAV.h>
#import <SOGo/NSArray+DAV.h>
#import <SOGo/NSObject+DAV.h>
#import <SOGo/SOGoDomainDefaults.h>
#import <SOGo/SOGoPermissions.h>
#import <SOGo/SOGoSystemDefaults.h>
#import <SOGo/SOGoUser.h>
#import <SOGo/SOGoUserSettings.h>
#import <SOGo/WORequest+SOGo.h>
#import <SOGo/WOResponse+SOGo.h>

#import "EOQualifier+MailDAV.h"
#import "SOGoMailObject.h"
#import "SOGoMailAccount.h"
#import "SOGoMailManager.h"
#import "SOGoMailFolder.h"
#import "SOGoTrashFolder.h"

#define XMLNS_INVERSEDAV @"urn:inverse:params:xml:ns:inverse-dav"

static NSString *defaultUserID =  @"anyone";

@interface NGImap4Connection (PrivateMethods)

- (NSString *) imap4FolderNameForURL: (NSURL *) url;

@end

@implementation SOGoMailFolder

- (BOOL)   _path: (NSString *) path
  isInNamespaces: (NSArray *) namespaces
{
  int count, max;
  BOOL rc;

  rc = NO;

  max = [namespaces count];
  for (count = 0; !rc && count < max; count++)
    rc = [path hasPrefix: [namespaces objectAtIndex: count]];

  return rc;
}

- (void) _adjustOwner
{
  SOGoMailAccount *mailAccount;
  NSString *path;
  NSArray *names;

  mailAccount = [self mailAccountFolder];
  path = [[self imap4Connection] imap4FolderNameForURL: [self imap4URL]];

  if ([self _path: path
            isInNamespaces: [mailAccount sharedFolderNamespaces]])
    [self setOwner: @"nobody"];
  else if ([self _path: path
                 isInNamespaces: [mailAccount otherUsersFolderNamespaces]])
    {
      names = [path componentsSeparatedByString: @"/"];
      if ([names count] > 1)
        [self setOwner: [names objectAtIndex: 1]];
      else
        [self setOwner: @"nobody"];
    }
}

- (id) initWithName: (NSString *) newName
	inContainer: (id) newContainer
{
  if ((self = [super initWithName: newName
		     inContainer: newContainer]))
    {
      [self _adjustOwner];
      mailboxACL = nil;
    }

  return self;
}

- (void) dealloc
{
  [filenames release];
  [folderType release];
  [mailboxACL release];
  [super dealloc];
}

/* IMAP4 */

- (NSString *) relativeImap4Name
{
  return [[nameInContainer substringFromIndex: 6] fromCSSIdentifier];
}

- (NSString *) absoluteImap4Name
{
  NSString *name;

  name = [[self imap4URL] path];
  if (![name hasSuffix: @"/"])
    name = [name stringByAppendingString: @"/"];

  return name;
}

- (NSMutableString *) imap4URLString
{
  NSMutableString *urlString;

  urlString = [super imap4URLString];
  [urlString appendString: @"/"];

  return urlString;
}

/* listing the available folders */

- (NSArray *) toManyRelationshipKeys
{
  NSArray *subfolders;

  subfolders = [[self subfolders] stringsWithFormat: @"folder%@"];

  return [subfolders resultsOfSelector: @selector (asCSSIdentifier)];
}

- (NSArray *) subfolders
{
  return [[self imap4Connection] subfoldersForURL: [self imap4URL]];
}

- (BOOL) isSpecialFolder
{
  return NO;
}

- (NSArray *) allFolderPaths
{
  NSMutableArray *deepSubfolders;
  NSEnumerator *folderNames;
  NSArray *result;
  NSString *currentFolderName, *prefix;

  deepSubfolders = [NSMutableArray array];

  prefix = [self absoluteImap4Name];

  result = [[self mailAccountFolder] allFolderPaths];
  folderNames = [result objectEnumerator];
  while ((currentFolderName = [folderNames nextObject]))
    if ([currentFolderName hasPrefix: prefix])
      [deepSubfolders addObject: currentFolderName];
  [deepSubfolders sortUsingSelector: @selector (compare:)];

  return deepSubfolders;
}

- (NSArray *) allFolderURLs
{
  NSURL *selfURL, *currentURL;
  NSMutableArray *subfoldersURL;
  NSEnumerator *subfolders;
  NSString *currentFolder;

  subfoldersURL = [NSMutableArray array];
  selfURL = [self imap4URL];
  subfolders = [[self allFolderPaths] objectEnumerator];
  currentFolder = [subfolders nextObject];
  while (currentFolder)
    {
      currentURL = [[NSURL alloc]
		     initWithScheme: [selfURL scheme]
		     host: [selfURL host]
		     path: currentFolder];
      [currentURL autorelease];
      [subfoldersURL addObject: currentURL];
      currentFolder = [subfolders nextObject];
    }

  return subfoldersURL;
}

- (NSString *) davContentType
{
  return @"httpd/unix-directory";
}

- (NSArray *) toOneRelationshipKeys
{
  NSArray *uids;
  unsigned int count, max;
  NSString *filename;

  if (!filenames)
    {
      filenames = [NSMutableArray new];
      if ([[self imap4Connection] doesMailboxExistAtURL: [self imap4URL]])
        {
          uids = [self fetchUIDsMatchingQualifier: nil sortOrdering: @"DATE"];
          if (![uids isKindOfClass: [NSException class]])
            {
              max = [uids count];
              for (count = 0; count < max; count++)
                {
                  filename = [NSString stringWithFormat: @"%@.eml",
                                    [uids objectAtIndex: count]];
                  [filenames addObject: filename];
                }
            }
        }
    }

  return filenames;
}

/* messages */
- (NSException *) deleteUIDs: (NSArray *) uids
		   inContext: (id) localContext
{
  SOGoMailFolder *trashFolder;
  NGImap4Client *client;
  NSString *folderName;
  NSException *error;
  id result;
  BOOL b;

  trashFolder = [[self mailAccountFolder] trashFolderInContext: localContext];
  if ([trashFolder isNotNull])
    {
      if ([trashFolder isKindOfClass: [NSException class]])
	error = (NSException *) trashFolder;
      else
	{
	  client = [[self imap4Connection] client];
	  [imap4 selectFolder: [self imap4URL]];
	  folderName = [imap4 imap4FolderNameForURL: [trashFolder imap4URL]];
	  b = YES;

	  // If we are deleting messages within the Trash folder itself, we
	  // do not, of course, try to move messages to the Trash folder.
	  if (![folderName isEqualToString: [self relativeImap4Name]])
	    {
	      // If our Trash folder doesn't exist when we try to copy messages
	      // to it, we create it.
	      result = [[client status: folderName  flags: [NSArray arrayWithObject: @"UIDVALIDITY"]]
			 objectForKey: @"result"];
	      
	      if (![result boolValue])
		result = [[self imap4Connection] createMailbox: folderName  atURL: [[self mailAccountFolder] imap4URL]];
	      
	      if (!result || [result boolValue])
		result = [client copyUids: uids toFolder: folderName];
	      
	      b = [[result valueForKey: @"result"] boolValue];
	    }
	  
	  if (b)
	    {
	      result = [client storeFlags: [NSArray arrayWithObject: @"Deleted"]
			       forUIDs: uids addOrRemove: YES];
	      if ([[result valueForKey: @"result"] boolValue])
		{
		  [self markForExpunge];
		  [trashFolder flushMailCaches];
		  error = nil;
		}
	      else
		error
		  = [NSException exceptionWithHTTPStatus:500
				 reason: @"Could not mark UIDs as Deleted"];
	    }
	  else
	    error = [NSException exceptionWithHTTPStatus:500
				 reason: @"Could not copy UIDs"];
	}
    }
  else
    error = [NSException exceptionWithHTTPStatus: 500
			 reason: @"Did not find Trash folder!"];

  return error;
}

- (WOResponse *) archiveUIDs: (NSArray *) uids
              inArchiveNamed: (NSString *) archiveName
                   inContext: (id) localContext
{
  NSException *error;
  NSFileManager *fm;
  NSString *spoolPath, *fileName, *zipPath, *qpFileName;
  NSDictionary *msgs;
  NSArray *messages;
  NSData *content, *zipContent;
  NSTask *zipTask;
  NSMutableArray *zipTaskArguments;
  WOResponse *response;
  int i;

  if (!archiveName)
    archiveName = @"SavedMessages.zip";

#warning this method should be rewritten according to our coding styles  
  spoolPath = [self userSpoolFolderPath];
  if (![self ensureSpoolFolderPath]) {
    [self errorWithFormat: @"spool directory '%@' doesn't exist", spoolPath];
    error = [NSException exceptionWithHTTPStatus: 500 
                                          reason: @"spool directory does not exist"];
    return (WOResponse *)error;
  }

  zipPath = [[SOGoSystemDefaults sharedSystemDefaults] zipPath];
  fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath: zipPath]) {
    error = [NSException exceptionWithHTTPStatus: 500 
                                          reason: @"zip not available"];
    return (WOResponse *)error;
  }
  
  zipTask = [[NSTask alloc] init];
  [zipTask setCurrentDirectoryPath: spoolPath];
  [zipTask setLaunchPath: zipPath];
  
  zipTaskArguments = [NSMutableArray arrayWithObjects: nil];
  [zipTaskArguments addObject: @"SavedMessages.zip"];

  msgs = (NSDictionary *)[self fetchUIDs: uids  
                                   parts: [NSArray arrayWithObject: @"RFC822"]];
  messages = [msgs objectForKey: @"fetch"];

  for (i = 0; i < [messages count]; i++) {
    content = [[messages objectAtIndex: i] objectForKey: @"message"];
    fileName = [NSString stringWithFormat:@"%@/%@.eml", spoolPath, [uids objectAtIndex: i]];;
    [content writeToFile: fileName atomically: YES];
    
    [zipTaskArguments addObject: 
      [NSString stringWithFormat:@"%@.eml", [uids objectAtIndex: i]]];
  }
  
  [zipTask setArguments: zipTaskArguments];
  [zipTask launch];
  [zipTask waitUntilExit];
  
  [zipTask release];
  
  zipContent = [[NSData alloc] initWithContentsOfFile: 
    [NSString stringWithFormat: @"%@/SavedMessages.zip", spoolPath]];
  
  for(i = 0; i < [zipTaskArguments count]; i++) {
    fileName = [zipTaskArguments objectAtIndex: i];
    [fm removeFileAtPath: 
      [NSString stringWithFormat: @"%@/%@", spoolPath, fileName] handler: nil];
  }
  
  response = [context response];
  qpFileName = [archiveName asQPSubjectString: @"utf-8"];
  [response setHeader: [NSString stringWithFormat: @"application/zip;"
                                 @" name=\"%@\"",
                                 qpFileName]
               forKey:@"content-type"];
  [response setHeader: [NSString stringWithFormat: @"attachment; filename=\"%@\"",
                                 qpFileName]
               forKey: @"Content-Disposition"];
  [response setContent: zipContent];

  [zipContent release];
  
  return response;
}

- (WOResponse *) archiveAllMessagesInContext: (id) localContext
{
  WOResponse *response;
  NSArray *uids;
  NSString *archiveName;
  EOQualifier *notDeleted;

  if ([[self imap4Connection] doesMailboxExistAtURL: [self imap4URL]])
    {
      notDeleted = [EOQualifier qualifierWithQualifierFormat:
                                  @"(not (flags = %@))", @"deleted"];
      uids = [self fetchUIDsMatchingQualifier: notDeleted
                                 sortOrdering: @"ARRIVAL"];
      archiveName = [NSString stringWithFormat: @"%@.zip", [self relativeImap4Name]];
      response = [self archiveUIDs: uids inArchiveNamed: archiveName
                         inContext: localContext];
    }
  else
    response = (WOResponse *)
      [NSException exceptionWithHTTPStatus: 404
                                    reason: @"Folder does not exist."];

  return response;
}

- (WOResponse *) copyUIDs: (NSArray *) uids
		 toFolder: (NSString *) destinationFolder
		inContext: (id) localContext
{
  NSArray *folders;
  NSString *currentFolderName;
  NSMutableString *imapDestinationFolder;
  NGImap4Client *client;
  id result;
  int count, max;

#warning this code will fail on implementation using something else than '/' as delimiter
  imapDestinationFolder = [NSMutableString string];
  folders = [[destinationFolder componentsSeparatedByString: @"/"]
              resultsOfSelector: @selector (fromCSSIdentifier)];
  max = [folders count];
  for (count = 2; count < max; count++)
    {
      currentFolderName
        = [[folders objectAtIndex: count] substringFromIndex: 6];
      [imapDestinationFolder appendFormat: @"/%@", currentFolderName];
    }

  client = [[self imap4Connection] client];
  [imap4 selectFolder: [self imap4URL]];
  
  // We make sure the destination IMAP folder exist, if not, we create it.
  result = [[client status: imapDestinationFolder
                     flags: [NSArray arrayWithObject: @"UIDVALIDITY"]]
	     objectForKey: @"result"];
  if (![result boolValue])
    result = [[self imap4Connection] createMailbox: imapDestinationFolder
                                             atURL: [[self mailAccountFolder] imap4URL]];
  if (!result || [result boolValue])
    result = [client copyUids: uids toFolder: imapDestinationFolder];

  if ([[result valueForKey: @"result"] boolValue])
    result = nil;
  else
    result = [NSException exceptionWithHTTPStatus: 500 reason: @"Couldn't copy UIDs."];
  
  return result;
}

- (WOResponse *) moveUIDs: (NSArray *) uids
		 toFolder: (NSString *) destinationFolder
		inContext: (id) localContext
{
  id result;
  NGImap4Client *client;

  client = [[self imap4Connection] client];
  
  result = [self copyUIDs: uids toFolder: destinationFolder inContext: localContext];
  if (![result isNotNull])
    {
      result = [client storeFlags: [NSArray arrayWithObject: @"Deleted"]
                          forUIDs: uids addOrRemove: YES];
      if ([[result valueForKey: @"result"] boolValue])
	{
	  [self markForExpunge];
	  result = nil;
	}
    }

  return result;
}

- (NSArray *) fetchUIDsMatchingQualifier: (id) _q
			    sortOrdering: (id) _so
{
  /* seems to return an NSArray of NSNumber's */
  return [[self imap4Connection] fetchUIDsInURL: [self imap4URL]
				 qualifier: _q sortOrdering: _so];
}

- (NSArray *) fetchUIDs: (NSArray *) _uids
		  parts: (NSArray *) _parts
{
  return [[self imap4Connection] fetchUIDs: _uids inURL: [self imap4URL]
				 parts: _parts];
}

- (NSException *) postData: (NSData *) _data
		     flags: (id) _flags
{
  // We check for the existence of the IMAP folder (likely to be the
  // Sent mailbox) prior to appending messages to it.
  if ([[self imap4Connection] doesMailboxExistAtURL: [self imap4URL]]
      || ![[self imap4Connection] createMailbox: [[self imap4Connection] imap4FolderNameForURL: [self imap4URL]]
                                          atURL: [[self mailAccountFolder] imap4URL]])
    return [[self imap4Connection] postData: _data flags: _flags
                                toFolderURL: [self imap4URL]];
  
  return [NSException exceptionWithHTTPStatus: 502 /* Bad Gateway */
		      reason: [NSString stringWithFormat: @"%@ is not an IMAP4 folder", [self relativeImap4Name]]];
}

- (NSException *) expunge
{
  return [[self imap4Connection] expungeAtURL: [self imap4URL]];
}

- (void) markForExpunge
{
  SOGoUserSettings *us;
  NSMutableDictionary *mailSettings;
  NSString *urlString;

  us = [[context activeUser] userSettings];
  mailSettings = [us objectForKey: @"Mail"];
  if (!mailSettings)
    {
      mailSettings = [NSMutableDictionary dictionaryWithCapacity: 1];
      [us setObject: mailSettings forKey: @"Mail"];
    }

  urlString = [self imap4URLString];
  if (![[mailSettings objectForKey: @"folderForExpunge"]
	 isEqualToString: urlString])
    {
      [mailSettings setObject: [self imap4URLString]
                       forKey: @"folderForExpunge"];
      [us synchronize];
    }
}

- (void) expungeLastMarkedFolder
{
  SOGoUserSettings *us;
  NSMutableDictionary *mailSettings;
  NSString *expungeURL;
  NSURL *folderURL;

  us = [[context activeUser] userSettings];
  mailSettings = [us objectForKey: @"Mail"];
  if (mailSettings)
    {
      expungeURL = [mailSettings objectForKey: @"folderForExpunge"];
      if (expungeURL
	  && ![expungeURL isEqualToString: [self imap4URLString]])
	{
	  folderURL = [NSURL URLWithString: expungeURL];
	  if (![[self imap4Connection] expungeAtURL: folderURL])
	    {
	      [mailSettings removeObjectForKey: @"folderForExpunge"];
	      [us synchronize];
	    }
	}
    }
}

/* flags */

- (NSException *) addFlagsToAllMessages: (id) _f
{
  return [[self imap4Connection] addFlags:_f 
				 toAllMessagesInURL: [self imap4URL]];
}

/* name lookup */

- (id) lookupName: (NSString *) _key
	inContext: (id)_ctx
	  acquire: (BOOL) _acquire
{
  NSString *folderName, *fullFolderName, *className;
  SOGoMailAccount *mailAccount;
  id obj;

  obj = [super lookupName: _key inContext: _ctx acquire: NO];
  if (!obj)
    {
      if ([_key hasPrefix: @"folder"])
        {
          mailAccount = [self mailAccountFolder];
          folderName = [[_key substringFromIndex: 6] fromCSSIdentifier];
          fullFolderName = [NSString stringWithFormat: @"%@/%@",
                                     [self traversalFromMailAccount], folderName];
          if ([fullFolderName
                    isEqualToString:
                  [mailAccount sentFolderNameInContext: _ctx]])
            className = @"SOGoSentFolder";
          else if ([fullFolderName
                     isEqualToString:
                       [mailAccount draftsFolderNameInContext: _ctx]])
            className = @"SOGoDraftsFolder";
          else if ([fullFolderName
                     isEqualToString:
                       [mailAccount trashFolderNameInContext: _ctx]])
            className = @"SOGoTrashFolder";
          /*       else if ([folderName isEqualToString:
                   [mailAccount sieveFolderNameInContext: _ctx]])
                   obj = [self lookupFiltersFolder: _key inContext: _ctx]; */
          else
            className = @"SOGoMailFolder";

          obj = [NSClassFromString (className) objectWithName: _key
                                                  inContainer: self];
        }
      else if (isdigit ([_key characterAtIndex: 0])
               && [[self imap4Connection] doesMailboxExistAtURL: [self imap4URL]])
        obj = [SOGoMailObject objectWithName: _key inContainer: self];
    }

  if (!obj && _acquire)
    obj = [NSException exceptionWithHTTPStatus: 404 /* Not Found */];

  return obj;
}

/* WebDAV */

- (BOOL) davIsCollection
{
  return YES;
}

- (NSException *) davCreateCollection: (NSString *) _name
			    inContext: (id) _ctx
{
  return [[self imap4Connection] createMailbox:_name atURL:[self imap4URL]];
}

- (NSException *) delete
{
  return [[self imap4Connection] deleteMailboxAtURL:[self imap4URL]];
}

- (NSException *) davMoveToTargetObject: (id) _target
				newName: (NSString *) _name
			      inContext: (id)_ctx
{
  NSURL *destImapURL;
  
  if ([_name length] == 0) { /* target already exists! */
    // TODO: check the overwrite request field (should be done by dispatcher)
    return [NSException exceptionWithHTTPStatus:412 /* Precondition Failed */
			reason:@"target already exists"];
  }
  if (![_target respondsToSelector:@selector(imap4URL)]) {
    return [NSException exceptionWithHTTPStatus:502 /* Bad Gateway */
			reason:@"target is not an IMAP4 folder"];
  }
  
  /* build IMAP4 URL for target */
  
  destImapURL = [_target imap4URL];
// -  destImapURL = [NSURL URLWithString:[[destImapURL path] 
// -				       stringByAppendingPathComponent:_name]
// -		       relativeToURL:destImapURL];
  destImapURL = [NSURL URLWithString: _name
		       relativeToURL: destImapURL];
  
  [self logWithFormat:@"TODO: should move collection as '%@' to: %@",
	[[self imap4URL] absoluteString], 
	[destImapURL absoluteString]];
  
  return [[self imap4Connection] moveMailboxAtURL:[self imap4URL] 
				 toURL:destImapURL];
}

- (NSException *) davCopyToTargetObject: (id) _target
				newName: (NSString *) _name
			      inContext: (id) _ctx
{
  [self logWithFormat:@"TODO: should copy collection as '%@' to: %@",
	_name, _target];
  return [NSException exceptionWithHTTPStatus:501 /* Not Implemented */
		      reason:@"not implemented"];
}

/* folder type */
- (NSString *) folderType
{
  return @"Mail";
}

- (NSString *) outlookFolderClass
{
  // TODO: detect Trash/Sent/Drafts folders
  SOGoMailAccount *account;
  NSString *name;

  if (!folderType)
    {
      account = [self mailAccountFolder];
      name = [self traversalFromMailAccount];

      if ([name isEqualToString: [account trashFolderNameInContext: nil]])
	folderType = @"IPF.Trash";
      else if ([name
		 isEqualToString: [account inboxFolderNameInContext: nil]])
	folderType = @"IPF.Inbox";
      else if ([name
		 isEqualToString: [account sentFolderNameInContext: nil]])
	folderType = @"IPF.Sent";
      else
	folderType = @"IPF.Folder";
    }
  
  return folderType;
}

/* acls */

- (NSArray *) _imapAclsToSOGoAcls: (NSString *) imapAcls
{
  unsigned int count, max;
  NSMutableArray *SOGoAcls;

  SOGoAcls = [NSMutableArray array];
  max = [imapAcls length];
  for (count = 0; count < max; count++)
    {
      switch ([imapAcls characterAtIndex: count])
	{
	case 'l':
	case 'r':
	  [SOGoAcls addObjectUniquely: SOGoRole_ObjectViewer];
	  break;
	case 's':
	  [SOGoAcls addObjectUniquely: SOGoMailRole_SeenKeeper];
	  break;
	case 'w':
	  [SOGoAcls addObjectUniquely: SOGoMailRole_Writer];
	  break;
	case 'i':
	  [SOGoAcls addObjectUniquely: SOGoRole_ObjectCreator];
	  break;
	case 'p':
	  [SOGoAcls addObjectUniquely: SOGoMailRole_Poster];
	  break;
	case 'c':
	case 'k':
	  [SOGoAcls addObjectUniquely: SOGoRole_FolderCreator];
	  break;
	case 'x':
	  [SOGoAcls addObjectUniquely: SOGoRole_FolderEraser];
	  break;
	case 'd':
	case 't':
	  [SOGoAcls addObjectUniquely: SOGoRole_ObjectEraser];
	  break;
	case 'e':
	  [SOGoAcls addObjectUniquely: SOGoMailRole_Expunger];
	  break;
	case 'a':
	  [SOGoAcls addObjectUniquely: SOGoMailRole_Administrator];
	  break;
	}
    }

  return SOGoAcls;
}

- (char) _rfc2086StyleRight: (NSString *) sogoRight
{
  char character;

  if ([sogoRight isEqualToString: SOGoRole_FolderCreator])
    character = 'c';
  else if ([sogoRight isEqualToString: SOGoRole_ObjectEraser])
    character = 'd';
  else
    character = 0;

  return character;
}

- (char) _rfc4314StyleRight: (NSString *) sogoRight
{
  char character;

  if ([sogoRight isEqualToString: SOGoRole_FolderCreator])
    character = 'k';
  else if ([sogoRight isEqualToString: SOGoRole_FolderEraser])
    character = 'x';
  else if ([sogoRight isEqualToString: SOGoRole_ObjectEraser])
    character = 't';
  else if ([sogoRight isEqualToString: SOGoMailRole_Expunger])
    character = 'e';
  else
    character = 0;

  return character;
}

- (NSString *) _sogoAclsToImapAcls: (NSArray *) sogoAcls
{
  NSMutableString *imapAcls;
  NSEnumerator *acls;
  NSString *currentAcl;
  char character;
  SOGoIMAPAclStyle aclStyle;

  imapAcls = [NSMutableString string];
  acls = [sogoAcls objectEnumerator];
  while ((currentAcl = [acls nextObject]))
    {
      if ([currentAcl isEqualToString: SOGoRole_ObjectViewer])
	{
	  [imapAcls appendFormat: @"lr"];
	  character = 0;
	}
      else if ([currentAcl isEqualToString: SOGoMailRole_SeenKeeper])
	character = 's';
      else if ([currentAcl isEqualToString: SOGoMailRole_Writer])
	character = 'w';
      else if ([currentAcl isEqualToString: SOGoRole_ObjectCreator])
	character = 'i';
      else if ([currentAcl isEqualToString: SOGoMailRole_Poster])
	character = 'p';
      else if ([currentAcl isEqualToString: SOGoMailRole_Administrator])
	character = 'a';
      else
	{
          aclStyle = [[self mailAccountFolder] imapAclStyle];
	  if (aclStyle == rfc2086)
	    character = [self _rfc2086StyleRight: currentAcl];
	  else if (aclStyle == rfc4314)
	    character = [self _rfc4314StyleRight: currentAcl];
	  else
	    character = 0;
	}

      if (character)
	[imapAcls appendFormat: @"%c", character];
    }

  return imapAcls;
}

- (void) _removeIMAPExtUsernames
{
  NSMutableDictionary *newIMAPAcls;
  NSEnumerator *usernames;
  NSString *username;

  newIMAPAcls = [NSMutableDictionary new];

  usernames = [[mailboxACL allKeys] objectEnumerator];
  while ((username = [usernames nextObject]))
    if (!([username isEqualToString: @"administrators"]
	  || [username isEqualToString: @"owner"]
	  || [username isEqualToString: @"anonymous"]
	  || [username isEqualToString: @"authuser"]))
      [newIMAPAcls setObject: [mailboxACL objectForKey: username]
		   forKey: username];
  [mailboxACL release];
  mailboxACL = newIMAPAcls;
}

- (void) _readMailboxACL
{
  [mailboxACL release];

  mailboxACL = [[self imap4Connection] aclForMailboxAtURL: [self imap4URL]];
  [mailboxACL retain];

  if ([[self mailAccountFolder] imapAclConformsToIMAPExt])
    [self _removeIMAPExtUsernames];
}

- (NSArray *) subscriptionRoles
{
  return [NSArray arrayWithObjects: SOGoRole_ObjectViewer,
		  SOGoMailRole_SeenKeeper, SOGoMailRole_Writer,
		  SOGoRole_ObjectCreator, SOGoMailRole_Poster,
		  SOGoRole_FolderCreator, SOGoRole_FolderEraser,
		  SOGoRole_ObjectEraser, SOGoMailRole_Expunger,
		  SOGoMailRole_Administrator, nil];
}

- (NSArray *) aclUsers
{
  NSArray *users;

  if (!mailboxACL)
    [self _readMailboxACL];

  if ([mailboxACL isKindOfClass: [NSDictionary class]])
    users = [mailboxACL allKeys];
  else
    users = nil;

  return users;
}

- (NSMutableArray *) _sharesACLs
{
  NSMutableArray *acls;
  SOGoMailAccount *mailAccount;
  NSString *path;

  acls = [NSMutableArray array];

  mailAccount = [self mailAccountFolder];
  path = [[self imap4Connection] imap4FolderNameForURL: [self imap4URL]];

  if ([self         _path: path
           isInNamespaces: [mailAccount otherUsersFolderNamespaces]]
      || [self         _path: path
              isInNamespaces: [mailAccount sharedFolderNamespaces]])
    [acls addObject: SOGoRole_ObjectViewer];
  else
    [acls addObject: SoRole_Owner];

  return acls;
}

- (NSArray *) aclsForUser: (NSString *) uid
{
  NSMutableArray *acls;
  NSString *userAcls, *userLogin;

  userLogin = [[context activeUser] login];
  if ([uid isEqualToString: userLogin])
    acls = [self _sharesACLs];
  else
    acls = [NSMutableArray array];

  if ([owner isEqualToString: userLogin])
    {
      if (!mailboxACL)
        [self _readMailboxACL];

      if ([mailboxACL isKindOfClass: [NSDictionary class]])
        {
          userAcls = [mailboxACL objectForKey: uid];
          if (!([userAcls length] || [uid isEqualToString: defaultUserID]))
            userAcls = [mailboxACL objectForKey: defaultUserID];
          if ([userAcls length])
            [acls addObjectsFromArray: [self _imapAclsToSOGoAcls: userAcls]];
        }
    }

  return acls;
}

- (void) removeAclsForUsers: (NSArray *) users
{
  NSEnumerator *uids;
  NSString *currentUID, *folderName;
  NGImap4Client *client;

  folderName = [[self imap4Connection] imap4FolderNameForURL: [self imap4URL]];
  client = [imap4 client];

  uids = [users objectEnumerator];
  while ((currentUID = [uids nextObject]))
    [client deleteACL: folderName uid: currentUID];
  [mailboxACL release];
  mailboxACL = nil;
}

- (void) setRoles: (NSArray *) roles
	  forUser: (NSString *) uid
{
  NSString *acls, *folderName;

  acls = [self _sogoAclsToImapAcls: roles];
  folderName = [[self imap4Connection] imap4FolderNameForURL: [self imap4URL]];
  [[imap4 client] setACL: folderName rights: acls uid: uid];

  [mailboxACL release];
  mailboxACL = nil;
}

- (NSString *) defaultUserID
{
  return defaultUserID;
}

- (NSString *) otherUsersPathToFolder
{
  NSString *userPath, *selfPath, *otherUsers;
  SOGoMailAccount *account;
  NSArray *otherUsersFolderNamespaces;

#warning this method should be checked
  account = [self mailAccountFolder];
  otherUsersFolderNamespaces = [account otherUsersFolderNamespaces];

  selfPath = [[self imap4URL] path];
  if ([self _path: selfPath isInNamespaces: otherUsersFolderNamespaces]
      || [self _path: selfPath
               isInNamespaces: [account sharedFolderNamespaces]])
    userPath = selfPath;
  else
    {
      if ([otherUsersFolderNamespaces count])
        {
          /* can we really have more than one "other users" namespace? */
          otherUsers = [[otherUsersFolderNamespaces objectAtIndex: 0]
                         stringByEscapingURL];
          userPath = [NSString stringWithFormat: @"/%@/%@%@",
                               otherUsers, owner, selfPath];
        }
      else
	userPath = nil;
    }

  return userPath;
}

- (NSString *) httpURLForAdvisoryToUser: (NSString *) uid
{
  SOGoUser *user;
  NSString *otherUsersPath, *url;
  SOGoMailAccount *thisAccount;
  NSDictionary *mailAccount;

  user = [SOGoUser userWithLogin: uid roles: nil];
  otherUsersPath = [self otherUsersPathToFolder];
  if (otherUsersPath)
    {
      thisAccount = [self mailAccountFolder];
      mailAccount = [[user mailAccounts] objectAtIndex: 0];
      url = [NSString stringWithFormat: @"%@/%@%@",
		      [self soURLToBaseContainerForUser: uid],
		      [mailAccount objectForKey: @"name"],
		      otherUsersPath];
    }
  else
    url = nil;

  return url;
}

- (NSString *) resourceURLForAdvisoryToUser: (NSString *) uid
{
  NSURL *selfURL, *userURL;

  selfURL = [self imap4URL];
  userURL = [[NSURL alloc] initWithScheme: [selfURL scheme]
			   host: [selfURL host]
			   path: [self otherUsersPathToFolder]];
  [userURL autorelease];

  return [userURL absoluteString];
}

- (NSString *) userSpoolFolderPath
{
  NSString *login, *mailSpoolPath;
  SOGoUser *currentUser;

  currentUser = [context activeUser];
  login = [currentUser login];
  mailSpoolPath = [[currentUser domainDefaults] mailSpoolPath];

  return [NSString stringWithFormat: @"%@/%@",
		   mailSpoolPath, login];
}

- (BOOL) ensureSpoolFolderPath
{
  NSFileManager *fm;

  fm = [NSFileManager defaultManager];
  
  return ([fm createDirectoriesAtPath: [self userSpoolFolderPath]
                           attributes: nil]);
}

- (NSString *) displayName
{
  return [self nameInContainer];
}

- (NSDictionary *) davIMAPFieldsTable
{
  static NSMutableDictionary *davIMAPFieldsTable = nil;

  if (!davIMAPFieldsTable)
    {
      davIMAPFieldsTable = [NSMutableDictionary new];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (DATE)]"
                             forKey: @"{urn:schemas:httpmail:}date"];
      [davIMAPFieldsTable setObject: @""
                             forKey: @"{urn:schemas:httpmail:}hasattachment"];
      [davIMAPFieldsTable setObject: @""
                             forKey: @"{urn:schemas:httpmail:}read"];
      [davIMAPFieldsTable setObject: @"BODY"
                             forKey: @"{urn:schemas:httpmail:}textdescription"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (CC)]"
                             forKey: @"{urn:schemas:mailheader:}cc"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (DATE)]"
                             forKey: @"{urn:schemas:mailheader:}date"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (FROM)]"
                             forKey: @"{urn:schemas:mailheader:}from"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (INREPLYTO)]"
                             forKey: @"{urn:schemas:mailheader:}in-reply-to"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (MESSAGEID)]"
                             forKey: @"{urn:schemas:mailheader:}message-id"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (RECEIVED)]"
                             forKey: @"{urn:schemas:mailheader:}received"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (REFERENCES)]"
                             forKey: @"{urn:schemas:mailheader:}references"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (SUBJECT)]"
                             forKey: @"{DAV:}displayname"];
      [davIMAPFieldsTable setObject: @"BODY[HEADER.FIELDS (TO)]"
                             forKey: @"{urn:schemas:mailheader:}to"];
    }

  return davIMAPFieldsTable;
}

- (BOOL) _sortElementIsAscending: (DOMElement *) sortElement
{
  NSString *davReverseAttr;
  BOOL orderIsAscending;

  orderIsAscending = YES;

  davReverseAttr = [sortElement attribute: @"order"];
  if ([davReverseAttr isEqualToString: @"descending"])
    orderIsAscending = NO;
  else if ([davReverseAttr length]
           && ![davReverseAttr isEqualToString: @"ascending"])
    [self errorWithFormat: @"unrecognized sort order: '%@'",
          davReverseAttr];

  return orderIsAscending;
}

- (NSArray *) _sortOrderingsFromSortElement: (DOMElement *) sortElement
{
  static NSMutableDictionary *criteriasMap = nil;
  NSArray *davSortCriterias;
  NSMutableArray *sortOrderings;
  SEL sortOrderingOrder;
  NSString *davSortVerb, *imapSortVerb;
  EOSortOrdering *currentOrdering;
  int count, max;

  if (!criteriasMap)
    {
      criteriasMap = [NSMutableDictionary new];
      [criteriasMap setObject: @"ARRIVAL"
                       forKey: @"{urn:schemas:mailheader:}received"];
      [criteriasMap setObject: @"DATE"
                       forKey: @"{urn:schemas:mailheader:}date"];
      [criteriasMap setObject: @"FROM"
                       forKey: @"{urn:schemas:mailheader:}from"];
      [criteriasMap setObject: @"TO"
                       forKey: @"{urn:schemas:mailheader:}to"];
      [criteriasMap setObject: @"CC"
                       forKey: @"{urn:schemas:mailheader:}cc"];
      [criteriasMap setObject: @"SUBJECT"
                       forKey: @"{DAV:}displayname"];
      [criteriasMap setObject: @"SUBJECT"
                       forKey: @"{urn:schemas:mailheader:}subject"];
      [criteriasMap setObject: @"SIZE"
                       forKey: @"{DAV:}getcontentlength"];
    }

  sortOrderings = [NSMutableArray array];

  if ([self _sortElementIsAscending: sortElement])
    sortOrderingOrder = EOCompareAscending;
  else
    sortOrderingOrder = EOCompareDescending;

  davSortCriterias = [sortElement flatPropertyNameOfSubElements];
  max = [davSortCriterias count];
  for (count = 0; count < max; count++)
    {
      davSortVerb = [davSortCriterias objectAtIndex : count];
      imapSortVerb = [criteriasMap objectForKey: davSortVerb];
      if (imapSortVerb)
        {
          currentOrdering
            = [EOSortOrdering sortOrderingWithKey: imapSortVerb
                                         selector: sortOrderingOrder];
          [sortOrderings addObject: currentOrdering];
        }
      else
        [self errorWithFormat: @"unrecognized sort key: '%@'", davSortVerb];
    }

  return sortOrderings;
}

- (NSArray *) _fetchMessageProperties: (NSDictionary *) properties
                    matchingQualifier: (EOQualifier *) searchQualifier
                     andSortOrderings: (NSArray *) sortOrderings
{
  NGImap4Client *client;
  NSDictionary *response;
  NSArray *messages;
  NSString *resultKey;

  client = [[self imap4Connection] client];
  [imap4 selectFolder: [self imap4URL]];

  if ([sortOrderings count])
    {
      response = [client sort: sortOrderings qualifier: searchQualifier
                     encoding: @"UTF-8"];
      resultKey = @"sort";
    }
  else
    {
      response = [client searchWithQualifier: searchQualifier];
      resultKey = @"search";
    }

   if ([[response objectForKey: @"result"] boolValue])
     messages = [response objectForKey: resultKey];
   else
     messages = nil;

  return messages;
}

- (NSArray *) _davPropstatsWithProperties: (NSArray *) davProperties
                       andMethodSelectors: (SEL *) selectors
                              fromMessage: (NSString *) messageId
{
  SOGoMailObject *message;
  unsigned int count, max;
  NSMutableArray *properties200, *properties404, *propstats;
  NSDictionary *propContent;
  NSString *messageUrl;
  id result;

  propstats = [NSMutableArray arrayWithCapacity: 2];

  max = [davProperties count];
  properties200 = [NSMutableArray arrayWithCapacity: max];
  properties404 = [NSMutableArray arrayWithCapacity: max];

  message = [self lookupName: messageId
                   inContext: context
                     acquire: NO];
  for (count = 0; count < max; count++)
    {
      if (selectors[count]
          && [message respondsToSelector: selectors[count]])
        result = [message performSelector: selectors[count]];
      else
        result = nil;

      if (result)
        {
          propContent = [[davProperties objectAtIndex: count]
                             asWebDAVTupleWithContent: result];
          [properties200 addObject: propContent];
        }
      else
        {
          propContent = [[davProperties objectAtIndex: count]
                          asWebDAVTuple];
          [properties404 addObject: propContent];
        }
    }

  messageUrl = [NSString stringWithFormat: @"%@%@.eml", 
                         [self davURL], messageId];
  [propstats addObject: davElementWithContent (@"href", XMLNS_WEBDAV, 
                                               messageUrl)];

  if ([properties200 count])
    [propstats addObject: [properties200
                            asDAVPropstatWithStatus: @"HTTP/1.1 200 OK"]];
  if ([properties404 count])
    [propstats addObject: [properties404
                            asDAVPropstatWithStatus: @"HTTP/1.1 404 Not Found"]];

  return propstats;
}

- (void) _appendProperties: (NSArray *) properties
              fromMessages: (NSArray *) messages
                toResponse: (WOResponse *) response
{
  NSDictionary *davElement;
  NSArray *propstats;
  NSMutableArray *all;
  NSString *message, *davString;
  SEL *selectors;
  int max, count;

  max = [properties count];
  selectors = NSZoneMalloc (NULL, sizeof (max * sizeof (SEL)));

  for (count = 0; count < max; count++)
    selectors[count]
      = SOGoSelectorForPropertyGetter ([properties objectAtIndex: count]);

  max = [messages count];
  all = [NSMutableArray array];
  for (count = 0; count < max; count++)
    {
      message = [[messages objectAtIndex: count] stringValue];
      propstats = [self _davPropstatsWithProperties: properties
                                 andMethodSelectors: selectors
                                         fromMessage: message];
      davElement = davElementWithContent (@"response", XMLNS_WEBDAV, 
                                          propstats);

      [all addObject: davElement];
    }

  davString = [davElementWithContent (@"multistatus", XMLNS_WEBDAV, all)
                asWebDavStringWithNamespaces: nil];
  [response appendContentString: davString];
  NSZoneFree (NULL, selectors);
}

- (NSDictionary *) _davIMAPFieldsForProperties: (NSArray *) properties
{
  NSMutableDictionary *davIMAPFields;
  NSDictionary *davIMAPFieldsTable;
  NSString *imapField, *property;
  unsigned int count, max;

  davIMAPFieldsTable = [self davIMAPFieldsTable];

  max = [properties count];
  davIMAPFields = [NSMutableDictionary dictionaryWithCapacity: max];
  for (count = 0; count < max; count++)
    {
      property = [properties objectAtIndex: count];
      imapField = [davIMAPFieldsTable objectForKey: property];
      if (imapField)
        [davIMAPFields setObject: imapField forKey: property];
      else
        [self errorWithFormat: @"DAV property '%@' has no matching IMAP field,"
          @" response could be incomplete", property];
    }

  return davIMAPFields;
}

- (NSDictionary *) parseDAVRequestedProperties: (DOMElement *) propElement
{
  NSArray *properties;
  NSDictionary *imapFieldsTable;

  properties = [propElement flatPropertyNameOfSubElements];
  imapFieldsTable = [self _davIMAPFieldsForProperties: properties];

  return imapFieldsTable;
}

/* TODO:
   - populate only required keys in returned SOGoMailObject rather that
     fetching the whole envelope and stuff
   - use EOSortOrdering rather than an NSString
 */
- (id) davMailQuery: (id) queryContext
{
  WOResponse *r;
  id <DOMDocument> document;
  DOMElement *documentElement, *propElement, *filterElement, *sortElement;
  NSDictionary *properties;
  NSArray *messages, *sortOrderings;
  EOQualifier *searchQualifier;

  r = [context response];
  [r prepareDAVResponse];

  document = [[context request] contentAsDOMDocument];
  documentElement = (DOMElement *) [document documentElement];

  propElement = [documentElement firstElementWithTag: @"prop"
                                         inNamespace: XMLNS_WEBDAV];
  properties = [self parseDAVRequestedProperties: propElement];
  filterElement = [documentElement firstElementWithTag: @"mail-filters"
                                           inNamespace: XMLNS_INVERSEDAV];
  searchQualifier = [EOQualifier
                      qualifierFromMailDAVMailFilters: filterElement];
  sortElement = [documentElement firstElementWithTag: @"sort"
                                         inNamespace: XMLNS_INVERSEDAV];
  sortOrderings = [self _sortOrderingsFromSortElement: sortElement];

  messages = [self _fetchMessageProperties: properties
                         matchingQualifier: searchQualifier
                          andSortOrderings: sortOrderings];
  [self _appendProperties: [properties allKeys]
             fromMessages: messages
               toResponse: r];

  return r;
}

- (NSException *) _appendMessageData: (NSData *) data
                             usingId: (int *) imap4id;
{
  NGImap4Client *client;
  NSString *folderName;
  NSException *error;
  id result;

  error = nil;
  client = [imap4 client];

  folderName = [imap4 imap4FolderNameForURL: [self imap4URL]];
  result = [client append: data toFolder: folderName withFlags: nil];

  if ([[result objectForKey: @"result"] boolValue])
    {
      if (imap4id)
        *imap4id = [self IMAP4IDFromAppendResult: result];
    }
  else
    error = [NSException exceptionWithHTTPStatus: 500 /* Server Error */
                                          reason: @"Failed to store message"];

  return error;
}

- (id) appendMessage: (NSData *) message
             usingId: (int *) imap4id
{
  NSException *error;
  WOResponse *response;
  NSString *location;

  error = [self _appendMessageData: message
                           usingId: imap4id];
  if (error)
    response = (WOResponse *) error;
  else
    {
      response = [context response];
      [response setStatus: 201];
      location = [NSString stringWithFormat: @"%@%d.eml",
                           [self davURL], *imap4id];
      [response setHeader: location forKey: @"location"];
    }

  return response;
}

- (id) PUTAction: (WOContext *) _ctx
{
  WORequest *rq;
  NSException *error;
  WOResponse *response;
  int imap4id;

  error = [self matchesRequestConditionInContext: _ctx];
  if (error)
    response = (WOResponse *) error;
  else
    {
      rq = [_ctx request];
      response = [self appendMessage: [rq content]
                             usingId: &imap4id];
    }

  return response;
}

@end /* SOGoMailFolder */

@implementation SOGoSpecialMailFolder

- (BOOL) isSpecialFolder
{
  return YES;
}

@end
