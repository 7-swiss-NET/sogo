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

#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>

#import <NGObjWeb/NSException+HTTP.h>
#import <NGObjWeb/WOContext+SoObjects.h>
#import <NGExtensions/NSNull+misc.h>
#import <NGExtensions/NSObject+Logs.h>
#import <NGCards/iCalCalendar.h>
#import <NGCards/iCalEvent.h>
#import <NGCards/iCalEventChanges.h>
#import <NGCards/iCalPerson.h>
#import <SaxObjC/XMLNamespaces.h>

#import <SoObjects/SOGo/iCalEntityObject+Utilities.h>
#import <SoObjects/SOGo/LDAPUserManager.h>
#import <SoObjects/SOGo/NSArray+Utilities.h>
#import <SoObjects/SOGo/NSObject+DAV.h>
#import <SoObjects/SOGo/SOGoObject.h>
#import <SoObjects/SOGo/SOGoPermissions.h>
#import <SoObjects/SOGo/SOGoUser.h>
#import <SoObjects/SOGo/SOGoWebDAVAclManager.h>
#import <SoObjects/SOGo/SOGoWebDAVValue.h>
#import <SoObjects/SOGo/WORequest+SOGo.h>

#import "iCalEventChanges+SOGo.h"
#import "iCalEntityObject+SOGo.h"
#import "iCalPerson+SOGo.h"
#import "NSArray+Appointments.h"
#import "SOGoAppointmentFolder.h"
#import "SOGoAppointmentOccurence.h"

#import "SOGoAppointmentObject.h"

@implementation SOGoAppointmentObject

+ (SOGoWebDAVAclManager *) webdavAclManager
{
  SOGoWebDAVAclManager *aclManager = nil;
  NSString *nsD, *nsI;

  if (!aclManager)
    {
      nsD = @"DAV:";
      nsI = @"urn:inverse:params:xml:ns:inverse-dav";

      aclManager = [SOGoWebDAVAclManager new];
      [aclManager registerDAVPermission: davElement (@"read", nsD)
		  abstract: YES
		  withEquivalent: nil
		  asChildOf: davElement (@"all", nsD)];
      [aclManager registerDAVPermission: davElement (@"read-current-user-privilege-set", nsD)
		  abstract: YES
		  withEquivalent: SoPerm_WebDAVAccess
		  asChildOf: davElement (@"read", nsD)];
      [aclManager registerDAVPermission: davElement (@"view-whole-component", nsI)
		  abstract: NO
		  withEquivalent: SOGoCalendarPerm_ViewAllComponent
		  asChildOf: davElement (@"read", nsD)];
      [aclManager registerDAVPermission: davElement (@"view-date-and-time", nsI)
		  abstract: NO
		  withEquivalent: SOGoCalendarPerm_ViewDAndT
		  asChildOf: davElement (@"view-whole-component", nsI)];
      [aclManager registerDAVPermission: davElement (@"write", nsD)
		  abstract: YES
		  withEquivalent: SOGoCalendarPerm_ModifyComponent
		  asChildOf: davElement (@"all", nsD)];
      [aclManager
	registerDAVPermission: davElement (@"write-properties", nsD)
	abstract: YES
	withEquivalent: SoPerm_ChangePermissions /* hackish */
	asChildOf: davElement (@"write", nsD)];
      [aclManager
	registerDAVPermission: davElement (@"write-content", nsD)
	abstract: YES
	withEquivalent: nil
	asChildOf: davElement (@"write", nsD)];
      [aclManager
	registerDAVPermission: davElement (@"respond-to-component", nsI)
	abstract: YES
	withEquivalent: SOGoCalendarPerm_RespondToComponent
	asChildOf: davElement (@"write-content", nsD)];
      [aclManager registerDAVPermission: davElement (@"admin", nsI)
		  abstract: YES
		  withEquivalent: nil
		  asChildOf: davElement (@"all", nsD)];
      [aclManager
	registerDAVPermission: davElement (@"read-acl", nsD)
	abstract: YES
	withEquivalent: SOGoPerm_ReadAcls
	asChildOf: davElement (@"admin", nsI)];
      [aclManager
	registerDAVPermission: davElement (@"write-acl", nsD)
	abstract: YES
	withEquivalent: nil
	asChildOf: davElement (@"admin", nsI)];
    }

  return aclManager;
}

