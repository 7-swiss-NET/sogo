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

#import <SOGo/SOGoProductLoader.h>
#import <SOGo/SOGoSystemDefaults.h>

#import "MAPIApplication.h"
#import "MAPIStoreContext.h"

#undef DEBUG

#include "MAPIStoreSOGo.h"

/**
   \details Initialize sogo mapistore backend

   \return MAPISTORE_SUCCESS on success
*/
static int
sogo_init (void)
{
  NSAutoreleasePool *pool;
  SOGoProductLoader *loader;
  Class MAPIApplicationK;
  SOGoSystemDefaults *sd;
  NSUserDefaults *ud;
  SoProductRegistry *registry;

  pool = [NSAutoreleasePool new];

  /* Here we work around a bug in GNUstep which decodes XML user
     defaults using the system encoding rather than honouring
     the encoding specified in the file. */
  putenv ("GNUSTEP_STRING_ENCODING=NSUTF8StringEncoding");

  sd = [SOGoSystemDefaults sharedSystemDefaults];

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
sogo_create_context(TALLOC_CTX *mem_ctx, const char *uri, void **private_data)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  Class MAPIStoreContextK;
  id context;
  int rc;

  DEBUG(0, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  MAPIStoreContextK = NSClassFromString (@"MAPIStoreContext");
  if (MAPIStoreContextK)
    {
      context = [MAPIStoreContextK contextFromURI: uri
				   inMemCtx: mem_ctx];
      [context retain];

      cContext = talloc_zero(mem_ctx, sogo_context);
      cContext->objcContext = context;

      *private_data = cContext;

      rc = MAPISTORE_SUCCESS;
    }
  else
    rc = MAPISTORE_ERROR;

  [pool release];

  return rc;
}


/**
   \details Delete a connection context from the sogo backend

   \param private_data pointer to the current sogo context

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_delete_context(void *private_data)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;

  pool = [NSAutoreleasePool new];

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  cContext = private_data;
  [cContext->objcContext release];

  [pool release];

  talloc_free (cContext);

  return MAPISTORE_SUCCESS;
}

/**
   \details Delete data associated to a given folder or message

   \param private_data pointer to the current sogo context

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_release_record(void *private_data, uint64_t fmid, uint8_t type)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  pool = [NSAutoreleasePool new];

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context releaseRecordWithFMID: fmid ofTableType: type];

  [context tearDownRequest];

  [pool release];

  return rc;
}


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
sogo_get_path(void *private_data, uint64_t fmid,
	      uint8_t type, char **path)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context getPath: path ofFMID: fmid withTableType: type];

  [context tearDownRequest];

  [pool release];

  return rc;
}

static int
sogo_op_get_fid_by_name(void *private_data, uint64_t parent_fid, const char* foldername, uint64_t *fid)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context getFID: fid byName: foldername inParentFID: parent_fid];

  [context tearDownRequest];
  [pool release];

  return rc;
}


/**
   \details Create a folder in the sogo backend
   
   \param private_data pointer to the current sogo context

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_op_mkdir(void *private_data, uint64_t parent_fid, uint64_t fid,
	      struct SRow *aRow)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context mkDir: aRow withFID: fid inParentFID: parent_fid];

  [context tearDownRequest];
  [pool release];

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
sogo_op_rmdir(void *private_data, uint64_t parent_fid, uint64_t fid)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context rmDirWithFID: fid inParentFID: parent_fid];

  [context tearDownRequest];
  [pool release];

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
sogo_op_opendir(void *private_data, uint64_t parent_fid, uint64_t fid)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context openDir: fid inParentFID: parent_fid];

  [context tearDownRequest];
  [pool release];

  return rc;
}


/**
   \details Close a folder from the sogo backend

   \param private_data pointer to the current sogo context

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_op_closedir(void *private_data)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context closeDir];

  [context tearDownRequest];
  [pool release];

  return rc;
}


/**
   \details Read directory content from the sogo backend

   \param private_data pointer to the current sogo context

   \return MAPISTORE_SUCCESS on success, otherwise MAPISTORE_ERROR
*/
static int
sogo_op_readdir_count(void *private_data, 
		      uint64_t fid,
		      uint8_t table_type,
		      uint32_t *RowCount)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context readCount: RowCount ofTableType: table_type inFID: fid];

  [context tearDownRequest];
  [pool release];

  return rc;
}


static int
sogo_op_get_table_property(void *private_data,
			   uint64_t fid,
			   uint8_t table_type,
			   enum table_query_type query_type,
			   uint32_t pos,
			   uint32_t proptag,
			   void **data)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context getTableProperty: data withTag: proptag atPosition: pos
		   withTableType: table_type andQueryType: query_type
			   inFID: fid];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_openmessage(void *private_data,
		    uint64_t fid,
		    uint64_t mid,
		    struct mapistore_message *msg)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context openMessage: msg withMID: mid inFID: fid];

  [context tearDownRequest];
  [pool release];

  return rc;
}


