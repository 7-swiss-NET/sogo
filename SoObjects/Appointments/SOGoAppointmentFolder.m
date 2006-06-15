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

#include "SOGoAppointmentFolder.h"
#include <SOGo/SOGoCustomGroupFolder.h>
#include <SOGo/SOGoAppointment.h>
#include <SOGo/AgenorUserManager.h>
#include <GDLContentStore/GCSFolder.h>
#include <SaxObjC/SaxObjC.h>
#include <NGiCal/NGiCal.h>
#include <NGExtensions/NGCalendarDateRange.h>
#include "common.h"

#if APPLE_Foundation_LIBRARY || NeXT_Foundation_LIBRARY
@interface NSDate(UsedPrivates)
- (id)initWithTimeIntervalSince1970:(NSTimeInterval)_interval;
@end
#endif

@implementation SOGoAppointmentFolder

static NGLogger   *logger    = nil;
static NSTimeZone *MET       = nil;
static NSNumber   *sharedYes = nil;

+ (int)version {
  return [super version] + 1 /* v1 */;
}
+ (void)initialize {
  NGLoggerManager *lm;
  static BOOL     didInit = NO;

  if (didInit) return;
  didInit = YES;
  
  NSAssert2([super version] == 0,
            @"invalid superclass (%@) version %i !",
            NSStringFromClass([self superclass]), [super version]);

  lm      = [NGLoggerManager defaultLoggerManager];
  logger  = [lm loggerForDefaultKey:@"SOGoAppointmentFolderDebugEnabled"];

  MET       = [[NSTimeZone timeZoneWithAbbreviation:@"MET"] retain];
  sharedYes = [[NSNumber numberWithBool:YES] retain];
}

- (void)dealloc {
  [self->uidToFilename release];
  [super dealloc];
}


/* logging */

- (id)debugLogger {
  return logger;
}

/* selection */

- (NSArray *)calendarUIDs {
  /* this is used for group calendars (this folder just returns itself) */
  NSString *s;
  
  s = [[self container] nameInContainer];
  return [s isNotNull] ? [NSArray arrayWithObjects:&s count:1] : nil;
}

/* name lookup */

- (BOOL)isValidAppointmentName:(NSString *)_key {
  if ([_key length] == 0)
    return NO;
  
  return YES;
}

- (id)appointmentWithName:(NSString *)_key inContext:(id)_ctx {
  static Class aptClass = Nil;
  id apt;
  
  if (aptClass == Nil)
    aptClass = NSClassFromString(@"SOGoAppointmentObject");
  if (aptClass == Nil) {
    [self errorWithFormat:@"missing SOGoAppointmentObject class!"];
    return nil;
  }
  
  apt = [[aptClass alloc] initWithName:_key inContainer:self];
  return [apt autorelease];
}

- (id)lookupName:(NSString *)_key inContext:(id)_ctx acquire:(BOOL)_flag {
  id obj;
  
  /* first check attributes directly bound to the application */
  if ((obj = [super lookupName:_key inContext:_ctx acquire:NO]))
    return obj;
  
  if ([self isValidAppointmentName:_key])
    return [self appointmentWithName:_key inContext:_ctx];
  
  /* return 404 to stop acquisition */
  return [NSException exceptionWithHTTPStatus:404 /* Not Found */];
}

/* timezone */

- (NSTimeZone *)viewTimeZone {
  // TODO: should use a cookie for configuration? we default to MET
  return MET;
}

/* vevent UID handling */

