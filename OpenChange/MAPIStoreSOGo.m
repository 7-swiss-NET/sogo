/* MAPIStoreSOGo.m - this file is part of SOGo
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

/* OpenChange SOGo storage backend */

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSUserDefaults.h>
#import <NGObjWeb/SoProductRegistry.h>
#import <NGExtensions/NSObject+Logs.h>
#import <SOGo/SOGoCache.h>
#import <SOGo/SOGoProductLoader.h>
#import <SOGo/SOGoSystemDefaults.h>

#import "MAPIApplication.h"
#import "MAPIStoreAttachment.h"
#import "MAPIStoreContext.h"
#import "MAPIStoreDraftsMessage.h"
#import "MAPIStoreFolder.h"
#import "MAPIStoreMessage.h"
#import "MAPIStoreObject.h"
#import "MAPIStoreTable.h"
#import "NSObject+MAPIStore.h"

#undef DEBUG
#include <stdbool.h>
#include <talloc.h>
#include <gen_ndr/exchange.h>
#include <mapistore/mapistore.h>
#include <mapistore/mapistore_errors.h>

/**
   \details Initialize sogo mapistore backend

   \return MAPISTORE_SUCCESS on success
*/
static int
sogo_backend_init (void)
{
  NSAutoreleasePool *pool;
  SOGoProductLoader *loader;
  Class MAPIApplicationK;
  NSUserDefaults *ud;
  SoProductRegistry *registry;

  pool = [NSAutoreleasePool new];

  /* Here we work around a bug in GNUstep which decodes XML user
     defaults using the system encoding rather than honouring
     the encoding specified in the file. */
  putenv ("GNUSTEP_STRING_ENCODING=NSUTF8StringEncoding");

  [SOGoSystemDefaults sharedSystemDefaults];

  // /* We force the plugin to base its configuration on the SOGo tree. */
  ud = [NSUserDefaults standardUserDefaults];
  [ud registerDefaults: [ud persistentDomainForName: @"sogod"]];

  registry = [SoProductRegistry sharedProductRegistry];
  [registry scanForProductsInDirectory: SOGO_BUNDLES_DIR];

  loader = [SOGoProductLoader productLoader];
  [loader loadProducts: [NSArray arrayWithObject: BACKEND_BUNDLE_NAME]];

  MAPIApplicationK = NSClassFromString (@"MAPIApplication");
  if (MAPIApplicationK)
    [MAPIApplicationK new];

  [[SOGoCache sharedCache] disableRequestsCache];

  [pool release];

  return MAPISTORE_SUCCESS;
}

/**
   \details Create a connection context to the sogo backend

   \param mem_ctx pointer to the memory context
   \param uri pointer to the sogo path
   \param private_data pointer to the private backend context 
*/