static int
sogo_op_createmessage(void *private_data,
		      uint64_t fid,
		      uint64_t mid)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context createMessagePropertiesWithMID: mid inFID: fid];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_savechangesmessage(void *private_data,
			   uint64_t mid,
			   uint8_t flags)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context saveChangesInMessageWithMID: mid andFlags: flags];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_submitmessage(void *private_data,
		      uint64_t mid,
		      uint8_t flags)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context submitMessageWithMID: mid andFlags: flags];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_getprops(void *private_data, 
		 uint64_t fmid, 
		 uint8_t type, 
		 struct SPropTagArray *SPropTagArray,
		 struct SRow *aRow)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context getProperties: SPropTagArray
		  ofTableType: type
			inRow: aRow withMID: fmid];

  [context tearDownRequest];
  [pool release];

  return rc;
}


static int
sogo_op_setprops(void *private_data,
		 uint64_t fmid,
		 uint8_t type,
		 struct SRow *aRow)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context setPropertiesWithFMID: fmid ofTableType: type inRow: aRow];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_set_property_from_fd(void *private_data,
			     uint64_t fmid, uint8_t type,
			     uint32_t property, int fd)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  NSFileHandle *fileHandle;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  fileHandle = [[NSFileHandle alloc] initWithFileDescriptor: fd
				     closeOnDealloc: NO];
  rc = [context setProperty: property withFMID: fmid ofTableType: type
		fromFile: fileHandle];
  [fileHandle release];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_get_property_into_fd(void *private_data,
			     uint64_t fmid, uint8_t type,
			     uint32_t property, int fd)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  NSFileHandle *fileHandle;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  fileHandle = [[NSFileHandle alloc] initWithFileDescriptor: fd
				     closeOnDealloc: NO];
  rc = [context getProperty: property withFMID: fmid ofTableType: type
		intoFile: fileHandle];
  [fileHandle release];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_modifyrecipients(void *private_data,
			 uint64_t mid,
			 struct ModifyRecipientRow *rows,
			 uint16_t count)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context modifyRecipientsWithMID: mid
		inRows: rows
		withCount: count];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_deletemessage(void *private_data,
		      uint64_t mid,
		      uint8_t flags)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context deleteMessageWithMID: mid withFlags: flags];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_get_folders_list(void *private_data,
			 uint64_t fmid,
			 struct indexing_folders_list **folders_list)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  [context setupRequest];

  rc = [context getFoldersList: folders_list withFMID: fmid];

  [context tearDownRequest];
  [pool release];

  return rc;
}

static int
sogo_op_set_restrictions (void *private_data, uint64_t fid, uint8_t type,
			  struct mapi_SRestriction *res, uint8_t *tableStatus)
{
  NSAutoreleasePool *pool;
  sogo_context *cContext;
  MAPIStoreContext *context;
  int rc;

  DEBUG (5, ("[SOGo: %s:%d]\n", __FUNCTION__, __LINE__));

  pool = [NSAutoreleasePool new];

  cContext = private_data;
  context = cContext->objcContext;
  if (context)
    {
      [context setupRequest];

      rc = [context setRestrictions: res
		    withFID: fid andTableType: type
		    getTableStatus: tableStatus];

      [context tearDownRequest];
      [pool release];
    }
  else
    {
      NSLog (@"  UNEXPECTED WEIRDNESS: RECEIVED NO CONTEXT");
      rc = MAPI_E_NOT_FOUND;
    }

  return rc;
}

/**
   \details Entry point for mapistore SOGO backend

   \return MAPI_E_SUCCESS on success, otherwise MAPISTORE error
*/
int mapistore_init_backend(void)
{
  struct mapistore_backend	backend;
  int				ret;
  static BOOL registered = NO;

  if (registered)
    {
      ret = MAPISTORE_ERROR;
    }
  else
    {
      registered = YES;
      
      /* Fill in our name */
      backend.name = "SOGo";
      backend.description = "mapistore SOGo backend";
      backend.namespace = "sogo://";

      backend.init = sogo_init;
      backend.create_context = sogo_create_context;
      backend.delete_context = sogo_delete_context;
      backend.release_record = sogo_release_record;

      backend.get_path = sogo_get_path;
      backend.op_get_fid_by_name = sogo_op_get_fid_by_name;

      backend.op_mkdir = sogo_op_mkdir;
      backend.op_rmdir = sogo_op_rmdir;
      backend.op_opendir = sogo_op_opendir;
      backend.op_closedir = sogo_op_closedir;
      backend.op_readdir_count = sogo_op_readdir_count;
      backend.op_get_table_property = sogo_op_get_table_property;
      backend.op_get_folders_list = sogo_op_get_folders_list;
      backend.op_set_restrictions = sogo_op_set_restrictions;
      backend.op_openmessage = sogo_op_openmessage;
      backend.op_createmessage = sogo_op_createmessage;
      backend.op_modifyrecipients = sogo_op_modifyrecipients;
      backend.op_savechangesmessage = sogo_op_savechangesmessage;
      backend.op_submitmessage = sogo_op_submitmessage;
      backend.op_deletemessage = sogo_op_deletemessage;

      backend.op_setprops = sogo_op_setprops;
      backend.op_getprops = sogo_op_getprops;
      backend.op_set_property_from_fd = sogo_op_set_property_from_fd;
      backend.op_get_property_into_fd = sogo_op_get_property_into_fd;

      /* Register ourselves with the MAPISTORE subsystem */
      ret = mapistore_backend_register(&backend);
      if (ret != MAPISTORE_SUCCESS) {
        DEBUG(0, ("Failed to register the '%s' mapistore backend!\n", backend.name));
      }
    }

  return ret;
}
