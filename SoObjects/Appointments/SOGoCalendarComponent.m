/* SOGoCalendarComponent.m - this file is part of SOGo
 *
 * Copyright (C) 2006 Inverse groupe conseil
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

#import <Foundation/NSString.h>

#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalPerson.h>
#import <NGCards/iCalRepeatableEntityObject.h>
#import <NGMime/NGMime.h>
#import <NGMail/NGMail.h>
#import <NGMail/NGSendMail.h>

#import <SoObjects/SOGo/LDAPUserManager.h>
#import <SoObjects/SOGo/SOGoPermissions.h>
#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/Appointments/SOGoAppointmentFolder.h>

#import "common.h"

#import "SOGoAptMailNotification.h"
#import "SOGoCalendarComponent.h"

static NSString *mailTemplateDefaultLanguage = nil;
static BOOL sendEMailNotifications = NO;

@implementation SOGoCalendarComponent

+ (void) initialize
{
  NSUserDefaults      *ud;
  static BOOL         didInit = NO;
  
  if (!didInit)
    {
      didInit = YES;
  
      ud = [NSUserDefaults standardUserDefaults];
      mailTemplateDefaultLanguage = [[ud stringForKey:@"SOGoDefaultLanguage"]
                                      retain];
      if (!mailTemplateDefaultLanguage)
        mailTemplateDefaultLanguage = @"French";

      sendEMailNotifications
        = [ud boolForKey: @"SOGoAppointmentSendEMailNotifications"];
    }
}

- (id) init
{
  if ((self = [super init]))
    {
      calendar = nil;
      calContent = nil;
      isNew = NO;
    }

  return self;
}

- (void) dealloc
{
  if (calendar)
    [calendar release];
  if (calContent)
    [calContent release];
  [super dealloc];
}

- (NSString *) davContentType
{
  return @"text/calendar";
}

- (NSString *) componentTag
{
  [self subclassResponsibility: _cmd];

  return nil;
}

- (void) _filterComponent: (iCalEntityObject *) component
{
  [component setSummary: @""];
  [component setComment: @""];
  [component setUserComment: @""];
  [component setLocation: @""];
  [component setCategories: @""];
  [component setUrl: @""];
  [component removeAllAttendees];
  [component removeAllAlarms];
}

- (NSString *) contentAsString
{
  NSString *tmpContent, *email, *uid, *role;
  iCalCalendar *tmpCalendar;
  iCalRepeatableEntityObject *tmpComponent;

  if (!calContent)
    {
      tmpContent = [super contentAsString];
      calContent = tmpContent;
      uid = [[context activeUser] login];
      if (![[self ownerInContext: context] isEqualToString: uid]
	  && [tmpContent length] > 0)
        {
          tmpCalendar = [iCalCalendar parseSingleFromSource: tmpContent];
          tmpComponent = (iCalRepeatableEntityObject *)
	    [tmpCalendar firstChildWithTag: [self componentTag]];
	  email = [[context activeUser] primaryEmail];
	  if (!([tmpComponent isOrganizer: email]
		|| [tmpComponent isParticipant: email]))
	    {
	      role = [container roleForComponentsWithAccessClass: [tmpComponent symbolicAccessClass]
				forUser: uid];
	      if ([role length] > 0)
		{
		  if ([role isEqualToString: SOGoCalendarPerm_ViewDAndT])
		    {
		      //             content = tmpContent;
		      [self _filterComponent: tmpComponent];
		      calContent = [tmpCalendar versitString];
		    }
		}
	      else
		calContent = nil;
            }
        }

      [calContent retain];
    }

  return calContent;
}

- (NSException *) saveContentString: (NSString *) contentString
                        baseVersion: (unsigned int) baseVersion
{
  NSException *result;

  result = [super saveContentString: contentString
                  baseVersion: baseVersion];
  if (!result && calContent)
    {
      [calContent release];
      calContent = nil;
    }

  return result;
}

- (iCalCalendar *) calendar: (BOOL) create
{
  NSString *iCalString, *componentTag;
  CardGroup *newComponent;

  if (!calendar)
    {
      iCalString = [self contentAsString];
      if ([iCalString length] > 0)
        calendar = [iCalCalendar parseSingleFromSource: iCalString];
      else
        {
          if (create)
            {
              calendar = [iCalCalendar groupWithTag: @"vcalendar"];
              [calendar setVersion: @"2.0"];
              [calendar setProdID: @"-//Inverse groupe conseil//SOGo 0.9//EN"];
              componentTag = [[self componentTag] uppercaseString];
              newComponent = [[calendar classForTag: componentTag]
                               groupWithTag: componentTag];
              [calendar addChild: newComponent];
	      isNew = YES;
            }
        }
      if (calendar)
        [calendar retain];
    }

  return calendar;
}

- (iCalRepeatableEntityObject *) component: (BOOL) create
{
  return
    (iCalRepeatableEntityObject *) [[self calendar: create]
				     firstChildWithTag: [self componentTag]];
}

- (BOOL) isNew
{
  return isNew;
}

/* raw saving */

