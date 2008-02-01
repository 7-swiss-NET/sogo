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
#import <Foundation/NSURL.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/SoHTTPAuthenticator.h>
#import <NGObjWeb/WORequest.h>
#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGExtensions/NSObject+Logs.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGImap4/NGImap4Connection.h>
#import <NGImap4/NGImap4Client.h>
#import <NGImap4/NGImap4Context.h>

#import <SoObjects/SOGo/NSArray+Utilities.h>
#import <SoObjects/SOGo/SOGoUser.h>

#import "SOGoDraftsFolder.h"
#import "SOGoMailFolder.h"
#import "SOGoMailManager.h"
#import "SOGoSentFolder.h"
#import "SOGoTrashFolder.h"

#import "SOGoMailAccount.h"

@implementation SOGoMailAccount

static NSArray *rootFolderNames = nil;
static NSString *inboxFolderName = @"INBOX";
static NSString *draftsFolderName = @"Drafts";
static NSString *sieveFolderName = @"Filters";
static NSString *sentFolderName = nil;
static NSString *trashFolderName = nil;
static NSString *sharedFolderName = @""; // TODO: add English default
static NSString *otherUsersFolderName = @""; // TODO: add English default

+ (void) initialize
{
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSString *cfgDraftsFolderName;

  sharedFolderName = [ud stringForKey:@"SOGoSharedFolderName"];
  otherUsersFolderName = [ud stringForKey:@"SOGoOtherUsersFolderName"];
  cfgDraftsFolderName = [ud stringForKey:@"SOGoDraftsFolderName"];
  if (!sentFolderName)
    {
      sentFolderName = [ud stringForKey: @"SOGoSentFolderName"];
      if (!sentFolderName)
	sentFolderName = @"Sent";
      [sentFolderName retain];
    }
  if (!trashFolderName)
    {
      trashFolderName = [ud stringForKey: @"SOGoTrashFolderName"];
      if (!trashFolderName)
	trashFolderName = @"Trash";
      [trashFolderName retain];
    }
  if ([cfgDraftsFolderName length] > 0)
    {
      ASSIGN (draftsFolderName, cfgDraftsFolderName);
      NSLog(@"Note: using drafts folder named:      '%@'", draftsFolderName);
    }

  NSLog(@"Note: using shared-folders name:      '%@'", sharedFolderName);
  NSLog(@"Note: using other-users-folders name: '%@'", otherUsersFolderName);
  if ([ud boolForKey: @"SOGoEnableSieveFolder"])
    rootFolderNames = [[NSArray alloc] initWithObjects:
				        draftsFolderName, 
				        sieveFolderName, 
				      nil];
  else
    rootFolderNames = [[NSArray alloc] initWithObjects:
				        draftsFolderName, 
				      nil];
}

- (id) init
{
  if ((self = [super init]))
    {
      inboxFolder = nil;
      draftsFolder = nil;
      sentFolder = nil;
      trashFolder = nil;
    }

  return self;
}

- (void) dealloc
{
  [inboxFolder release];
  [draftsFolder release];
  [sentFolder release];
  [trashFolder release];
  [super dealloc];  
}

/* shared accounts */

- (BOOL) isSharedAccount
{
  NSString *s;
  NSRange  r;
  
  s = [self nameInContainer];
  r = [s rangeOfString:@"@"];
  if (r.length == 0) /* regular HTTP logins are never a shared mailbox */
    return NO;
  
  s = [s substringToIndex:r.location];
  return [s rangeOfString:@".-."].length > 0 ? YES : NO;
}

- (NSString *) sharedAccountName
{
  return nil;
}

/* listing the available folders */

- (NSArray *) additionalRootFolderNames
{
  return rootFolderNames;
}

- (BOOL) isInDraftsFolder
{
  return NO;
}

- (NSArray *) toManyRelationshipKeys
{
  NSMutableArray *folders;
  NSArray *imapFolders, *additionalFolders;

  folders = [NSMutableArray array];

  imapFolders = [[self imap4Connection] subfoldersForURL: [self imap4URL]];
  additionalFolders = [self additionalRootFolderNames];
  if ([imapFolders count] > 0)
    [folders addObjectsFromArray: imapFolders];
  if ([additionalFolders count] > 0)
    {
      [folders removeObjectsInArray: additionalFolders];
      [folders addObjectsFromArray: additionalFolders];
    }
  
  return folders;
}

- (BOOL) supportsQuotas
{
  NGImap4Client *imapClient;

  imapClient = [[self imap4Connection] client];

  return [[imapClient context] canQuota];
}