- (NSString *) componentTag
{
  return @"vevent";
}

- (SOGoComponentOccurence *) occurence: (iCalRepeatableEntityObject *) occ
{
  return [SOGoAppointmentOccurence occurenceWithComponent: occ
				   withMasterComponent: [self component: NO
							      secure: NO]
				   inContainer: self];
}

- (iCalRepeatableEntityObject *) newOccurenceWithID: (NSString *) recID
{
  iCalEvent *newOccurence;
  NSCalendarDate *date;
  unsigned int interval;

  newOccurence = (iCalEvent *) [super newOccurenceWithID: recID];
  date = [newOccurence recurrenceId];
  interval = [[newOccurence endDate]
	       timeIntervalSinceDate: [newOccurence startDate]];
  [newOccurence setStartDate: date];
  [newOccurence setEndDate: [date addYear: 0
				  month: 0
				  day: 0
				  hour: 0
				  minute: 0
				  second: interval]];

  return newOccurence;
}

- (SOGoAppointmentObject *) _lookupEvent: (NSString *) eventUID
				  forUID: (NSString *) uid
{
  SOGoAppointmentFolder *folder;
  SOGoAppointmentObject *object;
  NSString *possibleName;

  folder = [container lookupCalendarFolderForUID: uid];
  object = [folder lookupName: nameInContainer
		   inContext: context acquire: NO];
  if ([object isKindOfClass: [NSException class]])
    {
      possibleName = [folder resourceNameForEventUID: eventUID];
      if (possibleName)
	{
	  object = [folder lookupName: possibleName
			   inContext: context acquire: NO];
	  if ([object isKindOfClass: [NSException class]])
	    object = nil;
	}
      else
	object = nil;
    }

  if (!object)
    {
      object = [SOGoAppointmentObject objectWithName: nameInContainer
				      inContainer: folder];
      [object setIsNew: YES];
    }

  return object;
}

- (void) _addOrUpdateEvent: (iCalEvent *) event
		    forUID: (NSString *) uid
{
  SOGoAppointmentObject *object;
  NSString *iCalString, *userLogin;

  userLogin = [[context activeUser] login];
  if (![uid isEqualToString: userLogin])
    {
      object = [self _lookupEvent: [event uid] forUID: uid];
      iCalString = [[event parent] versitString];
      [object saveContentString: iCalString];
    }
}

- (void) _removeEventFromUID: (NSString *) uid
{
  SOGoAppointmentFolder *folder;
  SOGoAppointmentObject *object;

  if (![uid isEqualToString: owner])
    {
      folder = [container lookupCalendarFolderForUID: uid];
      object = [folder lookupName: nameInContainer
		       inContext: context acquire: NO];
      if (![object isKindOfClass: [NSException class]])
	[object delete];
    }
}

#warning what about occurences?
- (void) _handleRemovedUsers: (NSArray *) attendees
{
  NSEnumerator *enumerator;
  iCalPerson *currentAttendee;
  NSString *currentUID;

  enumerator = [attendees objectEnumerator];
  while ((currentAttendee = [enumerator nextObject]))
    {
      currentUID = [currentAttendee uid];
      if (currentUID)
	[self _removeEventFromUID: currentUID];
    }
}

- (void) _requireResponseFromAttendees: (NSArray *) attendees
{
  NSEnumerator *enumerator;
  iCalPerson *currentAttendee;

  enumerator = [attendees objectEnumerator];
  while ((currentAttendee = [enumerator nextObject]))
    {
      [currentAttendee setRsvp: @"TRUE"];
      [currentAttendee setParticipationStatus: iCalPersonPartStatNeedsAction];
    }
}

- (void) _handleSequenceUpdateInEvent: (iCalEvent *) newEvent
		    ignoringAttendees: (NSArray *) attendees
		         fromOldEvent: (iCalEvent *) oldEvent
{
  NSMutableArray *updateAttendees, *updateUIDs;
  NSEnumerator *enumerator;
  iCalPerson *currentAttendee;
  NSString *currentUID;

  updateAttendees = [NSMutableArray arrayWithArray: [newEvent attendees]];
  [updateAttendees removeObjectsInArray: attendees];

  updateUIDs = [NSMutableArray arrayWithCapacity: [updateAttendees count]];
  enumerator = [updateAttendees objectEnumerator];
  while ((currentAttendee = [enumerator nextObject]))
    {
      currentUID = [currentAttendee uid];
      if (currentUID)
	[self _addOrUpdateEvent: newEvent
	      forUID: currentUID];
    }

  [self sendEMailUsingTemplateNamed: @"Invitation"
	forObject: [newEvent itipEntryWithMethod: @"request"]
	toAttendees: updateAttendees];
}

