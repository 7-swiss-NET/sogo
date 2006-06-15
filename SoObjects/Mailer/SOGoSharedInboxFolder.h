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

#ifndef __Mailer_SOGoSharedInboxFolder_H__
#define __Mailer_SOGoSharedInboxFolder_H__

#include <SoObjects/Mailer/SOGoMailFolder.h>

/*
  SOGoSharedInboxFolder
    Parent object: the SOGoSharedMailAccount
    Child objects: SOGoMailObject or SOGoMailFolder
    
  The SOGoSharedInboxFolder is a special SOGoMailFolder for use as the INBOX
  og SOGoSharedMailAccounts. This is necessary because the INBOX location in
  the IMAP4 server is different for shared boxes (its the shared user folder,
  not a mapped subfolder).
*/

@interface SOGoSharedInboxFolder : SOGoMailFolder
{
}

@end

#endif /* __Mailer_SOGoSharedInboxFolder_H__ */
