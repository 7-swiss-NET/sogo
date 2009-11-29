/* LDAPSource.m - this file is part of SOGo
 *
 * Copyright (C) 2007-2009 Inverse inc.
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
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

#import <NGExtensions/NSObject+Logs.h>
#import <EOControl/EOControl.h>
#import <NGLdap/NGLdapConnection.h>
#import <NGLdap/NGLdapAttribute.h>
#import <NGLdap/NGLdapEntry.h>

#import "NSArray+Utilities.h"
#import "NSString+Utilities.h"
#import "SOGoDomainDefaults.h"
#import "SOGoSystemDefaults.h"

#import "LDAPSource.h"

#define SafeLDAPCriteria(x) [[x stringByReplacingString: @"\\" withString: @"\\\\"] \
                                stringByReplacingString: @"'" withString: @"\\'"]
static NSArray *commonSearchFields;

@implementation LDAPSource

+ (void) initialize
{
  if (!commonSearchFields)
    {
      commonSearchFields = [NSArray arrayWithObjects:
				      @"title",
				    @"company",
				    @"o",
				    @"displayname",
				    @"modifytimestamp",
				    @"mozillahomestate",
				    @"mozillahomeurl",
				    @"homeurl",
				    @"st",
				    @"region",
				    @"mozillacustom2",
				    @"custom2",
				    @"mozillahomecountryname",
				    @"description",
				    @"notes",
				    @"department",
				    @"departmentnumber",
				    @"ou",
				    @"orgunit",
				    @"mobile",
				    @"cellphone",
				    @"carphone",
				    @"mozillacustom1",
				    @"custom1",
				    @"mozillanickname",
				    @"xmozillanickname",
				    @"mozillaworkurl",
				    @"workurl",
				    @"fax",
				    @"facsimiletelephonenumber",
				    @"telephonenumber",
				    @"mozillahomestreet",
				    @"mozillasecondemail",
				    @"xmozillasecondemail",
				    @"mozillacustom4",
				    @"custom4",
				    @"nsaimid",
				    @"nscpaimscreenname",
				    @"street",
				    @"streetaddress",
				    @"postofficebox",
				    @"homephone",
				    @"cn",
				    @"commonname",
				    @"givenname",
				    @"mozillahomepostalcode",
				    @"mozillahomelocalityname",
				    @"mozillaworkstreet2",
				    @"mozillausehtmlmail",
				    @"xmozillausehtmlmail",
				    @"mozillahomestreet2",
				    @"postalcode",
				    @"zip",
				    @"c",
				    @"countryname",
				    @"pager",
				    @"pagerphone",
				    @"mail",
				    @"sn",
				    @"surname",
				    @"mozillacustom3",
				    @"custom3",
				    @"l",
				    @"locality",
				    @"birthyear",
				    @"serialnumber",
				    @"calfburl",
                                    @"proxyaddresses",
				    nil];	
      [commonSearchFields retain];
    }
}

+ (id) sourceFromUDSource: (NSDictionary *) udSource
                 inDomain: (NSString *) domain
{
  id newSource;

  newSource = [[self alloc] initFromUDSource: udSource
                                    inDomain: domain];
  [newSource autorelease];

  return newSource;
}

- (id) init
{
  if ((self = [super init]))
    {
      bindDN = nil;
      hostname = nil;
      port = 389;
      encryption = nil;
      password = nil;
      sourceID = nil;
      domain = nil;

      baseDN = nil;
      IDField = @"cn"; /* the first part of a user DN */
      CNField = @"cn";
      UIDField = @"uid";
      mailFields = [NSArray arrayWithObject: @"mail"];
      [mailFields retain];
      IMAPHostField = nil;
      bindFields = nil;
      _scope = @"sub";
      _filter = nil;

      searchAttributes = nil;
    }

  return self;
}

- (void) dealloc
{
  [bindDN release];
  [hostname release];
  [encryption release];
  [password release];
  [baseDN release];
  [IDField release];
  [CNField release];
  [UIDField release];
  [mailFields release];
  [IMAPHostField release];
  [bindFields release];
  [_filter release];
  [sourceID release];
  [modulesConstraints release];
  [_scope release];
  [searchAttributes release];
  [super dealloc];
}