- (NSString *)resourceNameForEventUID:(NSString *)_u inFolder:(GCSFolder *)_f {
  static NSArray *nameFields = nil;
  EOQualifier *qualifier;
  NSArray     *records;
  
  if (![_u isNotNull]) return nil;
  if (_f == nil) {
    [self errorWithFormat:@"(%s): missing folder for fetch!",
	    __PRETTY_FUNCTION__];
    return nil;
  }
  
  if (nameFields == nil)
    nameFields = [[NSArray alloc] initWithObjects:@"c_name", nil];
  
  qualifier = [EOQualifier qualifierWithQualifierFormat:@"uid = %@", _u];
  records   = [_f fetchFields:nameFields matchingQualifier:qualifier];
  
  if ([records count] == 1)
    return [[records objectAtIndex:0] valueForKey:@"c_name"];
  if ([records count] == 0)
    return nil;
  
  [self errorWithFormat:
	  @"The storage contains more than file with the same UID!"];
  return [[records objectAtIndex:0] valueForKey:@"c_name"];
}

- (NSString *)resourceNameForEventUID:(NSString *)_uid {
  /* caches UIDs */
  GCSFolder *folder;
  NSString  *rname;
  
  if (![_uid isNotNull])
    return nil;
  if ((rname = [self->uidToFilename objectForKey:_uid]) != nil)
    return [rname isNotNull] ? rname : nil;
  
  if ((folder = [self ocsFolder]) == nil) {
    [self errorWithFormat:@"(%s): missing folder for fetch!",
      __PRETTY_FUNCTION__];
    return nil;
  }

  if (self->uidToFilename == nil)
    self->uidToFilename = [[NSMutableDictionary alloc] initWithCapacity:16];
  
  if ((rname = [self resourceNameForEventUID:_uid inFolder:folder]) == nil)
    [self->uidToFilename setObject:[NSNull null] forKey:_uid];
  else
    [self->uidToFilename setObject:rname forKey:_uid];
  
  return rname;
}

/* fetching */

- (NSMutableDictionary *)fixupRecord:(NSDictionary *)_record
  fetchRange:(NGCalendarDateRange *)_r
{
  NSMutableDictionary *md;
  id tmp;
  
  md = [[_record mutableCopy] autorelease];
 
  if ((tmp = [_record objectForKey:@"startdate"])) {
    tmp = [[NSCalendarDate alloc] initWithTimeIntervalSince1970:
          (NSTimeInterval)[tmp unsignedIntValue]];
    [tmp setTimeZone:[self viewTimeZone]];
    if (tmp) [md setObject:tmp forKey:@"startDate"];
    [tmp release];
  }
  else
    [self logWithFormat:@"missing 'startdate' in record?"];

  if ((tmp = [_record objectForKey:@"enddate"])) {
    tmp = [[NSCalendarDate alloc] initWithTimeIntervalSince1970:
          (NSTimeInterval)[tmp unsignedIntValue]];
    [tmp setTimeZone:[self viewTimeZone]];
    if (tmp) [md setObject:tmp forKey:@"endDate"];
    [tmp release];
  }
  else
    [self logWithFormat:@"missing 'enddate' in record?"];

  return md;
}

- (NSMutableDictionary *)fixupCycleRecord:(NSDictionary *)_record
  cycleRange:(NGCalendarDateRange *)_r
{
  NSMutableDictionary *md;
  id tmp;
  
  md = [[_record mutableCopy] autorelease];
  
  /* cycle is in _r */
  tmp = [_r startDate];
  [tmp setTimeZone:[self viewTimeZone]];
  [md setObject:tmp forKey:@"startDate"];
  tmp = [_r endDate];
  [tmp setTimeZone:[self viewTimeZone]];
  [md setObject:tmp forKey:@"endDate"];
  
  return md;
}

