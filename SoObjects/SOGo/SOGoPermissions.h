/* SOGoPermissions.h - this file is part of SOGo
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

#ifndef SOGOPERMISSIONS_H
#define SOGOPERMISSIONS_H

#import <Foundation/NSString.h>

#import <NGObjWeb/SoPermissions.h>

extern NSString *SOGoRole_ObjectCreator;
extern NSString *SOGoRole_ObjectEraser;

extern NSString *SOGoRole_FreeBusy;
extern NSString *SOGoRole_FreeBusyLookup;

extern NSString *SOGoPerm_ReadAcls;
extern NSString *SOGoPerm_FreeBusyLookup;

extern NSString *SOGoCalendarRole_Organizer;
extern NSString *SOGoCalendarRole_Participant;

extern NSString *SOGoCalendarRole_PublicViewer;
extern NSString *SOGoCalendarRole_PublicDAndTViewer;
extern NSString *SOGoCalendarRole_PublicModifier;
extern NSString *SOGoCalendarRole_PublicResponder;
extern NSString *SOGoCalendarRole_PrivateViewer;
extern NSString *SOGoCalendarRole_PrivateDAndTViewer;
extern NSString *SOGoCalendarRole_PrivateModifier;
extern NSString *SOGoCalendarRole_PrivateResponder;
extern NSString *SOGoCalendarRole_ConfidentialViewer;
extern NSString *SOGoCalendarRole_ConfidentialDAndTViewer;
extern NSString *SOGoCalendarRole_ConfidentialModifier;
extern NSString *SOGoCalendarRole_ConfidentialResponder;

#endif /* SOGOPERMISSIONS_H */
