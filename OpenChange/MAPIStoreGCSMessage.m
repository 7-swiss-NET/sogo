/* MAPIStoreGCSMessage.m - this file is part of SOGo
 *
 * Copyright (C) 2011 Inverse inc
 *
 * Author: Wolfgang Sourdeau <wsourdeau@inverse.ca>
 *
 * This file is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
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

#import <Foundation/NSValue.h>
#import <NGExtensions/NSObject+Logs.h>
#import <SOGo/SOGoContentObject.h>

#import "MAPIStoreGCSFolder.h"
#import "MAPIStoreTypes.h"

#import "MAPIStoreGCSMessage.h"

#undef DEBUG
#include <mapistore/mapistore.h>

@implementation MAPIStoreGCSMessage

- (NSCalendarDate *) creationTime
{
  return [sogoObject creationDate];
}

- (NSCalendarDate *) lastModificationTime
{
  return [sogoObject lastModified];
}

- (uint64_t) objectVersion
{
  uint64_t version = 0xffffffffffffffffLL;
  NSNumber *changeNumber;

  if (![sogoObject isNew])
    {
      changeNumber = [(MAPIStoreGCSFolder *) container
                        changeNumberForMessageWithKey: [self nameInContainer]];
      if (!changeNumber)
        {
          [self warnWithFormat: @"attempting to get change number"
                @" by synchronising folder..."];
          [(MAPIStoreGCSFolder *) container synchroniseCache];
          changeNumber = [(MAPIStoreGCSFolder *) container
                            changeNumberForMessageWithKey: [self nameInContainer]];
          
          if (changeNumber)
            [self logWithFormat: @"got one"];
          else
            {
              [self errorWithFormat: @"still nothing. We crash!"];
              abort ();
            }
        }
      version = [changeNumber unsignedLongLongValue] >> 16;
    }

  return version;
}

@end
