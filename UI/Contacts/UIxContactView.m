/*
  Copyright (C) 2004 SKYRIX Software AG
  Copyright (C) 2005-2010 Inverse inc.

  This file is part of SOGo.
 
  SOGo is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.
 
  SOGo is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.
 
  You should have received a copy of the GNU Lesser General Public
  License along with OGo; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/WOResponse.h>
#import <NGCards/NGVCard.h>
#import <NGCards/CardElement.h>
#import <NGCards/NSArray+NGCards.h>
#import <NGExtensions/NSString+Ext.h>

#import <SoObjects/Contacts/SOGoContactObject.h>

#import "UIxContactView.h"

@implementation UIxContactView

/* accessors */

- (NSString *)tabSelection {
  NSString *selection;
    
  selection = [self queryParameterForKey:@"tab"];
  if (selection == nil)
    selection = @"attributes";
  return selection;
}

- (NSString *) _cardStringWithLabel: (NSString *) label
                              value: (NSString *) value
{
  NSMutableString *cardString;

  cardString = [NSMutableString string];
  if (value && [value length] > 0)
    {
      if (label)
        [cardString appendFormat: @"%@&nbsp;%@<br />\n",
                    [self labelForKey: label], value];
      else
        [cardString appendFormat: @"%@<br />\n", value];
    }

  return cardString;
}

- (NSString *) contactCardTitle
{
  return [NSString stringWithFormat:
                     [self labelForKey: @"Card for %@"],
		   [self fullName]];
}

- (NSString *) displayName
{
  return [self _cardStringWithLabel: @"Display Name:"
               value: [card fn]];
}

- (NSString *) nickName
{
  return [self _cardStringWithLabel: @"Nickname:"
               value: [card nickname]];
}

- (NSString *) fullName
{
  NSArray *n;
  NSString *fn;
  unsigned int max;
  
  fn = [card fn];
  if ([fn length] == 0)
    {
      n = [card n];
      if (n)
	{
	  max = [n count];
	  if (max > 0)
	    {
	      if (max > 1)
		fn = [NSString stringWithFormat: @"%@ %@", [n objectAtIndex: 1], [n objectAtIndex: 0]];
	      else
		fn = [n objectAtIndex: 0];
	    }
	}
    }

  return fn;
}

- (NSString *) primaryEmail
{
  NSString *email, *mailTo;

  email = [card preferredEMail];
  if ([email length] > 0)
    mailTo = [NSString stringWithFormat: @"<a href=\"mailto:%@\""
                       @" onclick=\"return openMailTo('%@ <%@>');\">"
                       @"%@</a>", email, [[card fn] stringByReplacingString: @"\""  withString: @""], email, email];
  else
    mailTo = nil;

  return [self _cardStringWithLabel: @"Email:"
               value: mailTo];
}

- (NSString *) secondaryEmail
{
  NSString *email, *mailTo;
  NSMutableArray *emails;

  emails = [NSMutableArray array];
  mailTo = nil;

  [emails addObjectsFromArray: [card childrenWithTag: @"email"]];
  [emails removeObjectsInArray: [card childrenWithTag: @"email"
				      andAttribute: @"type"
				      havingValue: @"pref"]];

  // We might not have a preferred item but rather something like this:
  // EMAIL;TYPE=work:dd@ee.com
  // EMAIL;TYPE=home:ff@gg.com
  // In this case, we always return the last entry.
  if ([emails count] > 0)
    {
      email = [[emails objectAtIndex: [emails count]-1] value: 0];

      if ([email caseInsensitiveCompare: [card preferredEMail]] != NSOrderedSame)
	mailTo = [NSString stringWithFormat: @"<a href=\"mailto:%@\""
			   @" onclick=\"return openMailTo('%@ <%@>');\">"
			   @"%@</a>", email, [[card fn] stringByReplacingString: @"\""  withString: @""], email, email];
    }

  return [self _cardStringWithLabel: @"Additional Email:"
               value: mailTo];
}

- (NSString *) screenName
{
  NSString *screenName, *goim;

  screenName = [[card uniqueChildWithTag: @"x-aim"] value: 0];
  if ([screenName length] > 0)
    goim = [NSString stringWithFormat: @"<a href=\"aim:goim?screenname=%@\""
		     @">%@</a>", screenName, screenName];
  else
    goim = nil;

  return [self _cardStringWithLabel: @"Screen Name:" value: goim];
}

- (NSString *) preferredTel
{
  return [self _cardStringWithLabel: @"Phone Number:"
               value: [card preferredTel]];
}

- (NSString *) preferredAddress
{
  return @"";
}

- (BOOL) hasTelephones
{
  if (!phones)
    phones = [card childrenWithTag: @"tel"];

  return ([phones count] > 0);
}