- (id) initFromUDSource: (NSDictionary *) udSource
               inDomain: (NSString *) sourceDomain
{
  NSString *udDomainAttribute;
  SOGoDomainDefaults *dd;
  NSNumber *udQueryLimit, *udQueryTimeout;

  if ((self = [self init]))
    {
      ASSIGN (sourceID, [udSource objectForKey: @"id"]);

      [self setBindDN: [udSource objectForKey: @"bindDN"]
             password: [udSource objectForKey: @"bindPassword"]
             hostname: [udSource objectForKey: @"hostname"]
                 port: [udSource objectForKey: @"port"]
           encryption: [udSource objectForKey: @"encryption"]];
      [self setBaseDN: [udSource objectForKey: @"baseDN"]
              IDField: [udSource objectForKey: @"IDFieldName"]
              CNField: [udSource objectForKey: @"CNFieldName"]
             UIDField: [udSource objectForKey: @"UIDFieldName"]
           mailFields: [udSource objectForKey: @"MailFieldNames"]
	IMAPHostField: [udSource objectForKey: @"IMAPHostFieldName"]
	andBindFields: [udSource objectForKey: @"bindFields"]];

      udDomainAttribute = [udSource objectForKey: @"domainAttribute"];
      if ([sourceDomain length])
        {
          if ([udDomainAttribute length])
            {
              [self errorWithFormat: @"cannot define 'domainAttribute'"
                    @" for a domain-based source (%@)", sourceID];
              [self release];
              self = nil;
            }
          else
            {
              dd = [SOGoDomainDefaults defaultsForDomain: sourceDomain];
              ASSIGN (domain, sourceDomain);
            }
        }
      else
        {
          if ([udDomainAttribute length])
            ASSIGN (domainAttribute, udDomainAttribute);
          dd = [SOGoSystemDefaults sharedSystemDefaults];
        }

      contactInfoAttribute
        = [udSource objectForKey: @"SOGoLDAPContactInfoAttribute"];
      if (!contactInfoAttribute)
        contactInfoAttribute = [dd ldapContactInfoAttribute];
      [contactInfoAttribute retain];
      
      udQueryLimit = [udSource objectForKey: @"SOGoLDAPQueryLimit"];
      if (udQueryLimit)
        queryLimit = [udQueryLimit intValue];
      else
        queryLimit = [dd ldapQueryLimit];

      udQueryTimeout = [udSource objectForKey: @"SOGoLDAPQueryTimeout"];
      if (udQueryTimeout)
        queryTimeout = [udQueryTimeout intValue];
      else
        queryTimeout = [dd ldapQueryTimeout];

      ASSIGN (modulesConstraints,
              [udSource objectForKey: @"ModulesConstraints"]);
      ASSIGN (_filter, [udSource objectForKey: @"filter"]);
      ASSIGN (_scope, ([udSource objectForKey: @"scope"]
                       ? [udSource objectForKey: @"scope"]
                       : (id)@"sub"));
    }
  
  return self;
}

- (void) setBindDN: (NSString *) newBindDN
	  password: (NSString *) newBindPassword
	  hostname: (NSString *) newBindHostname
	      port: (NSString *) newBindPort
	encryption: (NSString *) newEncryption
{
  ASSIGN (bindDN, newBindDN);
  ASSIGN (encryption, [newEncryption uppercaseString]);
  if ([encryption isEqualToString: @"SSL"])
    port = 636;
  ASSIGN (hostname, newBindHostname);
  if (newBindPort)
    port = [newBindPort intValue];
  ASSIGN (password, newBindPassword);
}

- (void) setBaseDN: (NSString *) newBaseDN
	   IDField: (NSString *) newIDField
	   CNField: (NSString *) newCNField
	  UIDField: (NSString *) newUIDField
	mailFields: (NSArray *) newMailFields
     IMAPHostField: (NSString *) newIMAPHostField
     andBindFields: (NSString *) newBindFields
{
  ASSIGN (baseDN, [newBaseDN lowercaseString]);
  if (newIDField)
    ASSIGN (IDField, newIDField);
  if (newCNField)
    ASSIGN (CNField, newCNField);
  if (newUIDField)
    ASSIGN (UIDField, newUIDField);
  if (newIMAPHostField)
    ASSIGN (IMAPHostField, newIMAPHostField);
  if (newMailFields)
    ASSIGN (mailFields, newMailFields);
  if (newBindFields)
    ASSIGN (bindFields, newBindFields);
}