- (NSException *) primarySaveContentString: (NSString *) _iCalString
{
  return [super saveContentString: _iCalString];
}

- (NSException *) primaryDelete
{
  return [super delete];
}

- (NSException *) deleteWithBaseSequence: (int) a
{
  [self subclassResponsibility: _cmd];

  return nil;
}

- (NSException *) delete
{
  return [self deleteWithBaseSequence:0];
}

/* EMail Notifications */
- (NSString *) homePageURLForPerson: (iCalPerson *) _person
{
  NSString *baseURL;
  NSString *uid;
  NSArray *traversalObjects;

  /* generate URL from traversal stack */
  traversalObjects = [context objectTraversalStack];
  if ([traversalObjects count] > 0)
    baseURL = [[traversalObjects objectAtIndex:0] baseURLInContext: context];
  else
    {
      baseURL = @"http://localhost/";
      [self warnWithFormat:@"Unable to create baseURL from context!"];
    }
  uid = [[LDAPUserManager sharedUserManager]
          getUIDForEmail: [_person rfc822Email]];

  return ((uid)
          ? [NSString stringWithFormat:@"%@%@", baseURL, uid]
          : nil);
}

- (NSException *) changeParticipationStatus: (NSString *) _status
{
  iCalRepeatableEntityObject *component;
  iCalPerson *p;
  NSString *newContent;
  NSException *ex;
  NSString *myEMail;
  
  ex = nil;

  component = [self component: NO];
  if (component)
    {
      myEMail = [[context activeUser] primaryEmail];
      p = [component findParticipantWithEmail: myEMail];
      if (p)
        {
	  // TODO: send iMIP reply mails?
          [p setPartStat: _status];
          newContent = [[component parent] versitString];
          if (newContent)
            {
              ex = [self saveContentString:newContent];
              if (ex)
                // TODO: why is the exception wrapped?
                /* Server Error */
                ex = [NSException exceptionWithHTTPStatus: 500
                                  reason: [ex reason]];
            }
          else
            ex
              = [NSException exceptionWithHTTPStatus: 500 /* Server Error */
                             reason: @"Could not generate iCalendar data ..."];
        }
      else
        ex = [NSException exceptionWithHTTPStatus: 404 /* Not Found */
                          reason: @"user does not participate in this "
                          @"calendar component"];
    }
  else
    ex = [NSException exceptionWithHTTPStatus: 500 /* Server Error */
                      reason: @"unable to parse component record"];

  return ex;
}

- (BOOL) sendEMailNotifications
{
  return sendEMailNotifications;
}

- (NSTimeZone *) timeZoneForUser: (NSString *) email
{
  NSString *uid;

  uid = [[LDAPUserManager sharedUserManager] getUIDForEmail: email];

  return [[SOGoUser userWithLogin: uid andRoles: nil] timeZone];
}