- (void)_flattenCycleRecord:(NSDictionary *)_row
  forRange:(NGCalendarDateRange *)_r
  intoArray:(NSMutableArray *)_ma
{
  NSMutableDictionary *row;
  NSDictionary        *cycleinfo;
  NSCalendarDate      *startDate, *endDate;
  NGCalendarDateRange *fir;
  NSArray             *rules, *exRules, *exDates, *ranges;
  unsigned            i, count;

  cycleinfo  = [[_row objectForKey:@"cycleinfo"] propertyList];
  if (cycleinfo == nil) {
    [self errorWithFormat:@"cyclic record doesn't have cycleinfo -> %@", _row];
    return;
  }

  row = [self fixupRecord:_row fetchRange:_r];
  [row removeObjectForKey:@"cycleinfo"];
  [row setObject:sharedYes forKey:@"isRecurrentEvent"];

  startDate = [row objectForKey:@"startDate"];
  endDate   = [row objectForKey:@"endDate"];
  fir       = [NGCalendarDateRange calendarDateRangeWithStartDate:startDate
                                   endDate:endDate];
  rules     = [cycleinfo objectForKey:@"rules"];
  exRules   = [cycleinfo objectForKey:@"exRules"];
  exDates   = [cycleinfo objectForKey:@"exDates"];

  ranges = [iCalRecurrenceCalculator recurrenceRangesWithinCalendarDateRange:_r
                                     firstInstanceCalendarDateRange:fir
                                     recurrenceRules:rules
                                     exceptionRules:exRules
                                     exceptionDates:exDates];
  count = [ranges count];
  for (i = 0; i < count; i++) {
    NGCalendarDateRange *rRange;
    id fixedRow;
    
    rRange   = [ranges objectAtIndex:i];
    fixedRow = [self fixupCycleRecord:row cycleRange:rRange];
    if (fixedRow != nil) [_ma addObject:fixedRow];
  }
}

- (NSArray *)fixupRecords:(NSArray *)_records
  fetchRange:(NGCalendarDateRange *)_r
{
  // TODO: is the result supposed to be sorted by date?
  NSMutableArray *ma;
  unsigned i, count;

  if (_records == nil) return nil;
  if ((count = [_records count]) == 0)
    return _records;
  
  ma = [NSMutableArray arrayWithCapacity:count];
  for (i = 0; i < count; i++) {
    id row; // TODO: what is the type of the record?
    
    row = [_records objectAtIndex:i];
    row = [self fixupRecord:row fetchRange:_r];
    if (row != nil) [ma addObject:row];
  }
  return ma;
}

- (NSArray *)fixupCyclicRecords:(NSArray *)_records
  fetchRange:(NGCalendarDateRange *)_r
{
  // TODO: is the result supposed to be sorted by date?
  NSMutableArray *ma;
  unsigned i, count;
  
  if (_records == nil) return nil;
  if ((count = [_records count]) == 0)
    return _records;
  
  ma = [NSMutableArray arrayWithCapacity:count];
  for (i = 0; i < count; i++) {
    id row; // TODO: what is the type of the record?
    
    row = [_records objectAtIndex:i];
    [self _flattenCycleRecord:row forRange:_r intoArray:ma];
  }
  return ma;
}

