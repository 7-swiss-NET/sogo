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

#include "UIxMailPartViewer.h"
#include "UIxMailRenderingContext.h"
#include "UIxMailSizeFormatter.h"
#include "../MailerUI/WOContext+UIxMailer.h"
#include <NGExtensions/NSString+Encoding.h>
#include "common.h"

@implementation UIxMailPartViewer

- (void)dealloc {
  [self->flatContent release];
  [self->bodyInfo    release];
  [self->partPath    release];
  [super dealloc];
}

/* caches */

- (void)resetPathCaches {
  /* this is called when -setPartPath: is called */
  [self->flatContent release]; self->flatContent = nil;
}
- (void)resetBodyInfoCaches {
}

/* notifications */

- (void)sleep {
  [self resetPathCaches];
  [self resetBodyInfoCaches];
  [self->partPath release]; self->partPath = nil;
  [self->bodyInfo release]; self->bodyInfo = nil;
  [super sleep];
}

/* accessors */

- (void)setPartPath:(NSArray *)_path {
  if ([_path isEqual:self->partPath])
    return;
  
  ASSIGN(self->partPath, _path);
  [self resetPathCaches];
}
- (NSArray *)partPath {
  return self->partPath;
}

- (void)setBodyInfo:(id)_info {
  ASSIGN(self->bodyInfo, _info);
}
- (id)bodyInfo {
  return self->bodyInfo;
}

- (NSData *)flatContent {
  if (self->flatContent != nil)
    return [self->flatContent isNotNull] ? self->flatContent : nil;
  
  self->flatContent = 
    [[[[self context] mailRenderingContext] flatContentForPartPath:
					      [self partPath]] retain];
  return self->flatContent;
}

- (NSData *)decodedFlatContent {
  NSString *enc;
  
  enc = [[(NSDictionary *)[self bodyInfo] 
			  objectForKey:@"encoding"] lowercaseString];
  
  if ([enc isEqualToString:@"7bit"])
    return [self flatContent];
  
  if ([enc isEqualToString:@"8bit"]) // TODO: correct?
    return [self flatContent];
  
  if ([enc isEqualToString:@"base64"])
    return [[self flatContent] dataByDecodingBase64];

  if ([enc isEqualToString:@"quoted-printable"])
    return [[self flatContent] dataByDecodingQuotedPrintable];
  
  [self errorWithFormat:@"unsupported MIME encoding: %@", enc];
  return [self flatContent];
}