- (NSString *) _phoneOfType: (NSString *) aType
                  withLabel: (NSString *) aLabel
{
  NSArray *elements;
  NSString *phone;

  elements = [phones cardElementsWithAttribute: @"type"
                     havingValue: aType];

  if ([elements count] > 0)
    phone = [[elements objectAtIndex: 0] value: 0];
  else
    phone = nil;

  return [self _cardStringWithLabel: aLabel value: phone];
}

- (NSString *) workPhone
{
  return [self _phoneOfType: @"work" withLabel: @"Work:"];
}

- (NSString *) homePhone
{
  return [self _phoneOfType: @"home" withLabel: @"Home:"];
}

- (NSString *) fax
{
  return [self _phoneOfType: @"fax" withLabel: @"Fax:"];
}

- (NSString *) mobile
{
  return [self _phoneOfType: @"cell" withLabel: @"Mobile:"];
}

- (NSString *) pager
{
  return [self _phoneOfType: @"pager" withLabel: @"Pager:"];
}

- (BOOL) hasHomeInfos
{
  BOOL result;
  NSArray *elements;

  elements = [card childrenWithTag: @"adr"
                   andAttribute: @"type"
                   havingValue: @"home"];
  if ([elements count] > 0)
    {
      result = YES;
      homeAdr = [elements objectAtIndex: 0];
    }
  else
    result = ([[card childrenWithTag: @"url"
                     andAttribute: @"type"
                     havingValue: @"home"] count] > 0);

  return result;
}

- (NSString *) homePobox
{
  return [self _cardStringWithLabel: nil value: [homeAdr value: 0]];
}

- (NSString *) homeExtendedAddress
{
  return [self _cardStringWithLabel: nil value: [homeAdr value: 1]];
}

- (NSString *) homeStreetAddress
{
  return [self _cardStringWithLabel: nil value: [homeAdr value: 2]];
}

- (NSString *) homeCityAndProv
{
  NSString *city, *prov;
  NSMutableString *data;

  city = [homeAdr value: 3];
  prov = [homeAdr value: 4];

  data = [NSMutableString string];
  [data appendString: city];
  if ([city length] > 0 && [prov length] > 0)
    [data appendString: @", "];
  [data appendString: prov];

  return [self _cardStringWithLabel: nil value: data];
}

- (NSString *) homePostalCodeAndCountry
{
  NSString *postalCode, *country;
  NSMutableString *data;

  postalCode = [homeAdr value: 5];
  country = [homeAdr value: 6];

  data = [NSMutableString string];
  [data appendString: postalCode];
  if ([postalCode length] > 0 && [country length] > 0)
    [data appendFormat: @", ", country];
  [data appendString: country];

  return [self _cardStringWithLabel: nil value: data];
}

- (NSString *) _formattedURL: (NSString *) url
{
  NSString *data;

  data = nil;

  if (url)
    {
      if (![[url lowercaseString] rangeOfString: @"://"].length)
	url = [NSString stringWithFormat: @"http://%@", url];
      
      data = [NSString stringWithFormat:
                         @"<a href=\"%@\" target=\"_blank\">%@</a>",
                       url, url];
    }

  return [self _cardStringWithLabel: nil value: data];
}


- (NSString *) _urlOfType: (NSString *) aType
{
  NSArray *elements;
  NSString *url;

  elements = [card childrenWithTag: @"url"
                   andAttribute: @"type"
                   havingValue: aType];
  if ([elements count] > 0)
    url = [[elements objectAtIndex: 0] value: 0];
  else
    url = nil;

  return [self _formattedURL: url];
}

- (NSString *) homeUrl
{
  NSString *s;

  s = [self _urlOfType: @"home"];

  if (!s || [s length] == 0)
    {
      NSArray *elements;
      NSString *workURL;
      int i;
      
      elements = [card childrenWithTag: @"url"
		       andAttribute: @"type"
		       havingValue: @"work"];
      workURL = nil;

      if ([elements count] > 0)
	workURL = [[elements objectAtIndex: 0] value: 0];

      elements = [card childrenWithTag: @"url"];

      if (workURL && [elements count] > 1)
	{
	  for (i = 0; i < [elements count]; i++)
	    {
	      if ([[[elements objectAtIndex: i] value: 0] caseInsensitiveCompare: workURL] != NSOrderedSame)
		{
		  s = [[elements objectAtIndex: i] value: 0];
		  break;
		}
	    }
	  
	}
      else if (!workURL && [elements count] > 0)
	{
	  s = [[elements objectAtIndex: 0] value: 0];
	}

      if (s && [s length] > 0)
	s = [self _formattedURL: s];
    }
  
  return s;
}