- (NSArray *)fetchFields:(NSArray *)_fields
  fromFolder:(GCSFolder *)_folder
  from:(NSCalendarDate *)_startDate
  to:(NSCalendarDate *)_endDate 
{
  EOQualifier         *qualifier;
  NSMutableArray      *fields, *ma = nil;
  NSArray             *records;
  NSString            *sql;
  NGCalendarDateRange *r;

  if (_folder == nil) {
    [self errorWithFormat:@"(%s): missing folder for fetch!",
            __PRETTY_FUNCTION__];
    return nil;
  }
  
  r = [NGCalendarDateRange calendarDateRangeWithStartDate:_startDate
                           endDate:_endDate];

  /* prepare mandatory fields */

  fields = [NSMutableArray arrayWithArray:_fields];
  [fields addObject:@"uid"];
  [fields addObject:@"startdate"];
  [fields addObject:@"enddate"];
  
  if (logger)
    [self debugWithFormat:@"should fetch (%@=>%@) ...", _startDate, _endDate];
  
  sql = [NSString stringWithFormat:@"(startdate < %d) AND (enddate > %d)"
                                   @" AND (iscycle = 0)",
		  (unsigned int)[_endDate   timeIntervalSince1970],
		  (unsigned int)[_startDate timeIntervalSince1970]];

  /* fetch non-recurrent apts first */
  qualifier = [EOQualifier qualifierWithQualifierFormat:sql];

  records   = [_folder fetchFields:fields matchingQualifier:qualifier];
  if (records != nil) {
    records = [self fixupRecords:records fetchRange:r];
    if (logger)
      [self debugWithFormat:@"fetched %i records: %@",[records count],records];
    ma = [NSMutableArray arrayWithArray:records];
  }
  
  /* fetch recurrent apts now */
  sql = [NSString stringWithFormat:@"(startdate < %d) AND (cycleenddate > %d)"
                                   @" AND (iscycle = 1)",
		  (unsigned int)[_endDate   timeIntervalSince1970],
		  (unsigned int)[_startDate timeIntervalSince1970]];
  qualifier = [EOQualifier qualifierWithQualifierFormat:sql];

  [fields addObject:@"cycleinfo"];

  records = [_folder fetchFields:fields matchingQualifier:qualifier];
  if (records != nil) {
    if (logger)
      [self debugWithFormat:@"fetched %i cyclic records: %@",
        [records count], records];
    records = [self fixupCyclicRecords:records fetchRange:r];
    if (!ma) ma = [NSMutableArray arrayWithCapacity:[records count]];
    [ma addObjectsFromArray:records];
  }
  else if (ma == nil) {
    [self errorWithFormat:@"(%s): fetch failed!", __PRETTY_FUNCTION__];
    return nil;
  }
  /* NOTE: why do we sort here?
     This probably belongs to UI but cannot be achieved as fast there as
     we can do it here because we're operating on a mutable array -
     having the apts sorted is never a bad idea, though
  */
  [ma sortUsingSelector:@selector(compareAptsAscending:)];
  if (logger)
    [self debugWithFormat:@"returning %i records", [ma count]];
  return ma;
}

/* override this in subclasses */
- (NSArray *)fetchFields:(NSArray *)_fields
  from:(NSCalendarDate *)_startDate
  to:(NSCalendarDate *)_endDate 
{
  GCSFolder *folder;
  
  if ((folder = [self ocsFolder]) == nil) {
    [self errorWithFormat:@"(%s): missing folder for fetch!",
      __PRETTY_FUNCTION__];
    return nil;
  }
  return [self fetchFields:_fields fromFolder:folder
               from:_startDate to:_endDate];
}


- (NSArray *)fetchFreebusyInfosFrom:(NSCalendarDate *)_startDate
  to:(NSCalendarDate *)_endDate
{
  static NSArray *infos = nil; // TODO: move to a plist file
  if (infos == nil) {
    infos = [[NSArray alloc] initWithObjects:@"partmails", @"partstates", nil];
  }
  return [self fetchFields:infos from:_startDate to:_endDate];
}


- (NSArray *)fetchOverviewInfosFrom:(NSCalendarDate *)_startDate
  to:(NSCalendarDate *)_endDate
{
  static NSArray *infos = nil; // TODO: move to a plist file
  if (infos == nil) {
    infos = [[NSArray alloc] initWithObjects:
                               @"title", 
                               @"location", @"orgmail", @"status", @"ispublic",
                               @"isallday", @"priority",
                               @"partmails", @"partstates",
                               nil];
  }
  return [self fetchFields:infos
               from:_startDate
               to:_endDate];
}

- (NSArray *)fetchCoreInfosFrom:(NSCalendarDate *)_startDate
  to:(NSCalendarDate *)_endDate 
{
  static NSArray *infos = nil; // TODO: move to a plist file
  if (infos == nil) {
    infos = [[NSArray alloc] initWithObjects:
                               @"title", @"location", @"orgmail",
                               @"status", @"ispublic",
                               @"isallday", @"isopaque",
                               @"participants", @"partmails",
                               @"partstates", @"sequence", @"priority", nil];
  }
  return [self fetchFields:infos
               from:_startDate
               to:_endDate];
}

/* URL generation */