- (BOOL) _setupEncryption: (NGLdapConnection *) encryptedConn
{
  BOOL rc;

  if ([encryption isEqualToString: @"SSL"])
    rc = [encryptedConn useSSL];
  else if ([encryption isEqualToString: @"STARTTLS"])
    rc = [encryptedConn startTLS];
  else
    {
      [self errorWithFormat:
	      @"encryption scheme '%@' not supported:"
	    @" use 'SSL' or 'STARTTLS'", encryption];
      rc = NO;
    }

  return rc;
}

- (NGLdapConnection *) _ldapConnection
{
  NGLdapConnection *ldapConnection;

  NS_DURING
    {
      ldapConnection = [[NGLdapConnection alloc] initWithHostName: hostname
						 port: port];
      [ldapConnection autorelease];
      if (![encryption length] || [self _setupEncryption: ldapConnection])
	{
	  [ldapConnection bindWithMethod: @"simple"
			  binddn: bindDN
			  credentials: password];
	  if (queryLimit > 0)
	    [ldapConnection setQuerySizeLimit: queryLimit];
	  if (queryTimeout > 0)
	    [ldapConnection setQueryTimeLimit: queryTimeout];
	}
      else
	ldapConnection = nil;
    }
  NS_HANDLER
    {
      NSLog(@"Could not bind to the LDAP server %@ (%d) using the bind DN: %@", hostname, port, bindDN);
      ldapConnection = nil;
    }
  NS_ENDHANDLER;

  return ldapConnection;
}

- (NSString *) domain
{
  return domain;
}

/* user management */
- (EOQualifier *) _qualifierForBindFilter: (NSString *) uid
{
  NSMutableString *qs;
  NSString *escapedUid;
  NSEnumerator *fields;
  NSString *currentField;

  qs = [NSMutableString string];

  escapedUid = SafeLDAPCriteria (uid);

  fields = [[bindFields componentsSeparatedByString: @","] objectEnumerator];
  while ((currentField = [fields nextObject]))
    [qs appendFormat: @" OR (%@='%@')", currentField, escapedUid];

  if (_filter && [_filter length])
    [qs appendFormat: @" AND %@", _filter];

  [qs deleteCharactersInRange: NSMakeRange(0, 4)];

  return [EOQualifier qualifierWithQualifierFormat: qs];
}

- (NSString *) _fetchUserDNForLogin: (NSString *) loginToCheck
{
  NSEnumerator *entries;
  EOQualifier *qualifier;
  NSArray *attributes;
  NGLdapConnection *ldapConnection;
  NSString *userDN;

  ldapConnection = [self _ldapConnection];
  qualifier = [self _qualifierForBindFilter: loginToCheck];
  attributes = [NSArray arrayWithObject: @"dn"];

  if ([_scope caseInsensitiveCompare: @"BASE"] == NSOrderedSame)
    entries = [ldapConnection baseSearchAtBaseDN: baseDN
                                       qualifier: qualifier
                                      attributes: attributes];
  else if ([_scope caseInsensitiveCompare: @"ONE"] == NSOrderedSame)
    entries = [ldapConnection flatSearchAtBaseDN: baseDN
                                       qualifier: qualifier
                                      attributes: attributes];
  else
    entries = [ldapConnection deepSearchAtBaseDN: baseDN
                                       qualifier: qualifier
                                      attributes: attributes];

  userDN = [[entries nextObject] dn];

  return userDN;
}

