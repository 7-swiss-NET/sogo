/*
  Copyright (C) 2000-2005 SKYRIX Software AG
  Copyright (C) 2006-2009 Inverse inc.

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

#ifndef	__Appointments_SOGoAptMailNotification_H_
#define	__Appointments_SOGoAptMailNotification_H_

#include <NGObjWeb/SoComponent.h>

@class NSCalendarDate;
@class NSMutableDictionary;
@class NSString;
@class NSTimeZone;
@class iCalEvent;

/*
 * NOTE: We inherit from SoComponent in order to get the correct
 *       resourceManager required for this product
 */
@interface SOGoAptMailNotification : SoComponent
{
  iCalEvent *apt;
  iCalEvent *previousApt;
  NSString *homePageURL;
  NSTimeZone *viewTZ;
  NSCalendarDate *oldStartDate;
  NSCalendarDate *newStartDate;
  NSString *organizerName;
  NSMutableDictionary *values;
}

- (void) setupValues;

- (iCalEvent *) apt;
- (void) setApt: (iCalEvent *) theApt;

- (iCalEvent *) previousApt;
- (void) setPreviousApt: (iCalEvent *) theApt;

- (void) setOrganizerName: (NSString *) theString;
- (NSString *) organizerName;

- (NSCalendarDate *) oldStartDate;
- (NSCalendarDate *) newStartDate;

- (NSString *) getSubject;
- (NSString *) getBody;
  
@end

#endif	/* __Appointments_SOGoAptMailNotification_H_ */
