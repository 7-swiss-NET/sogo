/* MAPIStoreObject.h - this file is part of SOGo
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

#ifndef MAPISTOREOBJECT_H
#define MAPISTOREOBJECT_H

#include <talloc.h>

#import <Foundation/NSObject.h>

@class NSCalendarDate;
@class NSData;
@class NSString;
@class NSMutableArray;
@class NSMutableDictionary;

@class EOQualifier;

@class MAPIStoreFolder;
@class MAPIStoreTable;

@interface MAPIStoreObject : NSObject
{
  const IMP *classGetters;

  uint32_t mapiRetainCount;

  NSMutableArray *parentContainersBag;
  MAPIStoreObject *container;
  id sogoObject;
  NSMutableDictionary *newProperties;
  BOOL isNew;
}

+ (id) mapiStoreObjectWithSOGoObject: (id) newSOGoObject
                         inContainer: (MAPIStoreObject *) newContainer;
+ (int) getAvailableProperties: (struct SPropTagArray **) propertiesP
                      inMemCtx: (TALLOC_CTX *) memCtx;

- (id) initWithSOGoObject: (id) newSOGoObject
              inContainer: (MAPIStoreObject *) newFolder;

/* HACK: MAPI retain count */
- (void) setMAPIRetainCount: (uint32_t) newCount;
- (uint32_t) mapiRetainCount;

- (void) setIsNew: (BOOL) newIsNew;
- (BOOL) isNew;

- (NSString *) nameInContainer;

- (id) sogoObject;
- (MAPIStoreObject *) container;

- (id) context;

- (void) cleanupCaches;

- (uint64_t) objectId;
- (NSString *) url;

- (NSTimeZone *) ownerTimeZone;

/* properties */

- (void) addNewProperties: (NSDictionary *) newNewProperties;
- (NSDictionary *) newProperties;
- (void) resetNewProperties;

/* ops */
- (int) getAvailableProperties: (struct SPropTagArray **) propertiesP
                      inMemCtx: (TALLOC_CTX *) localMemCtx;
- (int) getProperties: (struct mapistore_property_data *) data
             withTags: (enum MAPITAGS *) tags
             andCount: (uint16_t) columnCount
             inMemCtx: (TALLOC_CTX *) localMemCtx;

- (int) setProperties: (struct SRow *) aRow;

- (int) getProperty: (void **) data
            withTag: (enum MAPITAGS) propTag
           inMemCtx: (TALLOC_CTX *) localMemCtx;

/* helper getters */
- (NSData *) getReplicaKeyFromGlobCnt: (uint64_t) objectCnt;
- (int) getReplicaKey: (void **) data
          fromGlobCnt: (uint64_t) objectCnt
             inMemCtx: (TALLOC_CTX *) memCtx;

/* implemented getters */
- (int) getPrDisplayName: (void **) data
                inMemCtx: (TALLOC_CTX *) memCtx;
- (int) getPrSearchKey: (void **) data
              inMemCtx: (TALLOC_CTX *) memCtx;
- (int) getPrGenerateExchangeViews: (void **) data
                          inMemCtx: (TALLOC_CTX *) memCtx;
- (int) getPrParentSourceKey: (void **) data
                    inMemCtx: (TALLOC_CTX *) memCtx;
- (int) getPrSourceKey: (void **) data
              inMemCtx: (TALLOC_CTX *) memCtx;
- (int) getPrChangeKey: (void **) data
              inMemCtx: (TALLOC_CTX *) memCtx;
- (int) getPrCreationTime: (void **) data
                 inMemCtx: (TALLOC_CTX *) memCtx;
- (int) getPrLastModificationTime: (void **) data
                         inMemCtx: (TALLOC_CTX *) memCtx;

/* subclasses */
- (uint64_t) objectVersion;
- (NSDate *) creationTime;
- (NSDate *) lastModificationTime;

@end

#endif /* MAPISTOREOBJECT_H */