- (void) _handleAddedUsers: (NSArray *) attendees
		 fromEvent: (iCalEvent *) newEvent
{
  NSEnumerator *enumerator;
  iCalPerson *currentAttendee;
  NSString *currentUID;

  enumerator = [attendees objectEnumerator];
  while ((currentAttendee = [enumerator nextObject]))
    {
      currentUID = [currentAttendee uid];
      if (currentUID)
	[self _addOrUpdateEvent: newEvent
	      forUID: currentUID];
    }
}

- (void) _handleUpdatedEvent: (iCalEvent *) newEvent
		fromOldEvent: (iCalEvent *) oldEvent
{
  NSArray *attendees;
  iCalEventChanges *changes;

  changes = [newEvent getChangesRelativeToEvent: oldEvent];
  attendees = [changes deletedAttendees];
  if ([attendees count])
    {
      [self _handleRemovedUsers: attendees];
      [self sendEMailUsingTemplateNamed: @"Deletion"
	    forObject: [newEvent itipEntryWithMethod: @"cancel"]
	    toAttendees: attendees];
    }

  attendees = [changes insertedAttendees];
  if ([changes sequenceShouldBeIncreased])
    {
      [newEvent increaseSequence];
      [self _requireResponseFromAttendees: [newEvent attendees]];
      [self _handleSequenceUpdateInEvent: newEvent
	    ignoringAttendees: attendees
	    fromOldEvent: oldEvent];
    }
  else
    [self _requireResponseFromAttendees: attendees];

  if ([attendees count])
    {
      [self _handleAddedUsers: attendees fromEvent: newEvent];
      [self sendEMailUsingTemplateNamed: @"Invitation"
	    forObject: [newEvent itipEntryWithMethod: @"request"]
	    toAttendees: attendees];
    }
}

- (void) saveComponent: (iCalEvent *) newEvent
{
  iCalEvent *oldEvent;
  NSArray *attendees;
  SOGoUser *ownerUser;

  [[newEvent parent] setMethod: @""];
  ownerUser = [SOGoUser userWithLogin: owner roles: nil];
  if ([newEvent userIsOrganizer: ownerUser])
    {
      oldEvent = [self component: NO secure: NO];
      if (oldEvent)
	[self _handleUpdatedEvent: newEvent fromOldEvent: oldEvent];
      else
	{
	  attendees = [newEvent attendeesWithoutUser: [context activeUser]];
	  if ([attendees count])
	    {
	      [self _handleAddedUsers: attendees fromEvent: newEvent];
	      [self sendEMailUsingTemplateNamed: @"Invitation"
		    forObject: [newEvent itipEntryWithMethod: @"request"]
		    toAttendees: attendees];
	    }

	  if (![[newEvent attendees] count])
	    [[newEvent uniqueChildWithTag: @"organizer"] setValue: 0
							 to: @""];
	}
    }

  [super saveComponent: newEvent];
}

//
// This method is used to update the status of an attendee.
//
// - theOwnerUser is owner of the calendar where the attendee
//   participation state has changed.
// - uid is the actual UID of the user for whom we must
//   update the calendar event (with the participation change)
//
// This method is called multiple times, in order to update the
// status of the attendee in calendars for the particular event UID.
// 
- (NSException *) _updateAttendee: (iCalPerson *) attendee
                        ownerUser: (SOGoUser *) theOwnerUser
		      forEventUID: (NSString *) eventUID
		     withSequence: (NSNumber *) sequence
			   forUID: (NSString *) uid
	          shouldAddSentBy: (BOOL) b
{
  SOGoAppointmentObject *eventObject;
  iCalEvent *event;
  iCalPerson *otherAttendee;
  NSString *iCalString;
  NSException *error;

  error = nil;

  eventObject = [self _lookupEvent: eventUID forUID: uid];
  if (![eventObject isNew])
    {
      event = [eventObject component: NO secure: NO];
      if ([[event sequence] compare: sequence]
	  == NSOrderedSame)
	{
	  SOGoUser *currentUser;
	  
	  //otherAttendee = [event findParticipant: [context activeUser]];
	  otherAttendee = [event findParticipant: theOwnerUser];
	  [otherAttendee setPartStat: [attendee partStat]];
	  
	  // If one has accepted / declined an invitation on behalf of
	  // the attendee, we add the user to the SENT-BY attribute.
	  currentUser = [context activeUser];
	  if (b && ![[currentUser login] isEqualToString: [theOwnerUser login]])
	    {
	      NSString *currentEmail;
	      currentEmail = [[currentUser allEmails] objectAtIndex: 0];
	      [otherAttendee addAttribute: @"SENT-BY"
			     value: [NSString stringWithFormat: @"\"MAILTO:%@\"", currentEmail]];
	    }

	  iCalString = [[event parent] versitString];
	  error = [eventObject saveContentString: iCalString];
	}
    }

  return error;
}


