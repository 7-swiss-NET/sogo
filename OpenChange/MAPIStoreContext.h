/* MAPIStoreContext.h - this file is part of SOGo
 *
 * Copyright (C) 2010 Inverse inc. 
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

#ifndef MAPISTORECONTEXT_H
#define MAPISTORECONTEXT_H

#import <Foundation/NSObject.h>

#define SENSITIVITY_NONE 0
#define SENSITIVITY_PERSONAL 1
#define SENSITIVITY_PRIVATE 2
#define SENSITIVITY_COMPANY_CONFIDENTIAL 3

#define TBL_LEAF_ROW 0x00000001
#define TBL_EMPTY_CATEGORY 0x00000002
#define TBL_EXPANDED_CATEGORY 0x00000003
#define TBL_COLLAPSED_CATEGORY 0x00000004

@class NSArray;
@class NSFileHandle;
@class NSMutableArray;
@class NSMutableDictionary;
@class NSString;

@class EOQualifier;

@class WOContext;

@class SOGoFolder;
@class SOGoObject;

@class MAPIStoreAuthenticator;
@class MAPIStoreMapping;

typedef enum {
  MAPIRestrictionStateAlwaysFalse = NO,
  MAPIRestrictionStateAlwaysTrue = YES,
  MAPIRestrictionStateNeedsEval,    /* needs passing of qualifier to underlying
				       database */
} MAPIRestrictionState;

@interface MAPIStoreContext : NSObject
{
  struct mapistore_context *memCtx;
  void *ldbCtx;

  BOOL baseContextSet;

  NSString *uri;

  NSMutableArray *parentFoldersBag;

  NSMutableDictionary *objectCache;
  NSMutableDictionary *messages;
  MAPIStoreAuthenticator *authenticator;
  WOContext *woContext;
  NSMutableDictionary *messageCache;
  NSMutableDictionary *subfolderCache;
  id moduleFolder;

  NSMutableDictionary *restrictedMessageCache;
  MAPIRestrictionState restrictionState;
  EOQualifier *restriction;
}

+ (id) contextFromURI: (const char *) newUri
             inMemCtx: (struct mapistore_context *) newMemCtx;

- (void) setURI: (NSString *) newUri
      andMemCtx: (struct mapistore_context *) newMemCtx;

- (void) setupModuleFolder;

- (void) setAuthenticator: (MAPIStoreAuthenticator *) newAuthenticator;
- (MAPIStoreAuthenticator *) authenticator;

- (void) setupRequest;
- (void) tearDownRequest;

- (id) lookupObject: (NSString *) objectURLString;

/* backend methods */
- (int) getPath: (char **) path
         ofFMID: (uint64_t) fmid
  withTableType: (uint8_t) tableType;

- (int) getFID: (uint64_t *) fid
        byName: (const char *) foldername
   inParentFID: (uint64_t) parent_fid;

- (int) setRestrictions: (struct mapi_SRestriction *) res
		withFID: (uint64_t) fid
	   andTableType: (uint8_t) type
	 getTableStatus: (uint8_t *) tableStatus;

- (enum MAPISTATUS) getTableProperty: (void **) data
			     withTag: (enum MAPITAGS) proptag
			  atPosition: (uint32_t) pos
		       withTableType: (uint8_t) tableType
			andQueryType: (enum table_query_type) queryType
			       inFID: (uint64_t) fid;

- (int) mkDir: (struct SRow *) aRow
      withFID: (uint64_t) fid
  inParentFID: (uint64_t) parentFID;
- (int) rmDirWithFID: (uint64_t) fid
         inParentFID: (uint64_t) parentFid;
- (int) openDir: (uint64_t) fid
    inParentFID: (uint64_t) parentFID;
- (int) closeDir;
- (int) readCount: (uint32_t *) rowCount
      ofTableType: (uint8_t) tableType
            inFID: (uint64_t) fid;
- (int) openMessage: (struct mapistore_message *) msg
            withMID: (uint64_t) mid
              inFID: (uint64_t) fid;
- (int) createMessagePropertiesWithMID: (uint64_t) mid
                                 inFID: (uint64_t) fid;
- (int) saveChangesInMessageWithMID: (uint64_t) mid
                           andFlags: (uint8_t) flags;
- (int) submitMessageWithMID: (uint64_t) mid
                    andFlags: (uint8_t) flags;
