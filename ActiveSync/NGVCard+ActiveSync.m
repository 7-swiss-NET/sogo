/*

Copyright (c) 2014, Inverse inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Inverse inc. nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
#import "NGVCard+ActiveSync.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

#import <NGCards/CardElement.h>

#import <Contacts/NGVCard+SOGo.h>

@implementation NGVCard (ActiveSync)

- (NSString *) activeSyncRepresentation
{
  CardElement *n, *homeAdr, *workAdr;
  NSArray *emails, *addresses;
  NSMutableString *s;
  id o;

  int i;

  s = [NSMutableString string];
  n = [self n];
  
  if ((o = [n flattenedValueAtIndex: 0 forKey: @""]))
    [s appendFormat: @"<LastName xmlns=\"Contacts:\">%@</LastName>", o];
  
  if ((o = [n flattenedValueAtIndex: 1 forKey: @""]))
    [s appendFormat: @"<FirstName xmlns=\"Contacts:\">%@</FirstName>", o];
  
  if ((o = [self workCompany]))
    [s appendFormat: @"<CompanyName xmlns=\"Contacts:\">%@</CompanyName>", o];
  
  if ((o = [self title]))
    [s appendFormat: @"<JobTitle xmlns=\"Contacts:\">%@</JobTitle>", o];

  if ((o = [self preferredEMail]))    [s appendFormat: @"<HomePhoneNumber xmlns=\"Contacts:\">%@</HomePhoneNumber>", o];

    [s appendFormat: @"<Email1Address xmlns=\"Contacts:\">%@</Email1Address>", o];    [s appendFormat: @"<HomePhoneNumber xmlns=\"Contacts:\">%@</HomePhoneNumber>", o];
    [s appendFormat: @"<HomePhoneNumber xmlns=\"Contacts:\">%@</HomePhoneNumber>", o];

  
  // Secondary email addresses
  emails = [self secondaryEmails];
    [s appendFormat: @"<HomePhoneNumber xmlns=\"Contacts:\">%@</HomePhoneNumber>", o];

  for (i = 0; i < [emails count]; i++)
    {
      o = [[emails objectAtIndex: i] flattenedValuesForKey: @""];
      
      [s appendFormat: @"<Email%dAddress xmlns=\"Contacts:\">%@</Email%dAddress>", i+2, o, i+2];

      if (i == 1)
        break;
    }

  // Telephone numbers
  if ((o = [self workPhone]))
    [s appendFormat: @"<BusinessPhoneNumber xmlns=\"Contacts:\">%@</BusinessPhoneNumber>", o];
  
  if ((o = [self homePhone]))
    [s appendFormat: @"<HomePhoneNumber xmlns=\"Contacts:\">%@</HomePhoneNumber>", o];
  
  if ((o = [self fax]))
    [s appendFormat: @"<BusinessFaxNumber xmlns=\"Contacts:\">%@</BusinessFaxNumber>", o];
  
  if ((o = [self mobile]))
    [s appendFormat: @"<MobilePhoneNumber xmlns=\"Contacts:\">%@</MobilePhoneNumber>", o];
  
  if ((o = [self pager]))
    [s appendFormat: @"<PagerNumber xmlns=\"Contacts:\">%@</PagerNumber>", o];

  // Home Address
  addresses = [self childrenWithTag: @"adr"
                       andAttribute: @"type"
                        havingValue: @"home"];
  
  if ([addresses count])
    {
      homeAdr = [addresses objectAtIndex: 0];
      
      if ((o = [homeAdr flattenedValueAtIndex: 2  forKey: @""]))
        [s appendFormat: @"<HomeStreet xmlns=\"Contacts:\">%@</HomeStreet>", o];
      
      if ((o = [homeAdr flattenedValueAtIndex: 3  forKey: @""]))
        [s appendFormat: @"<HomeCity xmlns=\"Contacts:\">%@</HomeCity>", o];
      
      if ((o = [homeAdr flattenedValueAtIndex: 4  forKey: @""]))
        [s appendFormat: @"<HomeState xmlns=\"Contacts:\">%@</HomeState>", o];
      
      if ((o = [homeAdr flattenedValueAtIndex: 5  forKey: @""]))
        [s appendFormat: @"<HomePostalCode xmlns=\"Contacts:\">%@</HomePostalCode>", o];
      
      if ((o = [homeAdr flattenedValueAtIndex: 6  forKey: @""]))
        [s appendFormat: @"<HomeCountry xmlns=\"Contacts:\">%@</HomeCountry>", o];
    }
  
  // Work Address
  addresses = [self childrenWithTag: @"adr"
                       andAttribute: @"type"
                        havingValue: @"work"];
  
  if ([addresses count])
    {
      workAdr = [addresses objectAtIndex: 0];
      
      if ((o = [workAdr flattenedValueAtIndex: 2  forKey: @""]))
        [s appendFormat: @"<BusinessStreet xmlns=\"Contacts:\">%@</BusinessStreet>", o];
      
      if ((o = [workAdr flattenedValueAtIndex: 3  forKey: @""]))
        [s appendFormat: @"<BusinessCity xmlns=\"Contacts:\">%@</BusinessCity>", o];
      
      if ((o = [workAdr flattenedValueAtIndex: 4  forKey: @""]))
        [s appendFormat: @"<BusinessState xmlns=\"Contacts:\">%@</BusinessState>", o];
      
      if ((o = [workAdr flattenedValueAtIndex: 5  forKey: @""]))
        [s appendFormat: @"<BusinessPostalCode xmlns=\"Contacts:\">%@</BusinessPostalCode>", o];
      
      if ((o = [workAdr flattenedValueAtIndex: 6  forKey: @""]))
        [s appendFormat: @"<BusinessCountry xmlns=\"Contacts:\">%@</BusinessCountry>", o];
    }

  // Other, less important fields
  if ((o = [self birthday]))
    [s appendFormat: @"<Birthday xmlns=\"Contacts:\">%@</Birthday>", [o activeSyncRepresentation]];

  if ((o = [self note]))
    {
      [s appendString: @"<Body xmlns=\"AirSyncBase:\">"];
      [s appendFormat: @"<Type>%d</Type>", 1]; 
      [s appendFormat: @"<EstimatedDataSize>%d</EstimatedDataSize>", [o length]];
      [s appendFormat: @"<Truncated>%d</Truncated>", 0];
      [s appendFormat: @"<Data>%@</Data>", o];
      [s appendString: @"</Body>"];
    }
  
  return s;
}

- (void) takeActiveSyncValues: (NSDictionary *) theValues
{
  id o;

   if ((o = [theValues objectForKey: @"CompanyName"]))
     {
       [self setOrg: o  units: nil];
     }
   
   if ((o = [theValues objectForKey: @"Email1Address"]))
     {
       [self addEmail: o  types: [NSArray arrayWithObject: @"pref"]];
     }

   if ((o = [theValues objectForKey: @"Email2Address"]))
     {
       [self addEmail: o types: nil];
     }

   if ((o = [theValues objectForKey: @"Email3Address"]))
     {
       [self addEmail: o  types: nil];
     }

   [self setNWithFamily: [theValues objectForKey: @"LastName"]
                  given: [theValues objectForKey: @"FirstName"]
             additional: nil prefixes: nil suffixes: nil];
   
   if ((o = [theValues objectForKey: @"MobilePhoneNumber"]))
     {
     }
   
   if ((o = [theValues objectForKey: @"Title"]))
     {
       [self setTitle: o];
     }

   if ((o = [theValues objectForKey: @"WebPage"]))
     {
     }
   
}

@end