//
// This method is invoked only from the SOGo Web interface.
//
// - theOwnerUser is owner of the calendar where the attendee
//   participation state has changed.
//
- (NSException *) _handleAttendee: (iCalPerson *) attendee
                        ownerUser: (SOGoUser *) theOwnerUser
		     statusChange: (NSString *) newStatus
			  inEvent: (iCalEvent *) event
{
  NSString *newContent, *currentStatus, *currentUser, *organizerUID;
  SOGoUser *ownerUser;
  NSException *ex;

  ex = nil;

  currentStatus = [attendee partStat];
  if ([currentStatus caseInsensitiveCompare: newStatus]
      != NSOrderedSame)
    {
      [attendee setPartStat: newStatus];
      
      // If one has accepted / declined an invitation on behalf of
      // the attendee, we add the user to the SENT-BY attribute.
      currentUser = [context activeUser];
      if (![[currentUser login] isEqualToString: [theOwnerUser login]])
	{
	  NSString *currentEmail;
	  currentEmail = [[currentUser allEmails] objectAtIndex: 0];
	  [attendee addAttribute: @"SENT-BY"
		    value: [NSString stringWithFormat: @"\"MAILTO:%@\"", currentEmail]];
	}

      // We generate the updated iCalendar file and we save it
      // in the database.
      newContent = [[event parent] versitString];
      ex = [self saveContentString: newContent];

      // If the current user isn't the organizer of the event
      // that has just been updated, we update the event and
      // send a notification
      ownerUser = [SOGoUser userWithLogin: owner roles: nil];
      if (!(ex || [event userIsOrganizer: ownerUser]))
	{
	  if ([[attendee rsvp] isEqualToString: @"true"]
	      && [event isStillRelevant])
	    [self sendResponseToOrganizer: event
		  from: ownerUser];
	  
	  organizerUID = [[event organizer] uid];
	  if (organizerUID)
	    ex = [self _updateAttendee: attendee
		       ownerUser: theOwnerUser
		       forEventUID: [event uid]
		       withSequence: [event sequence]
		       forUID: organizerUID
		       shouldAddSentBy: YES];
	}

      // We update the calendar of all participants that are
      // local to the system. This is useful in case user A accepts
      // invitation from organizer B and users C, D, E who are also
      // attendees need to verify if A has accepted.
      NSArray *attendees;
      iCalPerson *att;
      NSString *uid;
      int i;

      attendees = [event attendees];

      for (i = 0; i < [attendees count]; i++)
	{
	  att = [attendees objectAtIndex: i];
	  
	  if (att == attendee) continue;
	  
	  uid = [[LDAPUserManager sharedUserManager]
		  getUIDForEmail: [att rfc822Email]];

	  if (uid)
	    {
	      [self _updateAttendee: attendee
		    ownerUser: theOwnerUser
		    forEventUID: [event uid]
		    withSequence: [event sequence]
		    forUID: uid
		    shouldAddSentBy: YES];
	    }
	}
    }

  return ex;
}

- (NSDictionary *) _caldavSuccessCodeWithRecipient: (NSString *) recipient
{
  NSMutableArray *element;
  NSDictionary *code;

  element = [NSMutableArray new];
  [element addObject: davElementWithContent (@"recipient", XMLNS_CALDAV,
					     recipient)];
  [element addObject: davElementWithContent (@"request-status",
					     XMLNS_CALDAV,
					     @"2.0;Success")];
  code = davElementWithContent (@"response", XMLNS_CALDAV,
				element);
  [element release];

  return code;
}