- (void) sendEMailUsingTemplateNamed: (NSString *) _pageName
                        forOldObject: (iCalRepeatableEntityObject *) _oldObject
                        andNewObject: (iCalRepeatableEntityObject *) _newObject
                         toAttendees: (NSArray *) _attendees
{
  NSString *pageName;
  iCalPerson *organizer;
  NSString *cn, *email, *sender, *iCalString;
  NGSendMail *sendmail;
  WOApplication *app;
  unsigned i, count;
  iCalPerson *attendee;
  NSString *recipient;
  SOGoAptMailNotification *p;
  NSString *subject, *text, *header;
  NGMutableHashMap *headerMap;
  NGMimeMessage *msg;
  NGMimeBodyPart *bodyPart;
  NGMimeMultipartBody *body;

  if ([_attendees count])
    {
      /* sender */

      organizer = [_newObject organizer];
      cn = [organizer cnWithoutQuotes];
      if (cn)
        sender = [NSString stringWithFormat:@"%@ <%@>",
                           cn,
                           [organizer rfc822Email]];
      else
        sender = [organizer rfc822Email];

      /* generate iCalString once */
      iCalString = [[_newObject parent] versitString];
  
      /* get sendmail object */
      sendmail = [NGSendMail sharedSendMail];

      /* get WOApplication instance */
      app = [WOApplication application];

      /* generate dynamic message content */

      count = [_attendees count];
      for (i = 0; i < count; i++)
        {
          attendee = [_attendees objectAtIndex:i];

          /* construct recipient */
          cn = [attendee cn];
	  email = [attendee rfc822Email];
          if (cn)
            recipient = [NSString stringWithFormat: @"%@ <%@>",
                                  cn, email];
          else
            recipient = email;

          /* create page name */
          // TODO: select user's default language?
          pageName = [NSString stringWithFormat: @"SOGoAptMail%@%@",
                               mailTemplateDefaultLanguage,
                               _pageName];
          /* construct message content */
          p = [app pageWithName: pageName inContext: context];
          [p setNewApt: _newObject];
          [p setOldApt: _oldObject];
          [p setHomePageURL: [self homePageURLForPerson: attendee]];
          [p setViewTZ: [self timeZoneForUser: email]];
          subject = [p getSubject];
          text = [p getBody];

          /* construct message */
          headerMap = [NGMutableHashMap hashMapWithCapacity: 5];
          
          /* NOTE: multipart/alternative seems like the correct choice but
           * unfortunately Thunderbird doesn't offer the rich content alternative
           * at all. Mail.app shows the rich content alternative _only_
           * so we'll stick with multipart/mixed for the time being.
           */
          [headerMap setObject: @"multipart/mixed" forKey: @"content-type"];
          [headerMap setObject: sender forKey: @"From"];
          [headerMap setObject: recipient forKey: @"To"];
          [headerMap setObject: [NSCalendarDate date] forKey: @"date"];
          [headerMap setObject: subject forKey: @"Subject"];
          msg = [NGMimeMessage messageWithHeader: headerMap];

          /* multipart body */
          body = [[NGMimeMultipartBody alloc] initWithPart: msg];
    
          /* text part */
          headerMap = [NGMutableHashMap hashMapWithCapacity: 1];
          [headerMap setObject: @"text/plain; charset=utf-8"
                     forKey: @"content-type"];
          bodyPart = [NGMimeBodyPart bodyPartWithHeader: headerMap];
          [bodyPart setBody: [text dataUsingEncoding: NSUTF8StringEncoding]];

          /* attach text part to multipart body */
          [body addBodyPart: bodyPart];
    
          /* calendar part */
          header = [NSString stringWithFormat: @"text/calendar; method=%@;"
                             @" charset=utf-8",
                             [(iCalCalendar *) [_newObject parent] method]];
          headerMap = [NGMutableHashMap hashMapWithCapacity: 1];
          [headerMap setObject:header forKey: @"content-type"];
          bodyPart = [NGMimeBodyPart bodyPartWithHeader: headerMap];
          [bodyPart setBody: [iCalString dataUsingEncoding: NSUTF8StringEncoding]];

          /* attach calendar part to multipart body */
          [body addBodyPart: bodyPart];
    
          /* attach multipart body to message */
          [msg setBody: body];
          [body release];

          /* send the damn thing */
          [sendmail sendMimePart: msg
                    toRecipients: [NSArray arrayWithObject: email]
                    sender: [organizer rfc822Email]];
        }
    }
}