- (BOOL) checkLogin: (NSString *) loginToCheck
	andPassword: (NSString *) passwordToCheck
{
  BOOL didBind;
  NSString *userDN;
  NGLdapConnection *bindConnection;

  didBind = NO;

  if ([loginToCheck length] > 0)
    {
      bindConnection = [[NGLdapConnection alloc] initWithHostName: hostname
						 port: port];
      if (![encryption length] || [self _setupEncryption: bindConnection])
	{
	  if (queryTimeout > 0)
	    [bindConnection setQueryTimeLimit: queryTimeout];
	  if (bindFields)
	    userDN = [self _fetchUserDNForLogin: loginToCheck];
	  else
	    userDN = [NSString stringWithFormat: @"%@=%@,%@",
			       IDField, loginToCheck, baseDN];
	  if (userDN)
	    {
	      NS_DURING
		didBind = [bindConnection bindWithMethod: @"simple"
					  binddn: userDN
					  credentials: passwordToCheck];
	      NS_HANDLER
                ;
              NS_ENDHANDLER
                ;
            }
	}
      [bindConnection release];
    }

  return didBind;
}

/* contact management */
- (EOQualifier *) _qualifierForFilter: (NSString *) filter
{
  NSString *mailFormat, *fieldFormat, *escapedFilter;
  EOQualifier *qualifier;
  NSMutableString *qs;

  escapedFilter = SafeLDAPCriteria (filter);
  if ([escapedFilter length] > 0)
    {
      fieldFormat = [NSString stringWithFormat: @"(%%@='%@*')", escapedFilter];
      mailFormat = [[mailFields stringsWithFormat: fieldFormat]
                     componentsJoinedByString: @" OR "];

      qs = [NSMutableString string];
      if ([escapedFilter isEqualToString: @"."])
        [qs appendFormat: @"(%@='*')", CNField];
      else
        [qs appendFormat: @"(%@='%@*') OR (sn='%@*') OR (displayName='%@*')"
	    @"OR %@ OR (telephoneNumber='*%@*')",
	    CNField, escapedFilter, escapedFilter, escapedFilter, mailFormat,
            escapedFilter];

      if (_filter && [_filter length])
	[qs appendFormat: @" AND %@", _filter];

      qualifier = [EOQualifier qualifierWithQualifierFormat: qs];
    }
  else
    qualifier = nil;

  return qualifier;
}

- (EOQualifier *) _qualifierForUIDFilter: (NSString *) uid
{
  NSString *mailFormat, *fieldFormat, *escapedUid, *currentField;
  NSEnumerator *bindFieldsEnum;
  NSMutableString *qs;

  escapedUid = SafeLDAPCriteria (uid);

  fieldFormat = [NSString stringWithFormat: @"(%%@='%@')", escapedUid];
  mailFormat = [[mailFields stringsWithFormat: fieldFormat]
		 componentsJoinedByString: @" OR "];
  qs = [NSMutableString stringWithFormat: @"(%@='%@') OR %@",
                        UIDField, escapedUid, mailFormat];
  if (bindFields)
    {
      bindFieldsEnum = [[bindFields componentsSeparatedByString: @","]
                         objectEnumerator];
      while ((currentField = [bindFieldsEnum nextObject]))
        [qs appendFormat: @" OR (%@='%@')", [currentField stringByTrimmingSpaces], escapedUid];
    }

  if (_filter && [_filter length])
    [qs appendFormat: @" AND %@", _filter];

  return [EOQualifier qualifierWithQualifierFormat: qs];
}

- (NSArray *) _constraintsFields
{
  NSMutableArray *fields;
  NSEnumerator *values;
  NSDictionary *currentConstraint;

  fields = [NSMutableArray array];
  values = [[modulesConstraints allValues] objectEnumerator];
  while ((currentConstraint = [values nextObject]))
    [fields addObjectsFromArray: [currentConstraint allKeys]];

  return fields;
}

- (NSArray *) _searchAttributes
{
  if (!searchAttributes)
    {
      searchAttributes = [NSMutableArray new];
      [searchAttributes addObject: @"objectClass"];
      if (CNField)
	[searchAttributes addObject: CNField];
      if (UIDField)
	[searchAttributes addObject: UIDField];
      [searchAttributes addObjectsFromArray: mailFields];
      [searchAttributes addObjectsFromArray: [self _constraintsFields]];
      [searchAttributes addObjectsFromArray: commonSearchFields];

      // Add SOGoLDAPContactInfoAttribute from user defaults
      if ([contactInfoAttribute length])
        [searchAttributes addObjectUniquely: contactInfoAttribute];

      if ([domainAttribute length])
        [searchAttributes addObjectUniquely: domainAttribute];

      // Add IMAP hostname from user defaults
      if ([IMAPHostField length])
        [searchAttributes addObjectUniquely: IMAPHostField];
    }

  return searchAttributes;
}