- (int) getProperties: (struct SPropTagArray *) SPropTagArray
          ofTableType: (uint8_t) tableType
                inRow: (struct SRow *) aRow
              withMID: (uint64_t) fmid;
- (int) setPropertiesWithFMID: (uint64_t) fmid
                  ofTableType: (uint8_t) tableType
                        inRow: (struct SRow *) aRow;
- (int) setProperty: (enum MAPITAGS) property
	   withFMID: (uint64_t) fmid
	ofTableType: (uint8_t) tableType
	   fromFile: (NSFileHandle *) aFile;
- (int) getProperty: (enum MAPITAGS) property
	   withFMID: (uint64_t) fmid
	ofTableType: (uint8_t) tableType
	   intoFile: (NSFileHandle *) aFile;
- (int) modifyRecipientsWithMID: (uint64_t) mid
			 inRows: (struct ModifyRecipientRow *) rows
		      withCount: (NSUInteger) max;
- (int) deleteMessageWithMID: (uint64_t) mid
                   withFlags: (uint8_t) flags;
- (int) releaseRecordWithFMID: (uint64_t) fmid
		  ofTableType: (uint8_t) tableType;


/* util methods */
- (void) registerValue: (id) value
	    asProperty: (enum MAPITAGS) property
		forURL: (NSString *) url;


/* restrictions */

- (MAPIRestrictionState) evaluateRestriction: (struct mapi_SRestriction *) res
			       intoQualifier: (EOQualifier **) qualifier;
- (MAPIRestrictionState) evaluateNotRestriction: (struct mapi_SNotRestriction *) res
				  intoQualifier: (EOQualifier **) qualifierPtr;
- (MAPIRestrictionState) evaluateAndRestriction: (struct mapi_SAndRestriction *) res
				  intoQualifier: (EOQualifier **) qualifierPtr;
- (MAPIRestrictionState) evaluateOrRestriction: (struct mapi_SOrRestriction *) res
				 intoQualifier: (EOQualifier **) qualifierPtr;

/* subclass methods */
+ (NSString *) MAPIModuleName;
+ (void) registerFixedMappings: (MAPIStoreMapping *) storeMapping;

- (NSArray *) getFolderMessageKeys: (SOGoFolder *) folder
		 matchingQualifier: (EOQualifier *) qualifier;

- (enum MAPISTATUS) getCommonTableChildproperty: (void **) data
					  atURL: (NSString *) childURL
					withTag: (enum MAPITAGS) proptag
				       inFolder: (SOGoFolder *) folder
					withFID: (uint64_t) fid;

- (enum MAPISTATUS) getMessageTableChildproperty: (void **) data
					   atURL: (NSString *) childURL
					 withTag: (enum MAPITAGS) proptag
					inFolder: (SOGoFolder *) folder
					 withFID: (uint64_t) fid;

- (enum MAPISTATUS) getFolderTableChildproperty: (void **) data
					  atURL: (NSString *) childURL
					withTag: (enum MAPITAGS) proptag
				       inFolder: (SOGoFolder *) folder
					withFID: (uint64_t) fid;

- (int) getFoldersList: (struct indexing_folders_list **) folders_list
              withFMID: (uint64_t) fmid;

- (int) openMessage: (struct mapistore_message *) msg
              atURL: (NSString *) childURL;

- (int) getMessageProperties: (struct SPropTagArray *) sPropTagArray
                       inRow: (struct SRow *) aRow
                       atURL: (NSString *) childURL;

- (NSString *) backendIdentifierForProperty: (enum MAPITAGS) property;

/* restrictions */
- (MAPIRestrictionState) evaluateContentRestriction: (struct mapi_SContentRestriction *) res
				      intoQualifier: (EOQualifier **) qualifier;
- (MAPIRestrictionState) evaluatePropertyRestriction: (struct mapi_SPropertyRestriction *) res
				       intoQualifier: (EOQualifier **) qualifier;
- (MAPIRestrictionState) evaluateBitmaskRestriction: (struct mapi_SBitmaskRestriction *) res
				      intoQualifier: (EOQualifier **) qualifier;
- (MAPIRestrictionState) evaluateExistRestriction: (struct mapi_SExistRestriction *) res
				    intoQualifier: (EOQualifier **) qualifier;

@end

#endif /* MAPISTORECONTEXT_H */
