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

#include <SOGoUI/UIxComponent.h>

@interface UIxMailView : UIxComponent
{
  id currentAddress;
}

- (BOOL)isDeletableClientObject;

@end

#include <UI/MailPartViewers/UIxMailRenderingContext.h> // cyclic
#include "WOContext+UIxMailer.h"
#include <SoObjects/Mailer/SOGoMailObject.h>
#include <SoObjects/Mailer/SOGoMailAccount.h>
#include <SoObjects/Mailer/SOGoMailFolder.h>
#include <NGImap4/NGImap4Envelope.h>
#include <NGImap4/NGImap4EnvelopeAddress.h>
#include "common.h"

@implementation UIxMailView

static NSString *mailETag = nil;

+ (int)version {
  return [super version] + 0 /* v2 */;
}

+ (void)initialize {
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  
  NSAssert2([super version] == 2,
            @"invalid superclass (%@) version %i !",
            NSStringFromClass([self superclass]), [super version]);
  
  if ([ud boolForKey:@"SOGoDontUseETagsForMailViewer"]) {
    NSLog(@"Note: usage of constant etag for mailer viewer is disabled.");
  }
  else {
    mailETag = [[NSString alloc] initWithFormat:@"\"imap4url_%d_%d_%03d\"",
				 UIX_MAILER_MAJOR_VERSION,
				 UIX_MAILER_MINOR_VERSION,
				 UIX_MAILER_SUBMINOR_VERSION];
    NSLog(@"Note: using constant etag for mail viewer: '%@'", mailETag);
  }
}

- (void)dealloc {
  [super dealloc];
}

/* accessors */

- (void) setCurrentAddress: (id) _addr
{
  currentAddress = _addr;
}

- (id) currentAddress
{
  return currentAddress;
}

- (NSString *) objectTitle
{
  return [[self clientObject] subject];
}

- (NSString *) panelTitle
{
  return [NSString stringWithFormat: @"%@: %@",
                   [self labelForKey: @"View Mail"],
                   [self objectTitle]];
}

/* expunge / delete setup and permissions */

- (BOOL) isTrashingAllowed
{
  id trash;
  
  trash = [[[self clientObject] mailAccountFolder] 
            trashFolderInContext:context];
  if ([trash isKindOfClass:[NSException class]])
    return NO;

  return [trash isWriteAllowed];
}

- (BOOL) showMarkDeletedButton
{
  // TODO: we might also want to add a default to always show delete
  if (![[self clientObject] isDeletionAllowed])
    return NO;
  
  return [self isTrashingAllowed] ? NO : YES;
}

- (BOOL) showTrashButton
{
  if (![[self clientObject] isDeletionAllowed])
    return NO;
  
  return [self isTrashingAllowed];
}

/* links (DUP to UIxMailPartViewer!) */

- (NSString *)linkToEnvelopeAddress:(NGImap4EnvelopeAddress *)_address {
  // TODO: make some web-link, eg open a new compose panel?
  return [@"mailto:" stringByAppendingString:[_address baseEMail]];
}

- (NSString *)currentAddressLink {
  return [self linkToEnvelopeAddress:[self currentAddress]];
}

/* fetching */

- (id)message {
  return [[self clientObject] fetchCoreInfos];
}

- (BOOL)hasCC {
  return [[[self clientObject] ccEnvelopeAddresses] count] > 0 ? YES : NO;
}

/* viewers */

- (id)contentViewerComponent {
  // TODO: I would prefer to flatten the body structure prior rendering,
  //       using some delegate to decide which parts to select for alternative.
  id info;
  
  info = [[self clientObject] bodyStructure];
  return [[context mailRenderingContext] viewerForBodyInfo:info];
}

/* actions */

- (id)defaultAction {
  /* check etag to see whether we really must rerender */
  if (mailETag != nil ) {
    /*
      Note: There is one thing which *can* change for an existing message,
            those are the IMAP4 flags (and annotations, which we do not use).
	    Since we don't render the flags, it should be OK, if this changes
	    we must embed the flagging into the etag.
    */
    NSString *s;
    
    if ((s = [[context request] headerForKey:@"if-none-match"])) {
      if ([s rangeOfString:mailETag].length > 0) { /* not perfectly correct */
	/* client already has the proper entity */
	// [self logWithFormat:@"MATCH: %@ (tag %@)", s, mailETag];
	
	if (![[self clientObject] doesMailExist]) {
	  return [NSException exceptionWithHTTPStatus:404 /* Not Found */
			      reason:@"message got deleted"];
	}
	
	[[context response] setStatus:304 /* Not Modified */];
	return [context response];
      }
    }
  }
  
  if ([self message] == nil) {
    // TODO: redirect to proper error
    return [NSException exceptionWithHTTPStatus:404 /* Not Found */
			reason:@"did not find specified message!"];
  }
  
  return self;
}

