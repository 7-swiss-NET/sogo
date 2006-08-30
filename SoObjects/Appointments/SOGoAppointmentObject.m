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

#include "SOGoAppointmentObject.h"
#include <SOGo/AgenorUserManager.h>
#include <SOGo/SOGoAppointment.h>
#include <SaxObjC/SaxObjC.h>
#include <NGiCal/NGiCal.h>
#include <NGMime/NGMime.h>
#include <NGMail/NGMail.h>
#include <NGMail/NGSendMail.h>
#include "SOGoAptMailNotification.h"
#include "common.h"

@interface NSMutableArray (iCalPersonConvenience)
- (void)removePerson:(iCalPerson *)_person;
@end

@interface SOGoAppointmentObject (PrivateAPI)
- (NSString *)homePageURLForPerson:(iCalPerson *)_person;
- (NSTimeZone *)viewTimeZoneForPerson:(iCalPerson *)_person;
  
- (void)sendEMailUsingTemplateNamed:(NSString *)_pageName
  forOldAppointment:(SOGoAppointment *)_newApt
  andNewAppointment:(SOGoAppointment *)_oldApt
  toAttendees:(NSArray *)_attendees;

- (void)sendInvitationEMailForAppointment:(SOGoAppointment *)_apt
  toAttendees:(NSArray *)_attendees;
- (void)sendAppointmentUpdateEMailForOldAppointment:(SOGoAppointment *)_oldApt
  newAppointment:(SOGoAppointment *)_newApt
  toAttendees:(NSArray *)_attendees;
- (void)sendAttendeeRemovalEMailForAppointment:(SOGoAppointment *)_apt
  toAttendees:(NSArray *)_attendees;
- (void)sendAppointmentDeletionEMailForAppointment:(SOGoAppointment *)_apt
  toAttendees:(NSArray *)_attendees;
@end

@implementation SOGoAppointmentObject

static id<NSObject,SaxXMLReader> parser  = nil;
static SaxObjectDecoder          *sax    = nil;
static NGLogger                  *logger = nil;
static NSTimeZone                *EST    = nil;
static NSString                  *mailTemplateDefaultLanguage = nil;

+ (void)initialize {
  NSUserDefaults      *ud;
  NGLoggerManager     *lm;
  SaxXMLReaderFactory *factory;
  static BOOL         didInit = NO;
  
  if (didInit) return;
  didInit = YES;
  
  lm      = [NGLoggerManager defaultLoggerManager];
  logger  = [lm loggerForClass:self];
  
  factory = [SaxXMLReaderFactory standardXMLReaderFactory];
  parser  = [[factory createXMLReaderForMimeType:@"text/calendar"]
    retain];
  if (parser == nil)
    [logger fatalWithFormat:@"did not find a parser for text/calendar!"];
  sax = [[SaxObjectDecoder alloc] initWithMappingNamed:@"NGiCal"];
  if (sax == nil)
    [logger fatalWithFormat:@"could not create the iCal SAX handler!"];
  
  [parser setContentHandler:sax];
  [parser setErrorHandler:sax];

  EST = [[NSTimeZone timeZoneWithAbbreviation:@"EST"] retain];
  
  ud = [NSUserDefaults standardUserDefaults];
  mailTemplateDefaultLanguage = [[ud stringForKey:@"SOGoDefaultLanguage"]
                                     retain];
  if (!mailTemplateDefaultLanguage)
    mailTemplateDefaultLanguage = @"French";
}

- (void)dealloc {
  [super dealloc];
}

/* accessors */

- (NSString *)iCalString {
  // for UI-X appointment viewer
  return [self contentAsString];
}

- (iCalEvent *)event {
  NSString  *iCalString;
  iCalEvent *event;

  iCalString = [self iCalString];
  if ([iCalString length] > 0) {
    iCalCalendar *cal;

    [parser parseFromSource:iCalString];
    cal   = [sax rootObject];
    [sax reset];
    event = [[cal events] lastObject];
    return event;
  }
  return nil;
}

/* iCal handling */

