/* UIxCalendarSelector.m - this file is part of SOGo
 *
 * Copyright (C) 2007 Inverse groupe conseil
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

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>

#import <SOGo/NSDictionary+Utilities.h>
#import <Appointments/SOGoAppointmentFolder.h>
#import <Appointments/SOGoAppointmentFolders.h>

#import "UIxCalendarSelector.h"

// static inline char
// darkenedColor (const char value)
// {
//   char newValue;

//   if (value >= '0' && value <= '9')
//     newValue = ((value - '0') / 2) + '0';
//   else if (value >= 'a' && value <= 'f')
//     newValue = ((value + 10 - 'a') / 2) + '0';
//   else if (value >= 'A' && value <= 'F')
//     newValue = ((value + 10 - 'A') / 2) + '0';
//   else
//     newValue = value;

//   return newValue;
// }

static inline NSString *
colorForNumber (unsigned int number)
{
  unsigned int index, currentValue;
  unsigned char colorTable[] = { 1, 1, 1 };
  NSString *color;

  if (number == 0)
    color = @"#ccf";
  else if (number == NSNotFound)
    color = @"#f00";
  else
    {
      currentValue = number;
      index = 0;
      while (currentValue)
        {
          if (currentValue & 1)
            colorTable[index]++;
          if (index == 3)
            index = 0;
          currentValue >>= 1;
          index++;
        }
      color = [NSString stringWithFormat: @"#%2x%2x%2x",
                        (255 / colorTable[2]) - 1,
                        (255 / colorTable[1]) - 1,
                        (255 / colorTable[0]) - 1];
    }

  return color;
}

@implementation UIxCalendarSelector

- (id) init
{
  if ((self = [super init]))
    {
      calendars = nil;
      currentCalendar = nil;
    }

  return self;
}

- (void) dealloc
{
  [calendars release];
  [currentCalendar release];
  [super dealloc];
}

- (NSArray *) calendars
{
  NSArray *folders;
  SOGoAppointmentFolder *folder;
  NSMutableDictionary *calendar;
  unsigned int count, max;
  NSString *folderId, *folderName;
  NSNumber *isActive;

  if (!calendars)
    {
      folders = [[self clientObject] subFolders];
      max = [folders count];
      calendars = [[NSMutableArray alloc] initWithCapacity: max];
      for (count = 0; count < max; count++)
	{
	  folder = [folders objectAtIndex: count];
	  calendar = [NSMutableDictionary dictionary];
	  folderName = [folder nameInContainer];
	  [calendar setObject:
		      [NSString stringWithFormat: @"/%@", folderName]
		    forKey: @"id"];
	  [calendar setObject: [folder displayName]
		    forKey: @"displayName"];
	  [calendar setObject: folderName forKey: @"folder"];
	  [calendar setObject: colorForNumber (count)
		    forKey: @"color"];
	  isActive = [NSNumber numberWithBool: [folder isActive]];
	  [calendar setObject: isActive forKey: @"active"];
	  [calendars addObject: calendar];
	}
    }

  return calendars;
}

- (void) setCurrentCalendar: (NSDictionary *) newCalendar
{
  ASSIGN (currentCalendar, newCalendar);
}

- (NSDictionary *) currentCalendar
{
  return currentCalendar;
}

- (NSString *) currentCalendarStyle
{
  return [currentCalendar
	   keysWithFormat: @"color: %{color}; background-color: %{color};"];
}

@end /* UIxCalendarSelector */
