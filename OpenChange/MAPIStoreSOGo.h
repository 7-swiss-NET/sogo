/* MAPIStoreSOGo.h - this file is part of SOGo
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
#ifndef __MAPISTORE_SOGO_H
#define	__MAPISTORE_SOGO_H

#include <mapistore/mapistore.h>
#include <mapistore/mapistore_errors.h>
#include <dlinklist.h>

/* These are essentially local versions of part of the 
   C99 __STDC_FORMAT_MACROS */
#ifndef PRIx64
#if __WORDSIZE == 64
  #define PRIx64        "lx"
#else
  #define PRIx64        "llx"
#endif
#endif

#ifndef PRIX64
#if __WORDSIZE == 64
  #define PRIX64        "lX"
#else
  #define PRIX64        "llX"
#endif
#endif

@class MAPIStoreContext;

typedef struct {
    MAPIStoreContext *objcContext;
} sogo_context;

__BEGIN_DECLS

int	mapistore_init_backend(void);

__END_DECLS

#endif /* !__MAPISTORE_SOGO_H */
