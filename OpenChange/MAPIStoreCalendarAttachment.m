/* MAPIStoreCalendarAttachment.m - this file is part of SOGo
 *
 * Copyright (C) 2011 Inverse inc
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

#import "MAPIStoreTypes.h"

#import "MAPIStoreEmbeddedMessage.h"

#import "MAPIStoreCalendarAttachment.h"

#undef DEBUG
#include <stdbool.h>
#include <gen_ndr/exchange.h>
#include <mapistore/mapistore.h>
#include <mapistore/mapistore_errors.h>

@implementation MAPIStoreCalendarAttachment

- (int) getProperty: (void **) data
            withTag: (enum MAPITAGS) propTag
{
  int rc;

  rc = MAPISTORE_SUCCESS;
  switch (propTag)
    {
    case PR_ATTACHMENT_HIDDEN:
      *data = MAPIBoolValue (memCtx, YES);
      break;
    case PR_ATTACHMENT_FLAGS:
      *data = MAPILongValue (memCtx, 0x00000002); /* afException */
      break;
    case PR_ATTACH_METHOD:
      *data = MAPILongValue (memCtx, 0x00000005); /* afEmbeddedMessage */
      break;

    // case PidTagExceptionStartTime:
    // case PidTagExceptionEndTime:
    // case PidTagExceptionReplaceTime:

    default:
      rc = [super getProperty: data withTag: propTag];
    }

  return rc;
}

/* subclasses */
- (MAPIStoreEmbeddedMessage *) openEmbeddedMessage
{
  MAPIStoreEmbeddedMessage *msg;

  if (isNew)
    msg = nil;
  else
    msg = nil;

  return msg;
}

- (MAPIStoreEmbeddedMessage *) createEmbeddedMessage
{
  return [MAPIStoreEmbeddedMessage embeddedMessageWithAttachment: self];
}

@end