static int
sogo_backend_create_context(TALLOC_CTX *mem_ctx,
                            struct mapistore_connection_info *conn_info,
                            const char *uri, void **context_object)
{
  NSAutoreleasePool *pool;
  Class MAPIStoreContextK;
  MAPIStoreContext *context;
  int rc;

  DEBUG(0, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  MAPIStoreContextK = NSClassFromString (@"MAPIStoreContext");
  if (MAPIStoreContextK)
    {
      rc = [MAPIStoreContextK openContext: &context
                                  withURI: uri
                        andConnectionInfo: conn_info];
      if (rc == MAPISTORE_SUCCESS)
        *context_object = [context tallocWrapper: mem_ctx];
    }
  else
    rc = MAPISTORE_ERROR;

  [pool release];

  return rc;
}

// andFID: fid
// uint64_t fid,
//   void **private_data)

/**
   \details return the mapistore path associated to a given message or
   folder ID

   \param private_data pointer to the current sogo context
   \param fmid the folder/message ID to lookup
   \param type whether it is a folder or message
   \param path pointer on pointer to the path to return

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE error
*/
static int
sogo_context_get_path(void *backend_object, TALLOC_CTX *mem_ctx,
                      uint64_t fmid, char **path)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (backend_object)
    {
      wrapper = backend_object;
      context = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [context getPath: path ofFMID: fmid inMemCtx: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_context_get_root_folder(void *backend_object, TALLOC_CTX *mem_ctx,
                             uint64_t fid, void **folder_object)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreContext *context;
  MAPIStoreFolder *folder;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (backend_object)
    {
      wrapper = backend_object;
      context = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [context getRootFolder: &folder withFID: fid];
      if (rc == MAPISTORE_SUCCESS)
        *folder_object = [folder tallocWrapper: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

/**
   \details Open a folder from the sogo backend

   \param private_data pointer to the current sogo context
   \param parent_fid the parent folder identifier
   \param fid the identifier of the colder to open

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_folder_open_folder(void *folder_object, TALLOC_CTX *mem_ctx, uint64_t fid, void **childfolder_object)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder, *childFolder;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder openFolder: &childFolder withFID: fid];
      if (rc == MAPISTORE_SUCCESS)
        *childfolder_object = [childFolder tallocWrapper: mem_ctx];
      // [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

/**
   \details Create a folder in the sogo backend
   
   \param private_data pointer to the current sogo context

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_folder_create_folder(void *folder_object, TALLOC_CTX *mem_ctx,
                          uint64_t fid, struct SRow *aRow,
                          void **childfolder_object)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder, *childFolder;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder createFolder: &childFolder withRow: aRow andFID: fid];
      if (rc == MAPISTORE_SUCCESS)
        *childfolder_object = [childFolder tallocWrapper: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

/**
   \details Delete a folder from the sogo backend

   \param private_data pointer to the current sogo context
   \param parent_fid the FID for the parent of the folder to delete
   \param fid the FID for the folder to delete

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_folder_delete_folder(void *folder_object, uint64_t fid)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder deleteFolderWithFID: fid];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_folder_get_child_count(void *folder_object, uint8_t table_type, uint32_t *child_count)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder getChildCount: child_count ofTableType: table_type];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_folder_open_message(void *folder_object,
                         TALLOC_CTX *mem_ctx,
                         uint64_t mid,
                         void **message_object,
                         struct mapistore_message **msgp)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder;
  MAPIStoreMessage *message;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder openMessage: &message andMessageData: msgp withMID: mid inMemCtx: mem_ctx];
      if (rc == MAPISTORE_SUCCESS)
        *message_object = [message tallocWrapper: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_folder_create_message(void *folder_object,
                           TALLOC_CTX *mem_ctx,
                           uint64_t mid,
                           uint8_t associated,
                           void **message_object)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder;
  MAPIStoreMessage *message;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder createMessage: &message
                         withMID: mid isAssociated: associated];
      if (rc == MAPISTORE_SUCCESS)
        *message_object = [message tallocWrapper: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_folder_delete_message(void *folder_object, uint64_t mid, uint8_t flags)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder deleteMessageWithMID: mid andFlags: flags];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_folder_open_table(void *folder_object, TALLOC_CTX *mem_ctx,
                       uint8_t table_type, uint32_t handle_id,
                       void **table_object, uint32_t *row_count)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreFolder *folder;
  MAPIStoreTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (folder_object)
    {
      wrapper = folder_object;
      folder = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [folder getTable: &table
                andRowCount: row_count
                  tableType: table_type
                andHandleId: handle_id];
      if (rc == MAPISTORE_SUCCESS)
        *table_object = [table tallocWrapper: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_message_create_attachment (void *message_object, TALLOC_CTX *mem_ctx, void **attachment_object, uint32_t *aidp)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreMessage *message;
  MAPIStoreAttachment *attachment;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (message_object)
    {
      wrapper = message_object;
      message = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [message createAttachment: &attachment inAID: aidp];
      if (rc == MAPISTORE_SUCCESS)
        *attachment_object = [attachment tallocWrapper: mem_ctx];
      // [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_message_open_attachment (void *message_object, TALLOC_CTX *mem_ctx,
                              uint32_t aid, void **attachment_object)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreMessage *message;
  MAPIStoreAttachment *attachment;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (message_object)
    {
      wrapper = message_object;
      message = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [message getAttachment: &attachment withAID: aid];
      if (rc == MAPISTORE_SUCCESS)
        *attachment_object = [attachment tallocWrapper: mem_ctx];
      // [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_message_get_attachment_table (void *message_object, TALLOC_CTX *mem_ctx, void **table_object, uint32_t *row_count)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreMessage *message;
  MAPIStoreAttachmentTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (message_object)
    {
      wrapper = message_object;
      message = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [message getAttachmentTable: &table
                           andRowCount: row_count];
      if (rc == MAPISTORE_SUCCESS)
        *table_object = [table tallocWrapper: mem_ctx];
      // [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_message_modify_recipients (void *message_object,
                                struct ModifyRecipientRow *recipients,
                                uint16_t count)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreMessage *message;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (message_object)
    {
      wrapper = message_object;
      message = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [message modifyRecipientsWithRows: recipients andCount: count];
      // [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_message_save (void *message_object)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreMessage *message;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (message_object)
    {
      wrapper = message_object;
      message = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [message saveMessage];
      // [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_message_submit (void *message_object, enum SubmitFlags flags)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreDraftsMessage *message;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (message_object)
    {
      wrapper = message_object;
      message = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [message submitWithFlags: flags];
      // [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO OBJECT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_message_attachment_open_embedded_message
(void *attachment_object,
 TALLOC_CTX *mem_ctx, void **message_object,
 uint64_t *midP,
 struct mapistore_message **msg)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreAttachment *attachment;
  MAPIStoreAttachmentMessage *message;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  if (attachment_object)
    {
      wrapper = attachment_object;
      attachment = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [attachment openEmbeddedMessage: &message
                                   withMID: midP
                          withMAPIStoreMsg: msg
                                  inMemCtx: mem_ctx];
      if (rc == MAPISTORE_SUCCESS)
        *message_object = [message tallocWrapper: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO CONTEXT");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int sogo_table_get_available_properties(void *table_object,
                                               TALLOC_CTX *mem_ctx, struct SPropTagArray **propertiesP)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (table_object)
    {
      wrapper = table_object;
      table = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [table getAvailableProperties: propertiesP inMemCtx: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_table_set_columns (void *table_object, uint16_t count, enum MAPITAGS *properties)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (table_object)
    {
      wrapper = table_object;
      table = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [table setColumns: properties
                   withCount: count];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_table_set_restrictions (void *table_object, struct mapi_SRestriction *restrictions, uint8_t *table_status)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (table_object)
    {
      wrapper = table_object;
      table = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      [table setRestrictions: restrictions];
      [table cleanupCaches];
      rc = MAPISTORE_SUCCESS;
      *table_status = TBLSTAT_COMPLETE;
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_table_set_sort_order (void *table_object, struct SSortOrderSet *sort_order, uint8_t *table_status)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (table_object)
    {
      wrapper = table_object;
      table = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      [table setSortOrder: sort_order];
      [table cleanupCaches];
      rc = MAPISTORE_SUCCESS;
      *table_status = TBLSTAT_COMPLETE;
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_table_get_row (void *table_object, TALLOC_CTX *mem_ctx,
                    enum table_query_type query_type, uint32_t row_id,
                    struct mapistore_property_data **data)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (table_object)
    {
      wrapper = table_object;
      table = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [table getRow: data withRowID: row_id andQueryType: query_type
                inMemCtx: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_table_get_row_count (void *table_object,
                          enum table_query_type query_type,
                          uint32_t *row_countp)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreTable *table;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (table_object)
    {
      wrapper = table_object;
      table = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [table getRowCount: row_countp
                withQueryType: query_type];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int sogo_properties_get_available_properties(void *object,
                                                    TALLOC_CTX *mem_ctx,
                                                    struct SPropTagArray **propertiesP)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreObject *propObject;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (object)
    {
      wrapper = object;
      propObject = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [propObject getAvailableProperties: propertiesP inMemCtx: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_properties_get_properties (void *object,
                                TALLOC_CTX *mem_ctx,
                                uint16_t count, enum MAPITAGS *properties,
                                struct mapistore_property_data *data)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreObject *propObject;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (object)
    {
      wrapper = object;
      propObject = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [propObject getProperties: data withTags: properties
                            andCount: count
                            inMemCtx: mem_ctx];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO DATA");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

static int
sogo_properties_set_properties (void *object, struct SRow *aRow)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;
  MAPIStoreObject *propObject;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  if (object)
    {
      wrapper = object;
      propObject = wrapper->MAPIStoreSOGoObject;
      pool = [NSAutoreleasePool new];
      rc = [propObject setProperties: aRow];
      [pool release];
    }
  else
    {
      NSLog (@"  bad object pointer");
      rc = MAPISTORE_SUCCESS;
    }

  return rc;
}

/**
   \details Entry point for mapistore SOGO backend

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE error
*/
int mapistore_init_backend(void)
{
  struct mapistore_backend	backend;
  int				ret;
  static BOOL                   registered = NO;

  if (registered)
    ret = MAPISTORE_SUCCESS;
  else
    {
      registered = YES;

      /* Fill in our name */
      backend.backend.name = "SOGo";
      backend.backend.description = "mapistore SOGo backend";
      backend.backend.namespace = "sogo://";
      backend.backend.init = sogo_backend_init;
      backend.backend.create_context = sogo_backend_create_context;
      backend.context.get_path = sogo_context_get_path;
      backend.context.get_root_folder = sogo_context_get_root_folder;
      backend.folder.open_folder = sogo_folder_open_folder;
      backend.folder.create_folder = sogo_folder_create_folder;
      backend.folder.delete_folder = sogo_folder_delete_folder;
      backend.folder.open_message = sogo_folder_open_message;
      backend.folder.create_message = sogo_folder_create_message;
      backend.folder.delete_message = sogo_folder_delete_message;
      backend.folder.get_child_count = sogo_folder_get_child_count;
      backend.folder.open_table = sogo_folder_open_table;
      backend.message.create_attachment = sogo_message_create_attachment;
      backend.message.get_attachment_table = sogo_message_get_attachment_table;
      backend.message.open_attachment = sogo_message_open_attachment;
      backend.message.open_embedded_message = sogo_message_attachment_open_embedded_message;
      backend.message.modify_recipients = sogo_message_modify_recipients;
      backend.message.save = sogo_message_save;
      backend.message.submit = sogo_message_submit;
      backend.table.get_available_properties = sogo_table_get_available_properties;
      backend.table.set_restrictions = sogo_table_set_restrictions;
      backend.table.set_sort_order = sogo_table_set_sort_order;
      backend.table.set_columns = sogo_table_set_columns;
      backend.table.get_row = sogo_table_get_row;
      backend.table.get_row_count = sogo_table_get_row_count;
      backend.properties.get_available_properties = sogo_properties_get_available_properties;
      backend.properties.get_properties = sogo_properties_get_properties;
      backend.properties.set_properties = sogo_properties_set_properties;

      /* Register ourselves with the MAPISTORE subsystem */
      ret = mapistore_backend_register(&backend);
      if (ret != MAPISTORE_SUCCESS) {
        DEBUG(0, ("Failed to register the '%s' mapistore backend!\n", backend.backend.name));
      }
    }

  return ret;
}