- (NSArray *) postCalDAVEventRequestTo: (NSArray *) recipients
				  from: (NSString *) originator
{
  NSMutableArray *elements;
  NSEnumerator *recipientsEnum;
  NSString *recipient, *uid;
  iCalEvent *event;
  iCalPerson *person;

  elements = [NSMutableArray array];

  event = [self component: NO secure: NO];
  recipientsEnum = [recipients objectEnumerator];
  while ((recipient = [recipientsEnum nextObject]))
    if ([[recipient lowercaseString] hasPrefix: @"mailto:"])
      {
	person = [iCalPerson new];
	[person setValue: 0 to: recipient];
	uid = [person uid];
	if (uid)
	  [self _addOrUpdateEvent: event forUID: uid];
#warning fix this when sendEmailUsing blabla has been cleaned up
	[self sendEMailUsingTemplateNamed: @"Invitation"
	      forObject: event
	      toAttendees: [NSArray arrayWithObject: person]];
	[person release];
	[elements
	  addObject: [self _caldavSuccessCodeWithRecipient: recipient]];
      }

  return elements;
}

- (NSArray *) postCalDAVEventCancelTo: (NSArray *) recipients
				 from: (NSString *) originator
{
  NSMutableArray *elements;
  NSEnumerator *recipientsEnum;
  NSString *recipient, *uid;
  iCalEvent *event;
  iCalPerson *person;

  elements = [NSMutableArray array];

  event = [self component: NO secure: NO];
  recipientsEnum = [recipients objectEnumerator];
  while ((recipient = [recipientsEnum nextObject]))
    if ([[recipient lowercaseString] hasPrefix: @"mailto:"])
      {
	person = [iCalPerson new];
	[person setValue: 0 to: recipient];
	uid = [person uid];
	if (uid)
	  [self _removeEventFromUID: uid];
#warning fix this when sendEmailUsing blabla has been cleaned up
	[self sendEMailUsingTemplateNamed: @"Deletion"
	      forObject: event
	      toAttendees: [NSArray arrayWithObject: person]];
	[person release];
	[elements
	  addObject: [self _caldavSuccessCodeWithRecipient: recipient]];
      }

  return elements;
}


//
// This method is invoked by CalDAV clients such as
// Mozilla Lightning. We assume the SENT-BY has
// already been added, if required.
//
// It is used to updated the status of an attendee.
// The originator is the actualy owner of the calendar
// where the update took place. The status must then
// be propagated to the organizer and the other attendees.
//
- (void) takeAttendeeStatus: (iCalPerson *) attendee
		       from: (NSString *) originator
{
  iCalPerson *localAttendee;
  iCalEvent *event;
  SOGoUser *ownerUser;

  event = [self component: NO secure: NO];
  localAttendee = [event findParticipantWithEmail: [attendee rfc822Email]];
  if (localAttendee)
    {
      [localAttendee setPartStat: [attendee partStat]];
      [self saveComponent: event];

      /// TEST ///
     NSArray *attendees;
     iCalPerson *att;
     NSString *uid;
     int i;
     
     ownerUser = [SOGoUser userWithLogin:[[LDAPUserManager sharedUserManager]
					   getUIDForEmail: originator]
			   roles: nil];

     // We update the copy of the organizer, only
     // if it's a local user.
#warning add a check for only local users
     uid = [[event organizer] uid];
     if (uid)
       [self _updateAttendee: attendee
	     ownerUser: ownerUser
	     forEventUID: [event uid]
	     withSequence: [event sequence]
	     forUID: uid
	     shouldAddSentBy: NO];
    
      attendees = [event attendees];

      for (i = 0; i < [attendees count]; i++)
	{
	  att = [attendees objectAtIndex: i];
	  
	  if (att == attendee) continue;
	  
	  uid = [[LDAPUserManager sharedUserManager]
		  getUIDForEmail: [att rfc822Email]];

	  if (uid)
	    {		
	      // We skip the update that correspond to the originator
	      // since the CalDAV client will already have updated
	      // the actual event.
	      if ([ownerUser hasEmail: [att rfc822Email]]) 
		continue;

	      [self _updateAttendee: attendee
		    ownerUser: ownerUser
		    forEventUID: [event uid]
		    withSequence: [event sequence]
		    forUID: uid
		    shouldAddSentBy: NO];
	    }
	}

      /// TEST ///
    }
  else
    [self errorWithFormat: @"attendee not found: '%@'", attendee];
}