- (NSString *)baseURLForAptWithUID:(NSString *)_uid inContext:(id)_ctx {
  // TODO: who calls this?
  NSString *url;
  
  if ([_uid length] == 0)
    return nil;
  
  url = [self baseURLInContext:_ctx];
  if (![url hasSuffix:@"/"])
    url = [url stringByAppendingString:@"/"];
  
  // TODO: this should run a query to determine the uid!
  return [url stringByAppendingString:_uid];
}

/* folder management */

- (id)lookupHomeFolderForUID:(NSString *)_uid inContext:(id)_ctx {
  // TODO: DUP to SOGoGroupFolder
  NSException *error = nil;
  NSArray     *path;
  id          ctx, result;

  if (![_uid isNotNull])
    return nil;
  
  if (_ctx == nil) _ctx = [[WOApplication application] context];
  
  /* create subcontext, so that we don't destroy our environment */
  
  if ((ctx = [_ctx createSubContext]) == nil) {
    [self errorWithFormat:@"could not create SOPE subcontext!"];
    return nil;
  }
  
  /* build path */
  
  path = _uid != nil ? [NSArray arrayWithObjects:&_uid count:1] : nil;
  
  /* traverse path */
  
  result = [[ctx application] traversePathArray:path inContext:ctx
			      error:&error acquire:NO];
  if (error != nil) {
    [self errorWithFormat:@"folder lookup failed (uid=%@): %@",
            _uid, error];
    return nil;
  }
  
  [self debugWithFormat:@"Note: got folder for uid %@ path %@: %@",
	  _uid, [path componentsJoinedByString:@"=>"], result];
  return result;
}

- (NSArray *)lookupCalendarFoldersForUIDs:(NSArray *)_uids inContext:(id)_ctx {
  /* Note: can return NSNull objects in the array! */
  NSMutableArray *folders;
  NSEnumerator *e;
  NSString     *uid;
  
  if ([_uids count] == 0) return nil;
  folders = [NSMutableArray arrayWithCapacity:16];
  e = [_uids objectEnumerator];
  while ((uid = [e nextObject])) {
    id folder;
    
    folder = [self lookupHomeFolderForUID:uid inContext:nil];
    if ([folder isNotNull]) {
      folder = [folder lookupName:@"Calendar" inContext:nil acquire:NO];
      if ([folder isKindOfClass:[NSException class]])
	folder = nil;
    }
    if (![folder isNotNull])
      [self logWithFormat:@"Note: did not find folder for uid: '%@'", uid];
    
    /* Note: intentionally add 'null' folders to allow a mapping */
    [folders addObject:folder ? folder : [NSNull null]];
  }
  return folders;
}

- (NSArray *)lookupFreeBusyObjectsForUIDs:(NSArray *)_uids inContext:(id)_ctx {
  /* Note: can return NSNull objects in the array! */
  NSMutableArray *objs;
  NSEnumerator   *e;
  NSString       *uid;
  
  if ([_uids count] == 0) return nil;
  objs = [NSMutableArray arrayWithCapacity:16];
  e    = [_uids objectEnumerator];
  while ((uid = [e nextObject])) {
    id obj;
    
    obj = [self lookupHomeFolderForUID:uid inContext:nil];
    if ([obj isNotNull]) {
      obj = [obj lookupName:@"freebusy.ifb" inContext:nil acquire:NO];
      if ([obj isKindOfClass:[NSException class]])
	obj = nil;
    }
    if (![obj isNotNull])
      [self logWithFormat:@"Note: did not find freebusy.ifb for uid: '%@'", uid];
    
    /* Note: intentionally add 'null' folders to allow a mapping */
    [objs addObject:obj ? obj : [NSNull null]];
  }
  return objs;
}

