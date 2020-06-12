/* SOGoZipArchiver.m - this file is part of SOGo
 *
 * Copyright (C) 2020 Inverse inc.
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

#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSData.h>

#import "SOGoZipArchiver.h"

@implementation SOGoZipArchiver

+ (id)archiverAtPath:(NSString *)file
{
    id newArchiver = [[self alloc] initFromFile: file];
    [newArchiver autorelease];
    return newArchiver;
}

- (id)init
{
    if ((self = [super init])) {
        zip = NULL;
    }
    return self;
}

- (void)dealloc
{
    [self close];
    [super dealloc];
}

- (id)initFromFile:(NSString *)file
{
    id ret;

    ret = nil;
    if (file) {
        if ((self = [self init])) {
            int errorp;
            self->zip = zip_open([file cString], ZIP_CREATE | ZIP_EXCL, &errorp);
            if (self->zip == NULL) {
                zip_error_t ziperror;
                zip_error_init_with_code(&ziperror, errorp);
                NSLog(@"Failed to open zip output file %@: %@", file,
                        [NSString stringWithCString: zip_error_strerror(&ziperror)]);
            } else {
                ret = self;
            }
        }
    }

    return ret;
}

- (BOOL)putFileWithName:(NSString *)filename andData:(NSData *)data
{
    if (self->zip == NULL) {
        NSLog(@"Failed to add file, archive is not open");
        return NO;
    }

    zip_source_t *source = zip_source_buffer(self->zip, [data bytes], [data length], 0);
    if (source == NULL) {
        NSLog(@"Failed to create zip source from buffer: %@", [NSString stringWithCString: zip_strerror(self->zip)]);
        return NO;
    }

    if (zip_file_add(self->zip, [filename UTF8String], source, ZIP_FL_ENC_UTF_8) < 0) {
        NSLog(@"Failed to add file %@: %@", filename, [NSString stringWithCString: zip_strerror(self->zip)]);
        zip_source_free(source);
    }

    return YES;
}

- (BOOL)close
{
    BOOL success = YES;
    if (self->zip != NULL) {
        if (zip_close(zip) != 0) {
            NSLog(@"Failed to close zip archive: %@", [NSString stringWithCString: zip_strerror(self->zip)]);
            zip_discard(self->zip);
            success = NO;
        }
        self->zip = NULL;
    }
    return success;
}

@end