- (NSStringEncoding)fallbackStringEncoding {
  return 0;
}
- (NSString *)flatContentAsString {
  /* Note: we even have the line count in the body-info! */
  NSString *charset;
  NSString *s;
  NSData   *content;
  
  if ((content = [self decodedFlatContent]) == nil) {
    [self errorWithFormat:@"got no text content: %@", 
	    [[self partPath] componentsJoinedByString:@"."]];
    return nil;
  }
  
  charset = [(NSDictionary *)
	      [(NSDictionary *)[self bodyInfo] objectForKey:@"parameterList"] 
	                                       objectForKey:@"charset"];
  charset = [charset lowercaseString];
  
  // TODO: properly decode charset, might need to handle encoding?
  
  if ([charset length] > 0) {
    s = [NSString stringWithData:content usingEncodingNamed:charset];
  }
  else {
    s = [[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding];
    s = [s autorelease];
  }
  
  if (s == nil) {
    /* 
       Note: this can happend with iCalendar invitations sent by Outlook 2002.
             It will mark the content as UTF-8 but actually deliver it as
	     Latin-1 (or Windows encoding?).
    */
    [self errorWithFormat:@"could not convert content to text, charset: '%@'",
            charset];
    if ([self fallbackStringEncoding] > 0) {
      s = [[NSString alloc] initWithData:content 
			    encoding:[self fallbackStringEncoding]];
      s = [s autorelease];
      
      if (s == nil) {
	[self errorWithFormat:
		@"  an attempt to use fallback encoding failed to."];
      }
    }
  }
  return s;
}

/* path extension */

- (NSString *)pathExtensionForType:(NSString *)_mt subtype:(NSString *)_st {
  // TODO: support /etc/mime.types
  
  if (![_mt isNotNull] || ![_st isNotNull])
    return nil;
  if ([_mt length] == 0) return nil;
  if ([_st length] == 0) return nil;
  _mt = [_mt lowercaseString];
  _st = [_st lowercaseString];
  
  if ([_mt isEqualToString:@"image"]) {
    if ([_st isEqualToString:@"gif"])  return @"gif";
    if ([_st isEqualToString:@"jpeg"]) return @"jpg";
    if ([_st isEqualToString:@"png"])  return @"png";
  }
  else if ([_mt isEqualToString:@"text"]) {
    if ([_st isEqualToString:@"plain"])    return @"txt";
    if ([_st isEqualToString:@"xml"])      return @"xml";
    if ([_st isEqualToString:@"calendar"]) return @"ics";
    if ([_st isEqualToString:@"x-vcard"])  return @"vcf";
  }
  else if ([_mt isEqualToString:@"message"]) {
    if ([_st isEqualToString:@"rfc822"]) return @"mail";
  }
  else if ([_mt isEqualToString:@"application"]) {
    if ([_st isEqualToString:@"pdf"]) return @"pdf";
  }
  return nil;
}

- (NSString *)preferredPathExtension {
  return [self pathExtensionForType:[[self bodyInfo] valueForKey:@"type"]
	       subtype:[[self bodyInfo] valueForKey:@"subtype"]];
}

- (NSString *)filename {
  id tmp;
  
  tmp = [[self bodyInfo] valueForKey:@"parameterList"];
  if (![tmp isNotNull])
    return nil;
  
  tmp = [tmp valueForKey:@"name"];
  if (![tmp isNotNull])
    return nil;
  if ([tmp length] == 0)
    return nil;
  
  return tmp;
}

- (NSString *)filenameForDisplay {
  NSString *s;
  
  if ((s = [self filename]) != nil)
    return s;
  
  s = [[self partPath] componentsJoinedByString:@"-"];
  return ([s length] > 0)
    ? [@"untitled-" stringByAppendingString:s]
    : @"untitled";
}

- (NSFormatter *)sizeFormatter {
  return [UIxMailSizeFormatter sharedMailSizeFormatter];
}

/* URL generation */

- (NSString *)pathToAttachmentObject {
  /* this points to the SoObject representing the part, no modifications */
  NSString *url, *n, *pext;

  /* path to mail controller object */
  
  url = [[self clientObject] baseURLInContext:[self context]];
  if (![url hasSuffix:@"/"]) url = [url stringByAppendingString:@"/"];
  
  /* mail relative path to body-part */
  
  if ([(n = [[self partPath] componentsJoinedByString:@"/"]) isNotNull]) {
    /* eg this was nil for a draft containing an HTML message */
    url = [url stringByAppendingString:n];
  }
  
  /* we currently NEED the extension for SoObject lookup (should be fixed) */
  
  pext = [self preferredPathExtension];
  if ([pext isNotNull] && [pext length] > 0) {
    /* attach extension */
    if ([url hasSuffix:@"/"]) {
      /* this happens if the part is the root-content of the mail */
      url = [url substringToIndex:([url length] - 1)];
    }
    url = [url stringByAppendingString:@"."];
    url = [url stringByAppendingString:pext];
  }
  
  return url;
}

- (NSString *)pathToAttachment {
  /* this generates a more beautiful 'download' URL for a part */
  NSString *url, *fn;

  fn   = [self filename];
  
  if (![fn isNotNull] || ([fn length] == 0))
    fn = nil;

  /* get basic URL */

  url = [self pathToAttachmentObject];
  
  /* 
     If we have an attachment name, we attach it, this is properly handled by
     SOGoMailBodyPart.
  */
  
  if (fn != nil) {
    if (![url hasSuffix:@"/"]) url = [url stringByAppendingString:@"/"];
    if (isdigit([fn characterAtIndex:0]))
      url = [url stringByAppendingString:@"fn-"];
    url = [url stringByAppendingString:[fn stringByEscapingURL]];
    
    // TODO: should we check for a proper extension?
  }
  
  return url;
}

@end /* UIxMailPartViewer */