- (BOOL) isOrganizerOrOwner: (SOGoUser *) user
{
  BOOL isOrganizerOrOwner;
  iCalRepeatableEntityObject *component;
  NSString *organizerEmail;

  component = [self component: NO];
  organizerEmail = [[component organizer] rfc822Email];
  if (component && [organizerEmail length] > 0)
    isOrganizerOrOwner = [user hasEmail: organizerEmail];
  else
    isOrganizerOrOwner
      = [[container ownerInContext: context] isEqualToString: [user login]];

  return isOrganizerOrOwner;
}

- (iCalPerson *) participant: (SOGoUser *) user
{
  iCalPerson *participant, *currentParticipant;
  iCalEntityObject *component;
  NSEnumerator *participants;

  participant = nil;
  component = [self component: NO];
  if (component)
    {
      participants = [[component participants] objectEnumerator];
      currentParticipant = [participants nextObject];
      while (currentParticipant && !participant)
	if ([user hasEmail: [currentParticipant rfc822Email]])
	  participant = currentParticipant;
	else
	  currentParticipant = [participants nextObject];
    }

  return participant;
}

- (iCalPerson *) iCalPersonWithUID: (NSString *) uid
{
  iCalPerson *person;
  LDAPUserManager *um;
  NSDictionary *contactInfos;

  um = [LDAPUserManager sharedUserManager];
  contactInfos = [um contactInfosForUserWithUIDorEmail: uid];

  person = [iCalPerson new];
  [person autorelease];
  [person setCn: [contactInfos objectForKey: @"cn"]];
  [person setEmail: [contactInfos objectForKey: @"c_email"]];

  return person;
}

- (NSString *) getUIDForICalPerson: (iCalPerson *) person
{
  LDAPUserManager *um;

  um = [LDAPUserManager sharedUserManager];

  return [um getUIDForEmail: [person rfc822Email]];
}

- (NSArray *) getUIDsForICalPersons: (NSArray *) iCalPersons
{
  iCalPerson *currentPerson;
  NSEnumerator *persons;
  NSMutableArray *uids;
  NSString *email;
  LDAPUserManager *um;

  uids = [NSMutableArray array];

  um = [LDAPUserManager sharedUserManager];
  persons = [iCalPersons objectEnumerator];
  currentPerson = [persons nextObject];
  while (currentPerson)
    {
      email = [currentPerson rfc822Email];
      [uids addObject: [um getUIDForEmail: email]];
      currentPerson = [persons nextObject];
    }

  return uids;
}

- (NSArray *) aclsForUser: (NSString *) uid
{
  NSMutableArray *roles;
  NSArray *superAcls;
  iCalRepeatableEntityObject *component;
  NSString *email, *accessRole;

  roles = [NSMutableArray array];
  component = [self component: NO];
  if (component)
    {
      email = [[LDAPUserManager sharedUserManager] getEmailForUID: uid];
      if ([component isOrganizer: email])
	[roles addObject: SOGoCalendarRole_Organizer];
      if ([component isParticipant: email])
	[roles addObject: SOGoCalendarRole_Participant];
      accessRole = [container roleForComponentsWithAccessClass:
				[component symbolicAccessClass]
			      forUser: uid];
      if ([accessRole length] > 0)
	[roles addObject: accessRole];
    }

  superAcls = [super aclsForUser: uid];
  if ([superAcls count] > 0)
    [roles addObjectsFromArray: superAcls];
  if ([roles containsObject: SOGoRole_ObjectCreator])
    [roles addObject: SOGoCalendarRole_ComponentModifier];

  return roles;
}

@end