- (NSArray *) allEntryIDs
{
  NSEnumerator *entries;
  NGLdapEntry *currentEntry;
  NGLdapConnection *ldapConnection;
  NSString *value;
  NSArray *attributes;
  NSMutableArray *ids;

  ids = [NSMutableArray array];

  ldapConnection = [self _ldapConnection];
  attributes = [NSArray arrayWithObject: IDField];
  if ([_scope caseInsensitiveCompare: @"BASE"] == NSOrderedSame) 
    entries = [ldapConnection baseSearchAtBaseDN: baseDN
                                       qualifier: nil
                                      attributes: attributes];
  else if ([_scope caseInsensitiveCompare: @"ONE"] == NSOrderedSame) 
    entries = [ldapConnection flatSearchAtBaseDN: baseDN
                                       qualifier: nil
                                      attributes: attributes];
  else
    entries = [ldapConnection deepSearchAtBaseDN: baseDN
                                       qualifier: nil
                                      attributes: attributes];

  while ((currentEntry = [entries nextObject]))
    {
      value = [[currentEntry attributeWithName: IDField]
		    stringValueAtIndex: 0];
      if ([value length] > 0)
        [ids addObject: value];
    }

  return ids;
}

- (void) _fillEmailsOfEntry: (NGLdapEntry *) ldapEntry
	   intoContactEntry: (NSMutableDictionary *) contactEntry
{
  NSEnumerator *emailFields;
  NSString *currentFieldName, *ldapValue;
  NSMutableArray *emails;
  NSArray *allValues;

  emails = [[NSMutableArray alloc] init];
  emailFields = [mailFields objectEnumerator];
  while ((currentFieldName = [emailFields nextObject]))
    {
      allValues = [[ldapEntry attributeWithName: currentFieldName]
		    allStringValues];
      [emails addObjectsFromArray: allValues];
    }
  [contactEntry setObject: emails forKey: @"c_emails"];
  [emails release];

  if (IMAPHostField)
    {
      ldapValue = [[ldapEntry attributeWithName: IMAPHostField] stringValueAtIndex: 0];
      if ([ldapValue length] > 0)
	[contactEntry setObject: ldapValue forKey: @"c_imaphostname"];
    }
}

- (void) _fillConstraints: (NGLdapEntry *) ldapEntry
		forModule: (NSString *) module
	 intoContactEntry: (NSMutableDictionary *) contactEntry
{
  NSDictionary *constraints;
  NSEnumerator *matches;
  NSString *currentMatch, *currentValue, *ldapValue;
  BOOL result;

  result = YES;

  constraints = [modulesConstraints objectForKey: module];
  if (constraints)
    {
      matches = [[constraints allKeys] objectEnumerator];
      currentMatch = [matches nextObject];
      while (result && currentMatch)
	{
	  ldapValue = [[ldapEntry attributeWithName: currentMatch]
			stringValueAtIndex: 0];
	  currentValue = [constraints objectForKey: currentMatch];
	  if ([ldapValue caseInsensitiveMatches: currentValue])
	    currentMatch = [matches nextObject];
	  else
	    result = NO;
	}
    }

  [contactEntry setObject: [NSNumber numberWithBool: result]
		forKey: [NSString stringWithFormat: @"%@Access", module]];
}