- (NSArray *)attendeeUIDsFromAppointment:(SOGoAppointment *)_apt {
  AgenorUserManager *um;
  NSMutableArray    *uids;
  NSArray  *attendees;
  unsigned i, count;
  NSString *email, *uid;
  
  if (![_apt isNotNull])
    return nil;
  
  if ((attendees = [_apt attendees]) == nil)
    return nil;
  count = [attendees count];
  uids = [NSMutableArray arrayWithCapacity:count + 1];
  
  um = [AgenorUserManager sharedUserManager];
  
  /* add organizer */
  
  email = [[_apt organizer] rfc822Email];
  if ([email isNotNull]) {
    uid = [um getUIDForEmail:email];
    if ([uid isNotNull]) {
      [uids addObject:uid];
    }
    else
      [self logWithFormat:@"Note: got no uid for organizer: '%@'", email];
  }

  /* add attendees */
  
  for (i = 0; i < count; i++) {
    iCalPerson *person;
    
    person = [attendees objectAtIndex:i];
    email  = [person rfc822Email];
    if (![email isNotNull]) continue;
    
    uid = [um getUIDForEmail:email];
    if (![uid isNotNull]) {
      [self logWithFormat:@"Note: got no uid for email: '%@'", email];
      continue;
    }
    if (![uids containsObject:uid])
      [uids addObject:uid];
  }
  
  return uids;
}

/* raw saving */

- (NSException *)primarySaveContentString:(NSString *)_iCalString {
  return [super saveContentString:_iCalString];
}
- (NSException *)primaryDelete {
  return [super delete];
}

/* folder management */

- (id)lookupHomeFolderForUID:(NSString *)_uid inContext:(id)_ctx {
  // TODO: what does this do? lookup the home of the organizer?
  return [[self container] lookupHomeFolderForUID:_uid inContext:_ctx];
}
- (NSArray *)lookupCalendarFoldersForUIDs:(NSArray *)_uids inContext:(id)_ctx {
  return [[self container] lookupCalendarFoldersForUIDs:_uids inContext:_ctx];
}

/* store in all the other folders */

- (NSException *)saveContentString:(NSString *)_iCal inUIDs:(NSArray *)_uids {
  NSEnumerator *e;
  id           folder;
  NSException  *allErrors = nil;
  id ctx;

  ctx = [[WOApplication application] context];
  
  e = [[self lookupCalendarFoldersForUIDs:_uids inContext:ctx]
	     objectEnumerator];
  while ((folder = [e nextObject]) != nil) {
    NSException           *error;
    SOGoAppointmentObject *apt;
    
    if (![folder isNotNull]) /* no folder was found for given UID */
      continue;
    
    apt = [folder lookupName:[self nameInContainer] inContext:ctx
		  acquire:NO];
    if (![apt isNotNull]) {
      [self logWithFormat:@"Note: did not find '%@' in folder: %@",
	      [self nameInContainer], folder];
      continue;
    }
    
    if ((error = [apt primarySaveContentString:_iCal]) != nil) {
      [self logWithFormat:@"Note: failed to save iCal in folder: %@", folder];
      // TODO: make compound
      allErrors = error;
    }
  }
  return allErrors;
}
- (NSException *)deleteInUIDs:(NSArray *)_uids {
  NSEnumerator *e;
  id           folder;
  NSException  *allErrors = nil;
  id           ctx;
  
  ctx = [[WOApplication application] context];
  
  e = [[self lookupCalendarFoldersForUIDs:_uids inContext:ctx]
	     objectEnumerator];
  while ((folder = [e nextObject])) {
    NSException           *error;
    SOGoAppointmentObject *apt;
    
    apt = [folder lookupName:[self nameInContainer] inContext:ctx
		  acquire:NO];
    if (![apt isNotNull]) {
      [self logWithFormat:@"Note: did not find '%@' in folder: %@",
	      [self nameInContainer], folder];
      continue;
    }
    
    if ((error = [apt primaryDelete]) != nil) {
      [self logWithFormat:@"Note: failed to delete in folder: %@", folder];
      // TODO: make compound
      allErrors = error;
    }
  }
  return allErrors;
}

/* "iCal multifolder saves" */