/* hierarchy */

- (SOGoMailAccount *) mailAccountFolder
{
  return self;
}

- (NSArray *) allFolderPaths
{
  NSMutableArray *folderPaths;
  NSArray *rawFolders, *mainFolders;

  rawFolders = [[self imap4Connection] allFoldersForURL: [self imap4URL]];

  mainFolders = [[NSArray arrayWithObjects:
			    [self inboxFolderNameInContext: context],
			  [self draftsFolderNameInContext: context],
			  [self sentFolderNameInContext: context],
			  [self trashFolderNameInContext: context],
			  nil] stringsWithFormat: @"/%@"];
  folderPaths = [NSMutableArray arrayWithArray: rawFolders];
  [folderPaths removeObjectsInArray: mainFolders];
  [folderPaths
    sortUsingSelector: @selector (localizedCaseInsensitiveCompare:)];
  [folderPaths replaceObjectsInRange: NSMakeRange (0, 0)
	       withObjectsFromArray: mainFolders];

  return folderPaths;
}

/* IMAP4 */

- (BOOL) useSSL
{
  return NO;
}

- (NSString *) imap4LoginFromHTTP
{
  WORequest *rq;
  NSString  *s;
  NSArray   *creds;
  
  rq = [context request];
  
  s = [rq headerForKey:@"x-webobjects-remote-user"];
  if ([s length] > 0)
    return s;
  
  if ((s = [rq headerForKey:@"authorization"]) == nil) {
    /* no basic auth */
    return nil;
  }
  
  creds = [SoHTTPAuthenticator parseCredentials:s];
  if ([creds count] < 2)
    /* somehow invalid */
    return nil;
  
  return [creds objectAtIndex:0]; /* the user */
}

- (NSMutableString *) imap4URLString
{
  /* private, overridden by SOGoSharedMailAccount */
  NSMutableString *urlString;
  NSString *host;

  urlString = [NSMutableString string];

  if ([self useSSL])
    [urlString appendString: @"imaps://"];
  else
    [urlString appendString: @"imap://"];

  host = [self nameInContainer];
  if (![host rangeOfString: @"@"].length)
    [urlString appendFormat: @"%@@", [self imap4LoginFromHTTP]];
  [urlString appendFormat: @"%@/", host];

  return urlString;
}

- (NSMutableString *) traversalFromMailAccount
{
  return [NSMutableString string];
}

- (NSString *) imap4Login
{
  return [[self imap4URL] user];
}

/* name lookup */

- (id) lookupName: (NSString *) _key
	inContext: (id)_ctx
	  acquire: (BOOL) _flag
{
  NSString *folderName;
  Class klazz;
  id obj;

  if ([_key hasPrefix: @"folder"])
    {
      folderName = [_key substringFromIndex: 6];
      if ([folderName
	    isEqualToString: [self sentFolderNameInContext: _ctx]])
	klazz = [SOGoSentFolder class];
      else if ([folderName
		 isEqualToString: [self draftsFolderNameInContext: _ctx]])
	klazz = [SOGoDraftsFolder class];
      else if ([folderName
		 isEqualToString: [self trashFolderNameInContext: _ctx]])
	klazz = [SOGoTrashFolder class];
/*       else if ([folderName isEqualToString: [self sieveFolderNameInContext: _ctx]])
	 obj = [self lookupFiltersFolder: _key inContext: _ctx]; */
      else
	klazz = [SOGoMailFolder class];

      obj = [klazz objectWithName: _key inContainer: self];
    }
  else
    obj = [super lookupName: _key inContext: _ctx acquire: NO];
  
  /* return 404 to stop acquisition */
  if (!obj)
    obj = [NSException exceptionWithHTTPStatus: 404 /* Not Found */];

  return obj;
}

/* special folders */

- (NSString *) inboxFolderNameInContext: (id)_ctx
{
  /* cannot be changed in Cyrus ? */
  return inboxFolderName;
}

- (NSString *) _userFolderNameWithPurpose: (NSString *) purpose
{
  NSUserDefaults *ud;
  NSMutableDictionary *mailSettings;
  NSString *folderName;

  folderName = nil;
  ud = [[context activeUser] userSettings];
  mailSettings = [ud objectForKey: @"Mail"];
  if (mailSettings)
    folderName
      = [mailSettings objectForKey: [NSString stringWithFormat: @"%@Folder",
					      purpose]];

  return folderName;
}

