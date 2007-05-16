/* NSString+Utilities.m - this file is part of SOGo
 *
 * Copyright (C) 2006  Inverse group conseil
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

#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSEnumerator.h>

#import "NSString+Utilities.h"
#import "NSDictionary+URL.h"

static NSMutableCharacterSet *urlNonEndingChars = nil;
static NSMutableCharacterSet *urlAfterEndingChars = nil;

@implementation NSString (SOGoURLExtension)

- (NSString *) composeURLWithAction: (NSString *) action
			 parameters: (NSDictionary *) urlParameters
			    andHash: (BOOL) useHash
{
  NSMutableString *completeURL;

  completeURL = [NSMutableString new];
  [completeURL autorelease];

  [completeURL appendString: [self urlWithoutParameters]];
  if (![completeURL hasSuffix: @"/"])
    [completeURL appendString: @"/"];
  [completeURL appendString: action];
  [completeURL appendString: [urlParameters asURLParameters]];
  if (useHash)
    [completeURL appendString: @"#"];

  return completeURL;
}

- (NSString *) hostlessURL
{
  NSString *newURL;
  NSRange hostR, locationR;

  if ([self hasPrefix: @"/"])
    {
      newURL = [self copy];
      [newURL autorelease];
    }
  else
    {
      hostR = [self rangeOfString: @"://"];
      locationR = [[self substringFromIndex: (hostR.location + hostR.length)]
                    rangeOfString: @"/"];
      newURL = [self substringFromIndex: (hostR.location + hostR.length + locationR.location)];
    }

  return newURL;
}

- (NSString *) urlWithoutParameters;
{
  NSRange r;
  NSString *newUrl;
  
  r = [self rangeOfString:@"?" options: NSBackwardsSearch];
  if (r.length > 0)
    newUrl = [self substringToIndex: NSMaxRange(r) - 1];
  else
    newUrl = self;

  return newUrl;
}

- (NSString *) davMethodToObjC
{
  NSMutableString *newName;
  NSEnumerator *components;
  NSString *component;

  newName = [NSMutableString stringWithString: @"dav"];
  components = [[self componentsSeparatedByString: @"-"] objectEnumerator];
  component = [components nextObject];
  while (component)
    {
      [newName appendString: [component capitalizedString]];
      component = [components nextObject];
    }

  return newName;
}

- (NSRange) _rangeOfURLInRange: (NSRange) refRange
{
  int start, length;
  NSRange workRange;

  if (!urlNonEndingChars)
    {
      urlNonEndingChars = [NSMutableCharacterSet new];
      [urlNonEndingChars addCharactersInString: @">&=,.:;\t \r\n"];
    }
  if (!urlAfterEndingChars)
    {
      urlAfterEndingChars = [NSMutableCharacterSet new];
      [urlAfterEndingChars addCharactersInString: @"&;<\t \r\n"];
    }

  start = refRange.location;
  while (start > -1
	 && ![urlAfterEndingChars characterIsMember:
				    [self characterAtIndex: start]])
    start--;
  start++;
  length = [self length] - start;
  workRange = NSMakeRange (start, length);
  workRange = [self rangeOfCharacterFromSet: urlAfterEndingChars
		    options: NSLiteralSearch range: workRange];
  if (workRange.location != NSNotFound)
    length = workRange.location - start;
  while
    (length > 0
     && [urlNonEndingChars characterIsMember:
			     [self characterAtIndex: (start + length - 1)]])
    length--;

  return NSMakeRange (start, length);
}

- (void) _handleURLs: (NSMutableString *) selfCopy
	 textToMatch: (NSString *) match
	      prefix: (NSString *) prefix
{
  NSRange httpRange, currentURL, rest;
  NSString *urlText, *newUrlText;
  unsigned int length, matchLength;

  matchLength = [match length];
  httpRange = [selfCopy rangeOfString: match];
  while (httpRange.location != NSNotFound)
    {
      currentURL = [selfCopy _rangeOfURLInRange: httpRange];
      urlText = [selfCopy substringFromRange: currentURL];
      if ([urlText length] > matchLength)
	{
	  newUrlText = [NSString stringWithFormat: @"<a href=\"%@%@\">%@</a>",
				 prefix, urlText, urlText];
	  [selfCopy replaceCharactersInRange: currentURL
		    withString: newUrlText];
	  rest.location = currentURL.location + [newUrlText length];
	}
      else
	rest.location = currentURL.location + currentURL.length;
      length = [selfCopy length];
      rest.length = length - rest.location;
      httpRange = [selfCopy rangeOfString: match
			    options: 0 range: rest];
    }
}

- (NSString *) stringByDetectingURLs
{
  NSMutableString *selfCopy;

  selfCopy = [NSMutableString stringWithString: self];
  [self _handleURLs: selfCopy textToMatch: @"://" prefix: @""];
  [self _handleURLs: selfCopy textToMatch: @"@" prefix: @"mailto:"];

  return selfCopy;
}

#if LIB_FOUNDATION_LIBRARY
- (BOOL) boolValue
{
  return !([self isEqualToString: @"0"]
	   || [self isEqualToString: @"NO"]);
}
#endif

@end