- (NSException *)saveContentString:(NSString *)_iCal baseSequence:(int)_v {
  /* 
     Note: we need to delete in all participants folders and send iMIP messages
           for all external accounts.
     
     Steps:
     - fetch stored content
     - parse old content
     - check if sequence matches (or if 0=ignore)
     - extract old attendee list + organizer (make unique)
     - parse new content (ensure that sequence is increased!)
     - extract new attendee list + organizer (make unique)
     - make a diff => new, same, removed
     - write to new, same
     - delete in removed folders
     - send iMIP mail for all folders not found
  */
  AgenorUserManager *um;
  SOGoAppointment   *oldApt, *newApt;
  iCalEventChanges  *changes;
  iCalPerson        *organizer;
  NSString          *oldContent, *uid;
  NSArray           *uids, *props;
  NSMutableArray    *attendees, *storeUIDs, *removedUIDs;
  NSException       *storeError, *delError;
  BOOL              updateForcesReconsider;
  
  updateForcesReconsider = NO;

  if ([_iCal length] == 0) {
    return [NSException exceptionWithHTTPStatus:400 /* Bad Request */
			reason:@"got no iCalendar content to store!"];
  }

  um = [AgenorUserManager sharedUserManager];

  /* handle old content */
  
  oldContent = [self iCalString]; /* if nil, this is a new appointment */
  if ([oldContent length] == 0) {
    /* new appointment */
    [self debugWithFormat:@"saving new appointment: %@", _iCal];
    oldApt = nil;
  }
  else {
    oldApt = 
      [[[SOGoAppointment alloc] initWithICalString:oldContent] autorelease];
  }
  
  /* compare sequence if requested */

  if (_v != 0) {
    // TODO
  }
  
  
  /* handle new content */
  
  newApt  = [[[SOGoAppointment alloc] initWithICalString:_iCal] autorelease];
  if (newApt == nil) {
    return [NSException exceptionWithHTTPStatus:400 /* Bad Request */
			reason:@"could not parse iCalendar content!"];
  }
  
  /* diff */
  
  changes     = [iCalEventChanges changesFromEvent:[oldApt event]
                                  toEvent:[newApt event]];

  uids        = [um getUIDsForICalPersons:[changes deletedAttendees]
                    applyStrictMapping:NO];
  removedUIDs = [NSMutableArray arrayWithArray:uids];

  uids        = [um getUIDsForICalPersons:[newApt attendees]
                    applyStrictMapping:NO];
  storeUIDs   = [NSMutableArray arrayWithArray:uids];
  props       = [changes updatedProperties];

  /* detect whether sequence has to be increased */
  if ([changes hasChanges])
    [newApt increaseSequence];

  /* preserve organizer */

  organizer = [[newApt event] organizer];
  uid       = [um getUIDForICalPerson:organizer];
  if (uid) {
    if (![storeUIDs containsObject:uid])
      [storeUIDs addObject:uid];
    [removedUIDs removeObject:uid];
  }

  /* organizer might have changed completely */

  if ((oldApt != nil) && ([props containsObject:@"organizer"])) {
    uid = [um getUIDForICalPerson:[[oldApt event] organizer]];
    if (uid) {
      if (![storeUIDs containsObject:uid]) {
        if (![removedUIDs containsObject:uid]) {
          [removedUIDs addObject:uid];
        }
      }
    }
  }

  [self debugWithFormat:@"UID ops:\n  store: %@\n  remove: %@",
                        storeUIDs, removedUIDs];

  /* if time did change, all participants have to re-decide ...
   * ... exception from that rule: the organizer
   */

  if (oldApt != nil                        &&
      ([props containsObject:@"startDate"] ||
       [props containsObject:@"endDate"]   ||
       [props containsObject:@"duration"]))
  {
    NSArray  *ps;
    unsigned i, count;
    
    ps    = [newApt attendees];
    count = [ps count];
    for (i = 0; i < count; i++) {
      iCalPerson *p;
      
      p = [ps objectAtIndex:i];
      if (![p hasSameEmailAddress:organizer])
        [p setParticipationStatus:iCalPersonPartStatNeedsAction];
    }
    _iCal = [newApt iCalString];
    updateForcesReconsider = YES;
  }

  /* perform storing */

  storeError = [self saveContentString:_iCal inUIDs:storeUIDs];
  delError   = [self deleteInUIDs:removedUIDs];

  // TODO: make compound
  if (storeError != nil) return storeError;
  if (delError   != nil) return delError;

  /* email notifications */

  attendees = [NSMutableArray arrayWithArray:[changes insertedAttendees]];
  [attendees removePerson:organizer];
  [self sendInvitationEMailForAppointment:newApt
        toAttendees:attendees];

  if (updateForcesReconsider) {
    attendees = [NSMutableArray arrayWithArray:[[newApt event] attendees]];
    [attendees removeObjectsInArray:[changes insertedAttendees]];
    [attendees removePerson:organizer];
    [self sendAppointmentUpdateEMailForOldAppointment:oldApt
          newAppointment:newApt
          toAttendees:attendees];
  }

  attendees = [NSMutableArray arrayWithArray:[changes deletedAttendees]];
  [attendees removePerson:organizer];
  if ([attendees count]) {
    SOGoAppointment *canceledApt;
    
    canceledApt = [newApt copy];
    [canceledApt cancelWithoutIncreasingSequence];
    [self sendAttendeeRemovalEMailForAppointment:canceledApt
          toAttendees:attendees];
    [canceledApt release];
  }
  return nil;
}

