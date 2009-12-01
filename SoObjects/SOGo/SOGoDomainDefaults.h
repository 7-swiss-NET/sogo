/* SOGoDomainDefaults.h - this file is part of SOGo
 *
 * Copyright (C) 2009 Inverse inc.
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

#ifndef SOGODOMAINDEFAULTS_H
#define SOGODOMAINDEFAULTS_H

#import <SOGo/SOGoLDAPDefaults.h>
#import <SOGo/SOGoUserDefaults.h>

@interface SOGoDomainDefaults : SOGoUserDefaults <SOGoLDAPDefaults>

+ (SOGoDomainDefaults *) defaultsForDomain: (NSString *) domainId;

- (NSString *) profileURL;
- (NSString *) folderInfoURL;

- (NSArray *) superUsernames;

- (NSArray *) userSources;

- (NSString *) mailDomain;
- (NSString *) imapServer;
- (NSString *) imapAclStyle;
- (BOOL) imapAclConformsToIMAPExt;
- (BOOL) forceIMAPLoginWithEmail;
- (BOOL) forwardEnabled;
- (BOOL) vacationEnabled;
- (NSString *) otherUsersFolderName;
- (NSString *) sharedFolderName;
- (NSString *) mailingMechanism;
- (NSString *) smtpServer;
- (NSString *) mailSpoolPath;
- (float) softQuotaRatio;
- (BOOL) mailKeepDraftsAfterSend;
- (BOOL) mailAttachTextDocumentsInline;
- (NSArray *) mailListViewColumnsOrder;

- (BOOL) aclSendEMailNotifications;
- (BOOL) appointmentSendEMailNotifications;
- (BOOL) foldersSendEMailNotifications;
- (NSArray *) calendarDefaultRoles;
- (NSArray *) contactsDefaultRoles;
- (NSArray *) mailPollingIntervals;

- (NSString *) calendarDefaultCategoryColor;

- (NSArray *) freeBusyDefaultInterval;
- (int) davCalendarStartTimeLimit;

@end

#endif /* SOGODOMAINDEFAULTS_H */