- (NSDictionary *) _convertLDAPEntryToContact: (NGLdapEntry *) ldapEntry
{
  NSMutableDictionary *contactEntry;
  NSEnumerator *attributes;
  NSString *currentAttribute, *value;
  NSMutableArray *classes;
  id o;

  contactEntry = [NSMutableDictionary dictionary];
  [contactEntry setObject: [ldapEntry dn] forKey: @"dn"];
  attributes = [[self _searchAttributes] objectEnumerator];

  // We get our objectClass attribute values. We lowercase
  // everything for ease of search after.
  o = [ldapEntry objectClasses];
  classes = nil;

  if (o)
    {
      int i, c;

      classes = [NSMutableArray arrayWithArray: o];
      c = [classes count];
      for (i = 0; i < c; i++)
	[classes replaceObjectAtIndex: i
		 withObject: [[classes objectAtIndex: i] lowercaseString]];
    }

  if (classes)
    {
      [contactEntry setObject: classes
		       forKey: @"objectclasses"];

      // We check if our entry is a group. If so, we set the
      // 'isGroup' custom attribute.
      if ([classes containsObject: @"group"] ||
	  [classes containsObject: @"groupofnames"] ||
	  [classes containsObject: @"groupofuniquenames"] ||
	  [classes containsObject: @"posixgroup"])
	{
	  [contactEntry setObject: [NSNumber numberWithInt: 1]
			   forKey: @"isGroup"];
	}
    }

  while ((currentAttribute = [attributes nextObject]))
    {
      value = [[ldapEntry attributeWithName: currentAttribute]
		stringValueAtIndex: 0];

      // It's important here to set our attributes' key in lowercase.
      if (value)
	[contactEntry setObject: value forKey: [currentAttribute lowercaseString]];
    }

  value = [[ldapEntry attributeWithName: IDField] stringValueAtIndex: 0];
  if (!value)
    value = @"";
  [contactEntry setObject: value forKey: @"c_name"];
  value = [[ldapEntry attributeWithName: UIDField] stringValueAtIndex: 0];
  if (!value)
    value = @"";
//  else
//    {
//      Eventually, we could check at this point if the entry is a group
//      and prefix the UID with a "@"
//    }
  [contactEntry setObject: value forKey: @"c_uid"];
  value = [[ldapEntry attributeWithName: CNField] stringValueAtIndex: 0];
  if (!value)
    value = @"";
  [contactEntry setObject: value forKey: @"c_cn"];

  if (contactInfoAttribute)
    {
      value = [[ldapEntry attributeWithName: contactInfoAttribute]
                stringValueAtIndex: 0];
      if (!value)
        value = @"";
    }
  else
    value = @"";
  [contactEntry setObject: value forKey: @"c_info"];

  if (domainAttribute)
    {
      value = [[ldapEntry attributeWithName: domainAttribute]
                stringValueAtIndex: 0];
      if (!value)
        value = @"";
    }
  else if (domain)
    value = domain;
  else
    value = @"";
  [contactEntry setObject: value forKey: @"c_domain"];

  [self _fillEmailsOfEntry: ldapEntry intoContactEntry: contactEntry];
  [self _fillConstraints: ldapEntry forModule: @"Calendar"
	intoContactEntry: (NSMutableDictionary *) contactEntry];
  [self _fillConstraints: ldapEntry forModule: @"Mail"
	intoContactEntry: (NSMutableDictionary *) contactEntry];

  return contactEntry;
}