- (NSException *)deleteWithBaseSequence:(int)_v {
  /* 
     Note: We need to delete in all participants folders and send iMIP messages
           for all external accounts.
	   Delete is basically identical to save with all attendees and the
	   organizer being deleted.

     Steps:
     - fetch stored content
     - parse old content
     - check if sequence matches (or if 0=ignore)
     - extract old attendee list + organizer (make unique)
     - delete in removed folders
     - send iMIP mail for all folders not found
  */
  SOGoAppointment *apt;
  NSString        *econtent;
  NSArray         *removedUIDs;
  NSMutableArray  *attendees;

  /* load existing content */
  
  econtent = [self iCalString]; /* if nil, this is a new appointment */
  apt = [[[SOGoAppointment alloc] initWithICalString:econtent] autorelease];
  
  /* compare sequence if requested */

  if (_v != 0) {
    // TODO
  }
  
  removedUIDs = [self attendeeUIDsFromAppointment:apt];

  /* send notification email to attendees excluding organizer */
  attendees = [NSMutableArray arrayWithArray:[[apt event] attendees]];
  [attendees removePerson:[apt organizer]];
  
  /* flag appointment as being canceled */
  [apt cancelAndIncreaseSequence];
  /* remove all attendees to signal complete removal */
  [apt removeAllAttendees];

  /* send notification email */
  [self sendAppointmentDeletionEMailForAppointment:apt
        toAttendees:attendees];

  /* perform */
  
  return [self deleteInUIDs:removedUIDs];
}

- (NSException *)saveContentString:(NSString *)_iCalString {
  return [self saveContentString:_iCalString baseSequence:0];
}
- (NSException *)delete {
  return [self deleteWithBaseSequence:0];
}


- (NSException *)changeParticipationStatus:(NSString *)_status
  inContext:(id)_ctx
{
  SOGoAppointment *apt;
  iCalPerson      *p;
  NSString        *newContent;
  NSException     *ex;
  NSString        *myEMail;
  
  // TODO: do we need to use SOGoAppointment? (prefer iCalEvent?)
  apt = [[SOGoAppointment alloc] initWithICalString:[self iCalString]];
  if (apt == nil) {
    return [NSException exceptionWithHTTPStatus:500 /* Server Error */
                        reason:@"unable to parse appointment record"];
  }
  
  myEMail = [[_ctx activeUser] email];
  if ((p = [apt findParticipantWithEmail:myEMail]) == nil) {
    return [NSException exceptionWithHTTPStatus:404 /* Not Found */
                        reason:@"user does not participate in this "
                               @"appointment"];
  }
  
  [p setPartStat:_status];
  newContent = [[[apt iCalString] copy] autorelease];
  
  // TODO: send iMIP reply mails?
  
  [apt release]; apt = nil;
  
  if (newContent == nil) {
    return [NSException exceptionWithHTTPStatus:500 /* Server Error */
                        reason:@"Could not generate iCalendar data ..."];
  }
  
  if ((ex = [self saveContentString:newContent]) != nil) {
    // TODO: why is the exception wrapped?
    return [NSException exceptionWithHTTPStatus:500 /* Server Error */
                        reason:[ex reason]];
  }
  
  return nil /* means: no error */;
}


