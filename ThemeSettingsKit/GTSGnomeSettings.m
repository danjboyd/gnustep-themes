/* GTSGnomeSettings.m */
#import "GTSGnomeSettings.h"

static NSString *
findTool(NSString *name)
{
  NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey: @"PATH"];
  NSEnumerator *e = [[path componentsSeparatedByString: @":"] objectEnumerator];
  NSString *dir;
  NSFileManager *fm = [NSFileManager defaultManager];
  while ((dir = [e nextObject]) != nil)
    {
      NSString *p;
      if ([dir length] == 0) continue;
      p = [dir stringByAppendingPathComponent: name];
      if ([fm isExecutableFileAtPath: p]) return p;
    }
  return nil;
}

@implementation GTSGnomeSettings

+ (GTSGnomeSettings*) systemSettings
{
  return [[[GTSGnomeSettings alloc] init] autorelease];
}

- (NSString*) interfaceStringForKey: (NSString*)key
{
  NSString *tool = findTool(@"gsettings");
  NSTask *task;
  NSPipe *out;
  NSData *data;
  NSString *s;

  if (tool == nil || [key length] == 0) return nil;
  task = [[[NSTask alloc] init] autorelease];
  out = [NSPipe pipe];
  [task setLaunchPath: tool];
  [task setArguments: [NSArray arrayWithObjects: @"get", @"org.gnome.desktop.interface", key, nil]];
  [task setStandardOutput: out];
  [task setStandardError: [NSFileHandle fileHandleWithNullDevice]];
  NS_DURING
    [task launch];
  NS_HANDLER
    return nil;
  NS_ENDHANDLER
  data = [[out fileHandleForReading] readDataToEndOfFile];
  [task waitUntilExit];
  if ([task terminationStatus] != 0) return nil;
  s = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
  s = [s stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([s length] >= 2 && [s hasPrefix: @"'"] && [s hasSuffix: @"'"])
    s = [s substringWithRange: NSMakeRange(1, [s length] - 2)];
  return [s length] > 0 ? s : nil;
}

@end

@implementation GTSFixedGnomeSettings

- (id) initWithValues: (NSDictionary*)values
{
  if ((self = [super init]) != nil)
    _values = [values copy];
  return self;
}

- (void) dealloc
{
  [_values release];
  [super dealloc];
}

- (NSString*) interfaceStringForKey: (NSString*)key
{
  return [_values objectForKey: key];
}

@end
