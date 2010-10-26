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
#import <Foundation/NSDictionary.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGExtensions/NSObject+Logs.h>

#import <GDLContentStore/GCSFieldExtractor.h>
#import <NGCards/NGVCard.h>
#import <NGCards/NGVList.h>

#import <SOGo/NSArray+Utilities.h>

@interface OCSContactFieldExtractor : GCSFieldExtractor
@end

@implementation OCSContactFieldExtractor

- (NSMutableDictionary *) extractQuickFieldsFromVCard: (NGVCard *) vCard
{
  NSMutableDictionary *fields;
  NSArray *values;
  CardElement *adr;
  NSString *value;
  unsigned int max;

  fields = [NSMutableDictionary dictionaryWithCapacity: 16];

  value = [vCard fn];
  if (value)
    [fields setObject: value forKey: @"c_cn"];
  values = [vCard n];
  if (values)
    {
      max = [values count];
      if (max > 0)
        {
          [fields setObject: [values objectAtIndex: 0] forKey: @"c_sn"];
          if (max > 1)
            [fields setObject: [values objectAtIndex: 1]
                    forKey: @"c_givenName"];
        }
    }
  value = [vCard preferredTel];
  if (value)
    [fields setObject: value forKey: @"c_telephoneNumber"];
  value = [vCard preferredEMail];
  if (![value isNotNull])
    value = @"";
  [fields setObject: value forKey: @"c_mail"];
  values = [vCard org];
  max = [values count];
  if (max > 0)
    {
      [fields setObject: [values objectAtIndex: 0] forKey: @"c_o"];
      if (max > 1)
	[fields setObject: [values objectAtIndex: 1] forKey: @"c_ou"];
    }
  adr = [vCard preferredAdr];
  if (adr)
    [fields setObject: [adr value: 3] forKey: @"c_l"];
  value = [[vCard uniqueChildWithTag: @"X-AIM"] value: 0];
  [fields setObject: value forKey: @"c_screenname"];
  values = [[vCard categories] trimmedComponents];
  if ([values count] > 0)
    [fields setObject: [values componentsJoinedByString: @","]
               forKey: @"c_categories"];
  [fields setObject: @"vcard" forKey: @"c_component"];

  return fields;
}

- (NSMutableDictionary *) extractQuickFieldsFromVList: (NGVList *) vList
{
  NSMutableDictionary *fields;
  NSString *value;

  fields = [NSMutableDictionary dictionaryWithCapacity: 1];

  value = [vList fn];
  if (value)
    [fields setObject: value forKey: @"c_cn"];
  [fields setObject: @"vlist" forKey: @"c_component"];

  return fields;
}

- (NSMutableDictionary *) extractQuickFieldsFromContent: (NSString *) content
{
  NSMutableDictionary *fields;
  NGVCard *vCard;
  NGVList *vList;
  NSString *upperContent;

  fields = nil;
  if ([content length] > 0)
    {
      upperContent = [content uppercaseString];
      if ([upperContent hasPrefix: @"BEGIN:VCARD"])
	{
	  vCard = [NGVCard parseSingleFromSource: content];
	  if (vCard)
	    fields = [self extractQuickFieldsFromVCard: vCard];
	  else
	    [self errorWithFormat: @"Could not parse VCARD content."];
	}
      else if ([upperContent hasPrefix: @"BEGIN:VLIST"])
	{
	  vList = [NGVList parseSingleFromSource: content];
	  if (vList)
	    fields = [self extractQuickFieldsFromVList: vList];
	  else
	    [self errorWithFormat: @"Could not parse VLIST content."];
	}
      else
	[self errorWithFormat: @"Content is unknown."];
    }
  else
    [self errorWithFormat: @"Content is empty."];

  return fields;
}

@end /* OCSContactFieldExtractor */
