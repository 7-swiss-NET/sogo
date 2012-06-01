/* MAPIStoreEmbeddedMessage.m - this file is part of SOGo
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

#import <Foundation/NSString.h>

#import "MAPIStoreAttachment.h"

#import "MAPIStoreEmbeddedMessage.h"

static Class MAPIStoreAttachmentK;

@implementation MAPIStoreEmbeddedMessage

+ (void) initialize
{
  MAPIStoreAttachmentK = [MAPIStoreAttachment class];
}

+ (id) embeddedMessageWithAttachment: (id) newAttachment
{
  MAPIStoreEmbeddedMessage *newMessage;

  newMessage = [[self alloc] initWithAttachment: newAttachment];
  [newMessage autorelease];

  return newMessage;
}

- (id) initWithAttachment: (id) newAttachment
{
  if ((self = [self init]))
    {
      if ([newAttachment isKindOfClass: MAPIStoreAttachmentK])
        ASSIGN (container, newAttachment);
    }

  return self;
}

- (NSString *) nameInContainer
{
  return @"as-message";
}

@end