- (NSString *) draftsFolderNameInContext: (id) _ctx
{
  NSString *folderName;

  folderName = [self _userFolderNameWithPurpose: @"Drafts"];
  if (!folderName)
    folderName = draftsFolderName;

  return folderName;
}

// - (NSString *) sieveFolderNameInContext: (id) _ctx
// {
//   return sieveFolderName;
// }

- (NSString *) sentFolderNameInContext: (id)_ctx
{
  NSString *folderName;

  folderName = [self _userFolderNameWithPurpose: @"Sent"];
  if (!folderName)
    folderName = sentFolderName;

  return folderName;
}

- (NSString *) trashFolderNameInContext: (id)_ctx
{
  NSString *folderName;

  folderName = [self _userFolderNameWithPurpose: @"Trash"];
  if (!folderName)
    folderName = trashFolderName;

  return folderName;
}

- (id) folderWithTraversal: (NSString *) traversal
	      andClassName: (NSString *) className
{
  NSArray *paths;
  NSString *currentName;
  id currentContainer;
  unsigned int count, max;
  Class clazz;

  currentContainer = self;
  paths = [traversal componentsSeparatedByString: @"/"];

  if (!className)
    clazz = [SOGoMailFolder class];
  else
    clazz = NSClassFromString (className);

  max = [paths count];
  for (count = 0; count < max - 1; count++)
    {
      currentName = [NSString stringWithFormat: @"folder%@",
			      [paths objectAtIndex: count]];
      currentContainer = [SOGoMailFolder objectWithName: currentName
					 inContainer: currentContainer];
    }
  currentName = [NSString stringWithFormat: @"folder%@",
			  [paths objectAtIndex: max - 1]];

  return [clazz objectWithName: currentName inContainer: currentContainer];
}

- (SOGoMailFolder *) inboxFolderInContext: (id) _ctx
{
  // TODO: use some profile to determine real location, use a -traverse lookup
  if (!inboxFolder)
    {
      inboxFolder
	= [self folderWithTraversal: [self inboxFolderNameInContext: _ctx]
		andClassName: nil];
      [inboxFolder retain];
    }

  return inboxFolder;
}

- (SOGoDraftsFolder *) draftsFolderInContext: (id) _ctx
{
  // TODO: use some profile to determine real location, use a -traverse lookup

  if (!draftsFolder)
    {
      draftsFolder
	= [self folderWithTraversal: [self draftsFolderNameInContext: _ctx]
		andClassName: @"SOGoDraftsFolder"];
      [draftsFolder retain];
    }

  return draftsFolder;
}

- (SOGoSentFolder *) sentFolderInContext: (id) _ctx
{
  // TODO: use some profile to determine real location, use a -traverse lookup

  if (!sentFolder)
    {
      sentFolder
	= [self folderWithTraversal: [self sentFolderNameInContext: _ctx]
		andClassName: @"SOGoSentFolder"];
      [sentFolder retain];
    }

  return sentFolder;
}

- (SOGoTrashFolder *) trashFolderInContext: (id) _ctx
{
  if (!trashFolder)
    {
      trashFolder
	= [self folderWithTraversal: [self trashFolderNameInContext: _ctx]
		andClassName: @"SOGoTrashFolder"];
      [trashFolder retain];
    }

  return trashFolder;
}

/* WebDAV */

- (NSString *) davContentType
{
  return @"httpd/unix-directory";
}

- (BOOL) davIsCollection
{
  return YES;
}

- (NSException *) davCreateCollection: (NSString *) _name
			    inContext: (id) _ctx
{
  return [[self imap4Connection] createMailbox:_name atURL:[self imap4URL]];
}

- (NSString *) shortTitle
{
  NSString *s, *login, *host;
  NSRange r;

  s = [self nameInContainer];
  
  r = [s rangeOfString:@"@"];
  if (r.length > 0)
    {
      login = [s substringToIndex:r.location];
      host  = [s substringFromIndex:(r.location + r.length)];
    }
  else
    {
      login = nil;
      host  = s;
    }
  
  r = [host rangeOfString:@"."];
  if (r.length > 0)
    host = [host substringToIndex:r.location];
  
  if ([login length] == 0)
    return host;
  
  r = [login rangeOfString:@"."];
  if (r.length > 0)
    login = [login substringToIndex:r.location];
  
  return [NSString stringWithFormat:@"%@@%@", login, host];
}

- (NSString *) davDisplayName
{
  return [self shortTitle];
}

- (NSString *) sharedFolderName
{
  return sharedFolderName;
}

- (NSString *) otherUsersFolderName
{
  return otherUsersFolderName;
}

@end /* SOGoMailAccount */
