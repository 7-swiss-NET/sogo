/* UIxMailPartSignedViewer.m - this file is part of SOGo
 *
 * Copyright (C) 2009 Inverse inc.
 *
 * Author: Wolfgang Sourdeau <wsourdeau@inverse.ca>
 *         Ludovic Marcotte <lmarcotte@inverse.ca>
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

#include <stdio.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pkcs7.h>
#include <openssl/x509.h>

#import <Foundation/NSArray.h>

#import <NGExtensions/NSString+misc.h>
#import <NGMail/NGMimeMessage.h>
#import <NGMail/NGMimeMessageParser.h>
#import <NGMime/NGMimeBodyPart.h>
#import <NGMime/NGMimeMultipartBody.h>
#import <NGMime/NGMimeType.h>
#import <NGMime/NGPart.h>

#import <Mailer/SOGoMailBodyPart.h>
#import <Mailer/SOGoMailObject.h>

#import <SOGo/NSString+Utilities.h>
#import <Mailer/NSString+Mail.h>

#import "UIxMailPartSignedViewer.h"

@interface NGMimeMessage (SOGoExtension)

- (id <NGMimePart>) mimePartFromPath: (NSArray *) path;

@end

@implementation NGMimeMessage (SOGoExtension)

- (id <NGMimePart>) mimePartFromPath: (NSArray *) path
{
  int count, max, partNumber;
  BOOL overflow;
  id <NGMimePart> currentPart, foundPart;
  NSArray *parts;

  foundPart = nil;
  overflow = NO;

  currentPart = [self body];

  max = [path count];
  for (count = 0; (!overflow && !foundPart) && count < max; count++)
    {
      partNumber = [[path objectAtIndex: count] intValue];
      if (partNumber == 0)
        foundPart = currentPart;
      else
        {
          if ([currentPart isKindOfClass: [NGMimeMultipartBody class]])
            {
              parts = [(NGMimeMultipartBody *) currentPart parts];
              if (partNumber <= [parts count])
                currentPart = [parts objectAtIndex: partNumber - 1];
              else
                overflow = YES;
            }
          else
            overflow = YES;
        }
    }
  if (!overflow)
    foundPart = currentPart;

  return foundPart;
}

@end

@interface NGMimeType (SOGoExtension)

- (BOOL) isEqualToString: (NSString *) otherType;

@end

@implementation NGMimeType (SOGoExtension)

- (BOOL) isEqualToString: (NSString *) otherType
{
  NSString *thisString;

  thisString = [NSString stringWithFormat: @"%@/%@",
                         [self type], [self subType]];

  return [thisString isEqualToString: otherType];
}

@end

@implementation UIxMailPartSignedViewer : UIxMailPartViewer

- (void) _setupParts
{
  NSData *content;
  NGMimeMessageParser *parser;
  NGMimeMessage *message;
  NSArray *path;
  id co;
  NSArray *parts;

  co = [self clientObject];

  content = [co content];
  parser = [NGMimeMessageParser new];
  message = [parser parsePartFromData: content];
  if ([co respondsToSelector: @selector (bodyPartPath)])
    path = [(SOGoMailBodyPart *) co bodyPartPath];
  else
    path = [NSArray arrayWithObject: @"0"];
  parts = [(NGMimeMultipartBody *) [message mimePartFromPath: path] parts];
  if ([parts count] == 2)
    messagePart = [parts objectAtIndex: 0];

  [parser release];
}

- (NSString *) flatContentAsString
{
  NSString *body, *content;
  NGMimeType *mimeType;

  [self _setupParts];

  mimeType = [messagePart contentType];
  if ([mimeType isEqualToString: @"text/plain"])
    {
      body = [[messagePart body] stringByEscapingHTMLString];
      content = [[body stringByDetectingURLs]
                  stringByConvertingCRLNToHTML];
    }
  else if ([mimeType isEqualToString: @"multipart/alternative"])
    {
      NSArray *parts;
      int i;
      
      parts = [(NGMimeMultipartBody *)[messagePart body] parts];

      for (i = 0; i < [parts count]; i++)
	{
	  mimeType = [[parts objectAtIndex: i] contentType];

	  if ([mimeType isEqualToString: @"text/plain"])
	    {
	      body = [[[parts objectAtIndex: i] body] stringByEscapingHTMLString];
	      content = [[body stringByDetectingURLs]
			  stringByConvertingCRLNToHTML];
	      break;
	    }
	  else
	    content = nil;
	}
     
    }
  else
    {
      NSLog (@"unhandled mime type in multipart/signed: '%@'", mimeType);
      content = nil;
    }

  return content;
}

- (X509_STORE *) _setupVerify
{
  X509_STORE *store;
  X509_LOOKUP *lookup;
  BOOL success;

  success = NO;

  store = X509_STORE_new ();
  if (store)
    {
      lookup = X509_STORE_add_lookup (store, X509_LOOKUP_file());
      if (lookup)
        {
          X509_LOOKUP_load_file (lookup, NULL, X509_FILETYPE_DEFAULT);
          lookup = X509_STORE_add_lookup (store, X509_LOOKUP_hash_dir());
          if (lookup)
            {
              X509_LOOKUP_add_dir (lookup, NULL, X509_FILETYPE_DEFAULT);
              ERR_clear_error();
              success = YES;
            }
        }
    }

  if (!success)
    {
      if (store)
        {
          X509_STORE_free(store);
          store = NULL;
        }
    }

  return store;
}

- (void) _processMessage
{
  NSString *issuer, *subject;
  NSData *signedData;
  
  STACK_OF(X509) *certs;
  X509_STORE *x509Store;
  BIO *msgBio, *inData;
  char sslError[1024];
  PKCS7 *p7;
  int err, i;
 

  *sslError = 0;

  ERR_clear_error();

  signedData = [[self clientObject] content];
  msgBio = BIO_new_mem_buf ((void *) [signedData bytes], [signedData length]);

  inData = NULL;
  p7 = SMIME_read_PKCS7(msgBio, &inData);

  subject = nil;
  issuer = nil;
  certs = NULL;
  
  i = OBJ_obj2nid(p7->type);
  
  if (i == NID_pkcs7_signed)
    {
      X509 *x;

      certs=p7->d.sign->cert;

      if (sk_X509_num(certs) > 0)
	{
	  BIO *buf;
	  char p[256];

	  memset(p, 0, 256);
	  x = sk_X509_value(certs,0);
	  buf = BIO_new(BIO_s_mem());
	  X509_NAME_print_ex(buf, X509_get_subject_name(x), 0,  XN_FLAG_FN_SN);
	  BIO_gets(buf, p, 256);
	  subject = [NSString stringWithUTF8String: p];

	  memset(p, 0, 256);
	  X509_NAME_print_ex(buf, X509_get_issuer_name(x), 0,  XN_FLAG_FN_SN);
	  BIO_gets(buf, p, 256);
	  issuer = [NSString stringWithUTF8String: p];

	  BIO_free(buf);
	}
    }
 
  err = ERR_get_error();
  if (err)
    {
      ERR_error_string_n (err, sslError, 1023);
      validSignature = NO;
    }
  else
    {
      x509Store = [self _setupVerify];
      validSignature = (PKCS7_verify(p7, NULL, x509Store, inData,
                                     NULL, PKCS7_DETACHED) == 1);

      err = ERR_get_error();
      if (err)
        ERR_error_string_n(err, sslError, 1023);

      if (x509Store)
        X509_STORE_free (x509Store);
    }

  BIO_free (msgBio);
  if (inData)
    BIO_free (inData);

  validationMessage = [NSMutableString string];

  if (!validSignature)
    [validationMessage appendString: [self labelForKey: @"Digital signature is not valid"]];
  else
    [validationMessage appendString: [self labelForKey: @"Message is signed"]];
  
  if (issuer && subject)
    [validationMessage appendFormat: @"\n%@: %@\n%@: %@",
		   [self labelForKey: @"Subject"], subject,
		     [self labelForKey: @"Issuer"], issuer];
		   
  processed = YES;
}

- (BOOL) validSignature
{
  if (!processed)
    [self _processMessage];

  return validSignature;
}

- (NSString *) validationMessage
{
  if (!processed)
    [self _processMessage];

  return validationMessage;
}

@end