- (NSArray *)uidsFromICalPersons:(NSArray *)_persons {
  /* Note: can return NSNull objects in the array! */
  NSMutableArray    *uids;
  AgenorUserManager *um;
  unsigned          i, count;
  
  if (_persons == nil)
    return nil;

  count = [_persons count];
  uids  = [NSMutableArray arrayWithCapacity:count + 1];
  um    = [AgenorUserManager sharedUserManager];
  
  for (i = 0; i < count; i++) {
    iCalPerson *person;
    NSString   *email;
    NSString   *uid;
    
    person = [_persons objectAtIndex:i];
    email  = [person rfc822Email];
    if ([email isNotNull]) {
      uid = [um getUIDForEmail:email];
    }
    else
      uid = nil;
    
    [uids addObject:(uid != nil ? uid : (id)[NSNull null])];
  }
  return uids;
}

- (NSArray *)lookupCalendarFoldersForICalPerson:(NSArray *)_persons
  inContext:(id)_ctx
{
  /* Note: can return NSNull objects in the array! */
  NSArray *uids;

  if ((uids = [self uidsFromICalPersons:_persons]) == nil)
    return nil;
  
  return [self lookupCalendarFoldersForUIDs:uids inContext:_ctx];
}

- (id)lookupGroupFolderForUIDs:(NSArray *)_uids inContext:(id)_ctx {
  SOGoCustomGroupFolder *folder;
  
  if (_uids == nil)
    return nil;

  folder = [[SOGoCustomGroupFolder alloc] initWithUIDs:_uids inContainer:self];
  return [folder autorelease];
}
- (id)lookupGroupCalendarFolderForUIDs:(NSArray *)_uids inContext:(id)_ctx {
  SOGoCustomGroupFolder *folder;
  
  if ((folder = [self lookupGroupFolderForUIDs:_uids inContext:_ctx]) == nil)
    return nil;
  
  folder = [folder lookupName:@"Calendar" inContext:_ctx acquire:NO];
  if (![folder isNotNull])
    return nil;
  if ([folder isKindOfClass:[NSException class]]) {
    [self debugWithFormat:@"Note: could not lookup 'Calendar' in folder: %@",
	    folder];
    return nil;
  }
  
  return folder;
}

/* bulk fetches */

- (NSArray *)fetchAllSOGoAppointments {
  /* 
     Note: very expensive method, do not use unless absolutely required.
           returns an array of SOGoAppointment objects.
	   
     Note that we can leave out the filenames, supposed to be stored
     in the 'uid' field of the iCalendar object!
  */
  NSMutableArray *events;
  NSDictionary *files;
  NSEnumerator *contents;
  NSString     *content;
  
  /* fetch all raw contents */
  
  files = [self fetchContentStringsAndNamesOfAllObjects];
  if (![files isNotNull]) return nil;
  if ([files isKindOfClass:[NSException class]]) return (id)files;
  
  /* transform to SOGo appointments */
  
  events   = [NSMutableArray arrayWithCapacity:[files count]];
  contents = [files objectEnumerator];
  while ((content = [contents nextObject]) != nil) {
    SOGoAppointment *event;
    
    event = [[SOGoAppointment alloc] initWithICalString:content];
    if (![event isNotNull]) {
      [self errorWithFormat:@"(%s): could not parse an iCal file!",
              __PRETTY_FUNCTION__];
      continue;
    }

    [events addObject:event];
    [event release];
  }
  
  return events;
}

/* GET */

- (id)GETAction:(id)_ctx {
  // TODO: I guess this should really be done by SOPE (redirect to
  //       default method)
  WOResponse *r;
  NSString *uri;

  uri = [[(WOContext *)_ctx request] uri];
  if (![uri hasSuffix:@"/"]) uri = [uri stringByAppendingString:@"/"];
  uri = [uri stringByAppendingString:@"weekoverview"];

  r = [_ctx response];
  [r setStatus:302 /* moved */];
  [r setHeader:uri forKey:@"location"];
  return r;
}

/* folder type */

- (NSString *)outlookFolderClass {
  return @"IPF.Appointment";
}

@end /* SOGoAppointmentFolder */
