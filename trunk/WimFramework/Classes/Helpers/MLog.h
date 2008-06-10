//MLog.h

extern BOOL __MLogOn;
//Verbose Logging with File and line number -- not recommended for general release
#define MLog(s,...) \
    [MStringLog logFile:__FILE__ lineNumber:__LINE__ \
          format:(s),##__VA_ARGS__]

//Conditional logging without file and line numbers
//#define MLog(s,...) \
//    (__MLogOn ? NSLog(s, ##__VA_ARGS__) : (void)0)

//Logging as a NOOP
//#define MLog(s,...) \
//    ((void)0)

          
@interface MStringLog : NSObject
{
}

+(void)logFile:(char*)sourceFile lineNumber:(int)lineNumber 
       format:(NSString*)format, ...;
+(void)setLogOn:(BOOL)logOn;

@end