/* message type */

- (NSString *)outlookMessageClass {
  return @"IPM.Appointment";
}

/* EMail Notifications */

- (NSString *)homePageURLForPerson:(iCalPerson *)_person {
  static AgenorUserManager *um      = nil;
  static NSString          *baseURL = nil;
  NSString *uid;

  if (!um) {
    WOContext *ctx;
    NSArray   *traversalObjects;

    um = [[AgenorUserManager sharedUserManager] retain];

    /* generate URL from traversal stack */
    ctx = [[WOApplication application] context];
    traversalObjects = [ctx objectTraversalStack];
    if ([traversalObjects count] >= 1) {
      baseURL = [[[traversalObjects objectAtIndex:0] baseURLInContext:ctx]
                                                     retain];
    }
    else {
      [self warnWithFormat:@"Unable to create baseURL from context!"];
      baseURL = @"http://localhost/";
    }
  }
  uid = [um getUIDForEmail:[_person rfc822Email]];
  if (!uid) return nil;
  return [NSString stringWithFormat:@"%@%@", baseURL, uid];
}

- (NSTimeZone *)viewTimeZoneForPerson:(iCalPerson *)_person {
  /* TODO: get this from user config as soon as this is available and only
   *       fall back to default timeZone if config data is not available
   */
  return EST;
}


- (void)sendEMailUsingTemplateNamed:(NSString *)_pageName
  forOldAppointment:(SOGoAppointment *)_oldApt
  andNewAppointment:(SOGoAppointment *)_newApt
  toAttendees:(NSArray *)_attendees
{
  NSString                *pageName;
  iCalPerson              *organizer;
  NSString                *cn, *sender, *iCalString;
  NGSendMail              *sendmail;
  WOApplication           *app;
  unsigned                i, count;

  if (![_attendees count]) return; // another job neatly done :-)

  /* sender */

  organizer = [_newApt organizer];
  cn        = [organizer cnWithoutQuotes];
  if (cn) {
    sender = [NSString stringWithFormat:@"%@ <%@>",
                                        cn,
                                        [organizer rfc822Email]];
  }
  else {
    sender = [organizer rfc822Email];
  }

  /* generate iCalString once */
  iCalString = [_newApt iCalString];
  
  /* get sendmail object */
  sendmail   = [NGSendMail sharedSendMail];

  /* get WOApplication instance */
  app        = [WOApplication application];

  /* generate dynamic message content */

  count = [_attendees count];
  for (i = 0; i < count; i++) {
    iCalPerson              *attendee;
    NSString                *recipient;
    SOGoAptMailNotification *p;
    NSString                *subject, *text, *header;
    NGMutableHashMap        *headerMap;
    NGMimeMessage           *msg;
    NGMimeBodyPart          *bodyPart;
    NGMimeMultipartBody     *body;
    
    attendee  = [_attendees objectAtIndex:i];
    
    /* construct recipient */
    cn        = [attendee cn];
    if (cn) {
      recipient = [NSString stringWithFormat:@"%@ <%@>",
                                             cn,
                                             [attendee rfc822Email]];
    }
    else {
      recipient = [attendee rfc822Email];
    }

    /* create page name */
    // TODO: select user's default language?
    pageName   = [NSString stringWithFormat:@"SOGoAptMail%@%@",
                                            mailTemplateDefaultLanguage,
                                            _pageName];
    /* construct message content */
    p = [app pageWithName:pageName inContext:[WOContext context]];
    [p setNewApt:_newApt];
    [p setOldApt:_oldApt];
    [p setHomePageURL:[self homePageURLForPerson:attendee]];
    [p setViewTZ:[self viewTimeZoneForPerson:attendee]];
    subject = [p getSubject];
    text    = [p getBody];

    /* construct message */
    headerMap = [NGMutableHashMap hashMapWithCapacity:5];
    
    /* NOTE: multipart/alternative seems like the correct choice but
     * unfortunately Thunderbird doesn't offer the rich content alternative
     * at all. Mail.app shows the rich content alternative _only_
     * so we'll stick with multipart/mixed for the time being.
     */
    [headerMap setObject:@"multipart/mixed"    forKey:@"content-type"];
    [headerMap setObject:sender                forKey:@"From"];
    [headerMap setObject:recipient             forKey:@"To"];
    [headerMap setObject:[NSCalendarDate date] forKey:@"date"];
    [headerMap setObject:subject               forKey:@"Subject"];
    msg = [NGMimeMessage messageWithHeader:headerMap];
    
    /* multipart body */
    body = [[NGMimeMultipartBody alloc] initWithPart:msg];
    
    /* text part */
    headerMap = [NGMutableHashMap hashMapWithCapacity:1];
    [headerMap setObject:@"text/plain; charset=utf-8" forKey:@"content-type"];
    bodyPart = [NGMimeBodyPart bodyPartWithHeader:headerMap];
    [bodyPart setBody:[text dataUsingEncoding:NSUTF8StringEncoding]];

    /* attach text part to multipart body */
    [body addBodyPart:bodyPart];
    
    /* calendar part */
    header     = [NSString stringWithFormat:@"text/calendar; method=%@;"
                                            @" charset=utf-8",
                                            [_newApt method]];
    headerMap  = [NGMutableHashMap hashMapWithCapacity:1];
    [headerMap setObject:header forKey:@"content-type"];
    bodyPart   = [NGMimeBodyPart bodyPartWithHeader:headerMap];
    [bodyPart setBody:[iCalString dataUsingEncoding:NSUTF8StringEncoding]];
    
    /* attach calendar part to multipart body */
    [body addBodyPart:bodyPart];
    
    /* attach multipart body to message */
    [msg setBody:body];
    [body release];

    /* send the damn thing */
    [sendmail sendMimePart:msg
              toRecipients:[NSArray arrayWithObject:[attendee rfc822Email]]
              sender:[organizer rfc822Email]];
  }
}