- (NSArray *) fetchContactsMatching: (NSString *) match
{
  NGLdapConnection *ldapConnection;
  NGLdapEntry *currentEntry;
  NSEnumerator *entries;
  NSMutableArray *contacts;
  EOQualifier *qualifier;
  NSArray *attributes;

  contacts = [NSMutableArray array];

  if ([match length] > 0)
    {
      ldapConnection = [self _ldapConnection];
      qualifier = [self _qualifierForFilter: match];
      attributes = [self _searchAttributes];
	  
      if ([_scope caseInsensitiveCompare: @"BASE"] == NSOrderedSame)
        entries = [ldapConnection baseSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else if ([_scope caseInsensitiveCompare: @"ONE"] == NSOrderedSame)
        entries = [ldapConnection flatSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else /* we do it like before */ 
        entries = [ldapConnection deepSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      while ((currentEntry = [entries nextObject]))
        [contacts addObject:
                    [self _convertLDAPEntryToContact: currentEntry]];
    }

  return contacts;
}

- (NSDictionary *) lookupContactEntry: (NSString *) theID
{
  NGLdapEntry *ldapEntry;
  NGLdapConnection *ldapConnection;
  NSEnumerator *entries;
  EOQualifier *qualifier;
  NSArray *attributes;
  NSString *s;
  NSDictionary *contactEntry;

  contactEntry = nil;

  if ([theID length] > 0)
    {
      ldapConnection = [self _ldapConnection];
      s = [NSString stringWithFormat: @"(%@='%@')",
                    IDField, SafeLDAPCriteria (theID)];
      qualifier = [EOQualifier qualifierWithQualifierFormat: s];
      attributes = [self _searchAttributes];

      if ([_scope caseInsensitiveCompare: @"BASE"] == NSOrderedSame)
        entries = [ldapConnection baseSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else if ([_scope caseInsensitiveCompare: @"ONE"] == NSOrderedSame)
        entries = [ldapConnection flatSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else
        entries = [ldapConnection deepSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];

      ldapEntry = [entries nextObject];
      if (ldapEntry)
        contactEntry = [self _convertLDAPEntryToContact: ldapEntry];
    }

  return contactEntry;
}

- (NSDictionary *) lookupContactEntryWithUIDorEmail: (NSString *) uid
{
  NGLdapConnection *ldapConnection;
  NGLdapEntry *ldapEntry;
  NSEnumerator *entries;
  EOQualifier *qualifier;
  NSArray *attributes;
  NSDictionary *contactEntry;

  contactEntry = nil;

  if ([uid length] > 0)
    {
      ldapConnection = [self _ldapConnection];
      qualifier = [self _qualifierForUIDFilter: uid];
      attributes = [self _searchAttributes];

      if ([_scope caseInsensitiveCompare: @"BASE"] == NSOrderedSame)
        entries = [ldapConnection baseSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else if ([_scope caseInsensitiveCompare: @"ONE"] == NSOrderedSame)
        entries = [ldapConnection flatSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else
        entries = [ldapConnection deepSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
	  
      ldapEntry = [entries nextObject];
      if (ldapEntry)
        contactEntry = [self _convertLDAPEntryToContact: ldapEntry];
    }

  return contactEntry;
}

- (NSString *) lookupLoginByDN: (NSString *) theDN
{
  NGLdapConnection *ldapConnection;
  NGLdapEntry *entry;
  NSString *login;
  
  login = nil;

  ldapConnection = [self _ldapConnection];
  entry = [ldapConnection entryAtDN: theDN
                         attributes: [NSArray arrayWithObject: UIDField]];
  if (entry)
    login = [[entry attributeWithName: UIDField] stringValueAtIndex: 0];

  return login;
}

- (NGLdapEntry *) lookupGroupEntryByUID: (NSString *) theUID
{
  return [self lookupGroupEntryByAttribute: UIDField
	       andValue: theUID];
}

- (NGLdapEntry *) lookupGroupEntryByEmail: (NSString *) theEmail
{
#warning We should support MailFieldNames
  return [self lookupGroupEntryByAttribute: @"mail"
	       andValue: theEmail];
}

// This method should accept multiple attributes
- (NGLdapEntry *) lookupGroupEntryByAttribute: (NSString *) theAttribute 
				     andValue: (NSString *) theValue
{
  NSMutableArray *attributes;
  NSEnumerator *entries;
  EOQualifier *qualifier;
  NSString *s;
  NGLdapConnection *ldapConnection;
  NGLdapEntry *ldapEntry;

  if ([theValue length] > 0)
    {
      ldapConnection = [self _ldapConnection];
	  
      s = [NSString stringWithFormat: @"(%@='%@')",
                    theAttribute, SafeLDAPCriteria (theValue)];
      qualifier = [EOQualifier qualifierWithQualifierFormat: s];

      // We look for additional attributes - the ones related to group
      // membership
      attributes = [NSMutableArray arrayWithArray: [self _searchAttributes]];
      [attributes addObject: @"member"];
      [attributes addObject: @"uniqueMember"];
      [attributes addObject: @"memberUid"];
      [attributes addObject: @"memberOf"];

      if ([_scope caseInsensitiveCompare: @"BASE"] == NSOrderedSame)
        entries = [ldapConnection baseSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else if ([_scope caseInsensitiveCompare: @"ONE"] == NSOrderedSame)
        entries = [ldapConnection flatSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      else
        entries = [ldapConnection deepSearchAtBaseDN: baseDN
                                           qualifier: qualifier
                                          attributes: attributes];
      
      ldapEntry = [entries nextObject];
    }
  else
    ldapEntry = nil;

  return ldapEntry;
}

- (NSString *) sourceID
{
  return sourceID;
}

- (NSString *) baseDN
{
  return baseDN;
}

@end