- (BOOL)isDeletableClientObject {
  return [[self clientObject] respondsToSelector:@selector(delete)];
}
- (BOOL)isInlineViewer {
  return NO;
}

- (id)redirectToParentFolder {
  id url;
  
  url = [[[self clientObject] container] baseURLInContext:context];
  return [self redirectToLocation:url];
}

- (id)deleteAction {
  NSException *ex;
  
  if (![self isDeletableClientObject]) {
    return [NSException exceptionWithHTTPStatus:400 /* Bad Request */
                        reason:@"method cannot be invoked on "
                               @"the specified object"];
  }
  
  if ([self isInvokedBySafeMethod]) {
    // TODO: fix UI to use POST for unsafe actions
    [self logWithFormat:@"WARNING: method is invoked using safe HTTP method!"];
  }
  
  if ((ex = [[self clientObject] delete]) != nil) {
    id url;
    
    url = [[ex reason] stringByEscapingURL];
    url = [@"view?error=" stringByAppendingString:url];
    return [self redirectToLocation:url];
    //return ex;
  }
  
  if (![self isInlineViewer]) {
    // if everything is ok, close the window (send a JS closing the Window)
    id page;
    
    page = [self pageWithName:@"UIxMailWindowCloser"];
    [page takeValue:@"YES" forKey:@"refreshOpener"];
    return page;
  }
  
  return [self redirectToParentFolder];
}

- (id)trashAction {
  NSException *ex;
  
  if ([self isInvokedBySafeMethod]) {
    // TODO: fix UI to use POST for unsafe actions
    [self logWithFormat:@"WARNING: method is invoked using safe HTTP method!"];
  }
  
  if ((ex = [[self clientObject] trashInContext:context]) != nil) {
    id url;
    
    if ([[[context request] formValueForKey:@"jsonly"] boolValue])
      /* called using XMLHttpRequest */
      return ex;
    
    url = [[ex reason] stringByEscapingURL];
    url = [@"view?error=" stringByAppendingString:url];
    return [self redirectToLocation:url];
  }

  if ([[[context request] formValueForKey:@"jsonly"] boolValue]) {
    /* called using XMLHttpRequest */
    [[context response] setStatus:200 /* OK */];
    return [context response];
  }
  
  if (![self isInlineViewer]) {
    // if everything is ok, close the window (send a JS closing the Window)
    id page;
    
    page = [self pageWithName:@"UIxMailWindowCloser"];
    [page takeValue:@"YES" forKey:@"refreshOpener"];
    return page;
  }
  
  return [self redirectToParentFolder];
}

- (id <WOActionResults>) moveAction
{
  id <WOActionResults> *result;
  NSString *destinationFolder;
  id url;

  if ([self isInvokedBySafeMethod]) {
    // TODO: fix UI to use POST for unsafe actions
    [self logWithFormat:@"WARNING: method is invoked using safe HTTP method!"];
  }

  destinationFolder = [self queryParameterForKey: @"tofolder"];
  if ([destinationFolder length] > 0)
    {
      result = [[self clientObject] moveToFolderNamed: destinationFolder
                                    inContext: context];
      if (result)
        {
          if (![[[context request] formValueForKey:@"jsonly"] boolValue])
            {
              url = [NSString stringWithFormat: @"view?error=%@",
                              [[result reason] stringByEscapingURL]];
              result = [self redirectToLocation: url];
            }
        }
      else
        {
          result = [context response];
          [result setStatus: 200];
        }
    }
  else
    result = [NSException exceptionWithHTTPStatus:500 /* Server Error */
                          reason: @"No destination folder given"];

  return result;
}

- (id)getMailAction {
  // TODO: we might want to flush the caches?
  return [self redirectToLocation:@"view"];
}

/* generating response */

- (void)appendToResponse:(WOResponse *)_response inContext:(WOContext *)_ctx {
  UIxMailRenderingContext *mctx;

  if (mailETag != nil)
    [[_ctx response] setHeader:mailETag forKey:@"etag"];

  mctx = [[NSClassFromString(@"UIxMailRenderingContext")
			    alloc] initWithViewer:self context:_ctx];
  [_ctx pushMailRenderingContext:mctx];
  [mctx release];
  
  [super appendToResponse:_response inContext:_ctx];
  
  [[_ctx popMailRenderingContext] reset];
}

@end /* UIxMailView */