- (void)sendInvitationEMailForAppointment:(SOGoAppointment *)_apt
  toAttendees:(NSArray *)_attendees
{
  if (![_attendees count]) return; // another job neatly done :-)

  [self sendEMailUsingTemplateNamed:@"Invitation"
        forOldAppointment:nil
        andNewAppointment:_apt
        toAttendees:_attendees];
}

- (void)sendAppointmentUpdateEMailForOldAppointment:(SOGoAppointment *)_oldApt
  newAppointment:(SOGoAppointment *)_newApt
  toAttendees:(NSArray *)_attendees
{
  if (![_attendees count]) return;
  
  [self sendEMailUsingTemplateNamed:@"Update"
        forOldAppointment:_oldApt
        andNewAppointment:_newApt
        toAttendees:_attendees];
}

- (void)sendAttendeeRemovalEMailForAppointment:(SOGoAppointment *)_apt
  toAttendees:(NSArray *)_attendees
{
  if (![_attendees count]) return;

  [self sendEMailUsingTemplateNamed:@"Removal"
        forOldAppointment:nil
        andNewAppointment:_apt
        toAttendees:_attendees];
}

- (void)sendAppointmentDeletionEMailForAppointment:(SOGoAppointment *)_apt
  toAttendees:(NSArray *)_attendees
{
  if (![_attendees count]) return;

  [self sendEMailUsingTemplateNamed:@"Deletion"
        forOldAppointment:nil
        andNewAppointment:_apt
        toAttendees:_attendees];
}

@end /* SOGoAppointmentObject */

@implementation NSMutableArray (iCalPersonConvenience)

- (void)removePerson:(iCalPerson *)_person {
  int i;
  
  for (i = [self count] - 1; i >= 0; i--) {
    iCalPerson *p;
    
    p = [self objectAtIndex:i];
    if ([p hasSameEmailAddress:_person])
      [self removeObjectAtIndex:i];
  }
}

@end /* NSMutableArray (iCalPersonConvenience) */
