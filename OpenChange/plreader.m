/* plreader.m - this file is part of SOGo
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

/* A format-agnostic property list dumper.
   Usage: plreader [filename] */

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSPropertyList.h>
#import <NGExtensions/NSNull+misc.h>

const char *indentationStep = "  ";

@interface NSObject (plext)

- (void) displayWithIndentation: (NSInteger) anInt;

@end

@implementation NSObject (plext)

- (void) _outputIndentation: (NSInteger) anInt
{
  NSInteger i;

  for (i = 0; i < anInt; i++)
    printf ("%s", indentationStep);
}

- (void) displayWithIndentation: (NSInteger) anInt
{
  [self _outputIndentation: anInt];
  printf ("(%s) %s\n",
          [NSStringFromClass (isa) UTF8String],
          [[self description] UTF8String]);
}

@end

@implementation NSDictionary (plext)

- (void) displayKey: (NSString *) key
    withIndentation: (NSInteger) anInt
{
  [self _outputIndentation: anInt];
  printf ("%s =\n",
          [[key description] UTF8String]);
}

- (void) displayWithIndentation: (NSInteger) anInt
{
  NSUInteger i, max;
  NSArray *keys;
  NSInteger subIndent;
  NSString *key;

  keys = [self allKeys];
  max = [keys count];

  [self _outputIndentation: anInt];
  printf ("{ (%ld) items\n", max);

  subIndent = anInt + 1;

  for (i = 0; i < max; i++)
    {
      key = [keys objectAtIndex: i];
      [self displayKey: key withIndentation: subIndent];
      [[self objectForKey: key] displayWithIndentation: subIndent + 1];
    }

  [self _outputIndentation: anInt];
  printf ("}\n");
}

@end

@implementation NSArray (plext)

- (void) displayCount: (NSUInteger) count
      withIndentation: (NSInteger) anInt
{
  [self _outputIndentation: anInt];
  printf ("%lu =\n", count);
}

- (void) displayWithIndentation: (NSInteger) anInt
{
  NSUInteger i, max;
  NSInteger subIndent;

  max = [self count];

  [self _outputIndentation: anInt];
  printf ("[ (%ld) items\n", max);

  subIndent = anInt + 1;

  for (i = 0; i < max; i++)
    {
      [self displayCount: i withIndentation: subIndent];
      [[self objectAtIndex: i] displayWithIndentation: subIndent + 1];
    }

  [self _outputIndentation: anInt];
  printf ("]\n");
}

@end

static void
PLReaderDumpPListFile (NSString *filename)
{
  NSData *content;
  NSDictionary *d;
  NSPropertyListFormat format;
  NSString *error = nil;
  const char *formatName;

  content = [NSData dataWithContentsOfFile: filename];
  d = [NSPropertyListSerialization propertyListFromData: content
                                       mutabilityOption: NSPropertyListImmutable
                                                 format: &format
                                       errorDescription: &error];
  if (error)
    printf ("an error occurred: %s\n", [error UTF8String]);
  else
    {
      switch (format)
        {
        case  NSPropertyListOpenStepFormat:
          formatName = "OpenStep";
          break;
        case NSPropertyListXMLFormat_v1_0:
          formatName = "XML";
          break;
        case NSPropertyListBinaryFormat_v1_0:
          formatName = "Binary";
          break;
        case NSPropertyListGNUstepFormat:
          formatName = "GNUstep";
          break;
        case NSPropertyListGNUstepBinaryFormat:
          formatName = "GNUstep binary";
          break;
        default: formatName = "unknown";
        }

      printf ("File format is: %s\n", formatName);
      [d displayWithIndentation: 0];
    }
}

int main()
{
  NSAutoreleasePool *p;
  NSProcessInfo *pi;
  NSArray *arguments;

  p = [NSAutoreleasePool new];
  pi = [NSProcessInfo processInfo];
  arguments = [pi arguments];
  if ([arguments count] > 1)
    PLReaderDumpPListFile ([arguments objectAtIndex: 1]);
  [p release];

  return 0;
}