- (BOOL) hasWorkInfos
{
  BOOL result;
  NSArray *elements;

  elements = [card childrenWithTag: @"adr"
                   andAttribute: @"type"
                   havingValue: @"work"];
  if ([elements count] > 0)
    {
      result = YES;
      workAdr = [elements objectAtIndex: 0];
    }
  else
    result = (([[card childrenWithTag: @"url"
                      andAttribute: @"type"
		      havingValue: @"work"] count] > 0)
              || [[card childrenWithTag: @"org"] count] > 0);

  return result;
}

- (NSString *) workTitle
{
  return [self _cardStringWithLabel: nil value: [card title]];
}

- (NSString *) workService
{
  NSMutableArray *orgServices;
  NSArray *org;
  NSRange aRange;
  NSString *services;

  org = [card org];
  if (org && [org count] > 1)
    {
      aRange = NSMakeRange(1, [org count]-1);
      orgServices = [NSMutableArray arrayWithArray: [org subarrayWithRange: aRange]];
      
      while ([orgServices containsObject: @""])
	[orgServices removeObject: @""];

      services = [orgServices componentsJoinedByString: @", "];
    }
  else
    services = nil;

  return [self _cardStringWithLabel: nil value: services];
}

- (NSString *) workCompany
{
  NSArray *org;
  NSString *company;

  org = [card org];
  if (org && [org count] > 0)
    company = [org objectAtIndex: 0];
  else
    company = nil;

  return [self _cardStringWithLabel: nil value: company];
}

- (NSString *) workPobox
{
  return [self _cardStringWithLabel: nil value: [workAdr value: 0]];
}

- (NSString *) workExtendedAddress
{
  return [self _cardStringWithLabel: nil value: [workAdr value: 1]];
}

- (NSString *) workStreetAddress
{
  return [self _cardStringWithLabel: nil value: [workAdr value: 2]];
}

- (NSString *) workCityAndProv
{
  NSString *city, *prov;
  NSMutableString *data;

  city = [workAdr value: 3];
  prov = [workAdr value: 4];

  data = [NSMutableString string];
  [data appendString: city];
  if ([city length] > 0 && [prov length] > 0)
    [data appendString: @", "];
  [data appendString: prov];

  return [self _cardStringWithLabel: nil value: data];
}

- (NSString *) workPostalCodeAndCountry
{
  NSString *postalCode, *country;
  NSMutableString *data;

  postalCode = [workAdr value: 5];
  country = [workAdr value: 6];

  data = [NSMutableString string];
  [data appendString: postalCode];
  if ([postalCode length] > 0 && [country length] > 0)
    [data appendFormat: @", ", country];
  [data appendString: country];

  return [self _cardStringWithLabel: nil value: data];
}

- (NSString *) workUrl
{
  return [self _urlOfType: @"work"];
}

- (BOOL) hasOtherInfos
{
  return ([[card note] length] > 0
          || [[card bday] length] > 0
          || [[card tz] length] > 0);
}

- (NSString *) bday
{
  return [self _cardStringWithLabel: @"Birthday:" value: [card bday]];
}

- (NSString *) tz
{
  return [self _cardStringWithLabel: @"Timezone:" value: [card tz]];
}

- (NSString *) note
{
  NSString *note;

  note = [card note];
  if (note)
    {
      note = [note stringByReplacingString: @"\r\n"
                   withString: @"<br />"];
      note = [note stringByReplacingString: @"\n"
                   withString: @"<br />"];
    }

  return [self _cardStringWithLabel: @"Note:" value: note];
}

/* hrefs */

- (NSString *) completeHrefForMethod: (NSString *) _method
                       withParameter: (NSString *) _param
                              forKey: (NSString *) _key
{
  NSString *href;

  [self setQueryParameter:_param forKey:_key];
  href = [self completeHrefForMethod:[self ownMethodName]];
  [self setQueryParameter:nil forKey:_key];

  return href;
}

- (NSString *)attributesTabLink {
  return [self completeHrefForMethod:[self ownMethodName]
	       withParameter:@"attributes"
	       forKey:@"tab"];
}
- (NSString *)debugTabLink {
  return [self completeHrefForMethod:[self ownMethodName]
	       withParameter:@"debug"
	       forKey:@"tab"];
}

/* action */

- (id <WOActionResults>) vcardAction
{
#warning this method is unused
  WOResponse *response;

  card = [[self clientObject] vCard];
  if (card)
    {
      response = [context response];
      [response setHeader: @"text/vcard" forKey: @"Content-type"];
      [response appendContentString: [card versitString]];
    }
  else
    return [NSException exceptionWithHTTPStatus: 404 /* Not Found */
                        reason:@"could not locate contact"];

  return response;
}

- (id <WOActionResults>) defaultAction
{
  card = [[self clientObject] vCard];
  if (card)
    {
      phones = nil;
      homeAdr = nil;
      workAdr = nil;
    }
  else
    return [NSException exceptionWithHTTPStatus: 404 /* Not Found */
                        reason: @"could not locate contact"];

  return self;
}

@end /* UIxContactView */
