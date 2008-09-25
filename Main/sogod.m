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

#import <unistd.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSUserDefaults.h>

#import <NGObjWeb/SoApplication.h>

#if defined(LDAP_CONFIG)
#import <SOGo/SOGoLDAPUserDefaults.h>
#endif

int
main (int argc, char **argv, char **env)
{
  NSString *tzName;
  NSUserDefaults *ud;
  NSAutoreleasePool *pool;
  int rc;

  pool = [NSAutoreleasePool new];

#if defined(LDAP_CONFIG)
  [SOGoLDAPUserDefaults poseAsClass: [NSUserDefaults class]];
#endif

  rc = -1;

  if (getuid() > 0)
    {
#if LIB_FOUNDATION_LIBRARY
      [NSProcessInfo initializeWithArguments: argv
		     count: argc environment: env];
#endif
      ud = [NSUserDefaults standardUserDefaults];
      rc = 0;
      tzName = [ud stringForKey: @"SOGoServerTimeZone"];
      if (!tzName)
	tzName = @"UTC";
      [NSTimeZone setDefaultTimeZone:
		    [NSTimeZone timeZoneWithName: tzName]];
      WOWatchDogApplicationMain (@"SOGo", argc, (void *) argv);
    }
  else
    NSLog (@"Don't run SOGo as root!");

  [pool release];

  return rc;
}