- (NSArray *) postCalDAVEventReplyTo: (NSArray *) recipients
				from: (NSString *) originator
{
  NSMutableArray *elements;
  NSEnumerator *recipientsEnum;
  NSString *recipient, *uid, *eventUID;
  iCalEvent *event;
  iCalPerson *attendee, *person;
  SOGoAppointmentObject *recipientEvent;
  SOGoUser *ownerUser;
  NSString *email;

  elements = [NSMutableArray array];
  event = [self component: NO secure: NO];
  //ownerUser = [SOGoUser userWithLogin: owner roles: nil]; 

  ownerUser = [SOGoUser userWithLogin: [[LDAPUserManager sharedUserManager]
					 getUIDForEmail: originator]
			roles: nil];
  attendee = [event findParticipant: ownerUser];
  eventUID = [event uid];

  recipientsEnum = [recipients objectEnumerator];
  while ((recipient = [recipientsEnum nextObject]))
    if ([[recipient lowercaseString] hasPrefix: @"mailto:"])
      {
	person = [iCalPerson new];
	[person setValue: 0 to: recipient];
	uid = [person uid];
	if (uid)
	  {
	    recipientEvent = [self _lookupEvent: eventUID forUID: uid];
	    if ([recipientEvent isNew])
	      [recipientEvent saveComponent: event];
	    else
	      [recipientEvent takeAttendeeStatus: attendee
			      from: originator];
	  }
	[self sendIMIPReplyForEvent: event
	      from: ownerUser
	      to: person];
	[person release];
	[elements
	  addObject: [self _caldavSuccessCodeWithRecipient: recipient]];
      }

  return elements;
}

//
// This method is invoked only from the SOGo Web interface.
//
- (NSException *) changeParticipationStatus: (NSString *) _status
{
  iCalEvent *event;
  iCalPerson *attendee;
  NSException *ex;
  SOGoUser *ownerUser;

  ex = nil;

  event = [self component: NO secure: NO];
  if (event)
    {
      // owerUser will actually be the owner of the calendar
      // where the participation change on the event has
      // actually occured. The particpation change will of
      // course be on the attendee that is the owner of the
      // calendar where the participation change has occured.
      ownerUser = [SOGoUser userWithLogin: owner roles: nil];
     
      attendee = [event findParticipant: ownerUser];
      if (attendee)
	ex = [self _handleAttendee: attendee
		   ownerUser: ownerUser
		   statusChange: _status
		   inEvent: event];
      else
        ex = [NSException exceptionWithHTTPStatus: 404 /* Not Found */
                          reason: @"user does not participate in this "
                          @"calendar event"];
    }
  else
    ex = [NSException exceptionWithHTTPStatus: 500 /* Server Error */
                      reason: @"unable to parse event record"];

  return ex;
}

- (void) prepareDeleteOccurence: (iCalEvent *) occurence
{
  iCalEvent *event;
  SOGoUser *ownerUser, *currentUser;
  NSArray *attendees;

  if ([[context request] handledByDefaultHandler])
    {
      ownerUser = [SOGoUser userWithLogin: owner roles: nil];
      event = [self component: NO secure: NO];
      if (!occurence)
	occurence = event;
      if ([event userIsOrganizer: ownerUser])
	{
	  currentUser = [context activeUser];
	  attendees = [occurence attendeesWithoutUser: currentUser];
	  if (![attendees count] && event != occurence)
	    attendees = [event attendeesWithoutUser: currentUser];
	  if ([attendees count])
	    {
	      [self _handleRemovedUsers: attendees];
	      [self sendEMailUsingTemplateNamed: @"Deletion"
		    forObject: [occurence itipEntryWithMethod: @"cancel"]
		    toAttendees: attendees];
	    }
	}
      else if ([occurence userIsParticipant: ownerUser])
	[self changeParticipationStatus: @"DECLINED"];
    }
}

- (void) prepareDelete
{
  [self prepareDeleteOccurence: nil];
}

/* message type */

- (NSString *) outlookMessageClass
{
  return @"IPM.Appointment";
}

@end /* SOGoAppointmentObject */
