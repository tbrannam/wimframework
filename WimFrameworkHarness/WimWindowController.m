/* 
 Copyright (c) 2008 AOL LLC
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer 
 in the documentation and/or other materials provided with the distribution.
 Neither the name of the AOL LCC nor the names of its contributors may be used to endorse or promote products derived 
 from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT 
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#import "WimWindowController.h"


//kTestHarnessDevId - DO NOT USE THIS KEY IN YOUR RELEASE APPLICATION - IT MAY BE REVOKED WITHOUT NOTICE
// GET YOUR OWN FREE DEV KEY http://developer.aim.com/wimReg.jsp
NSString *kTestHarnessDevId = @"tb17-IMEDLqnPUbO";

NSString *kClientName = @"WIM Test Harness";
NSString *kClientVersion = @"0.1";
NSString *kScreenNamePref = @"screenName";
NSString *kPasswordPref = @"password";
NSString *kDevIdPref = @"developerKey";

@implementation WimWindowController

+ (void)initialize
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  
  NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                               @"" , kScreenNamePref ,
                               @"" , kPasswordPref ,
                               kTestHarnessDevId, kDevIdPref,
                               nil ];
  
  [defaults registerDefaults:appDefaults];
}

// Create a WIMSession object for this application,
// initialize your client name and client version number

-(id) init
{
  if (self = [super init])
  {
    wimSession = [[WimSession alloc] init];
    [wimSession setClientName:kClientName];
    [wimSession setClientVersion:kClientVersion];
  }
  
  return self;
}

-(void)dealloc
{
  [wimSession release];
	[[NSNotificationCenter defaultCenter] removeObject:self];
	[super dealloc];
}

- (void)appendLog:(NSString *)aMessage
{
	NSAttributedString *log = [[[NSAttributedString alloc] initWithString:aMessage] autorelease];
  [[sessionLog textStorage] appendAttributedString:log];
  NSRange range;
  range = NSMakeRange ([[sessionLog string] length], 0);
  [sessionLog scrollRangeToVisible: range];
}


-(void)onOnlineEvent:(NSNotification*)notification
{	
  [self willChangeValueForKey:@"online"];
  [self willChangeValueForKey:@"connected"];

  _connected = [wimSession connected];
  
  [self didChangeValueForKey:@"connected"];
  [self didChangeValueForKey:@"online"];
  
  [self appendLog:[NSString stringWithFormat:@"%@\n", [notification name]]];
}

-(void)onPresenceEvent:(NSNotification*)notification
{
  // WIM Events will contain a NSDictionary containing the data returned from the WIMServer
  // you can valueForKeyPath to access these structures
  
	NSDictionary* buddy = [notification userInfo];
	NSString *log = [NSString stringWithFormat:@"presenceEvent: %@ (%@)\n", [buddy objectForKey:@"displayId"], [buddy objectForKey:@"state"]];
  [self appendLog:log];
}

-(void)onBuddyListArrived:(NSNotification*)notification
{
  // WIM Events will contain a NSDictionary containing the data returned from the WIMServer
  // you can valueForKeyPath to access these structures

	NSString *log = [NSString stringWithFormat:@"buddyListArrived:\n"];
  [self appendLog:log];
  
	// We don't want to fire presence events when we get a buddy list
  NSDictionary *buddyList = [notification userInfo];
  NSArray *groupsArray = [buddyList valueForKey:@"groups"];
  NSEnumerator* buddyListGroups = [groupsArray objectEnumerator];
  NSArray* buddyGroups;
  
  while ((buddyGroups = [buddyListGroups nextObject])) 
  {
    NSEnumerator *buddies = [[buddyGroups valueForKey:@"buddies"] objectEnumerator];
    NSMutableDictionary *buddy;
    NSString *log = [NSString stringWithFormat:@"Group: %@\n", [buddyGroups valueForKey:@"name"]];
    [self appendLog:log];
    while (buddy = [buddies nextObject])
    {
      log = [NSString stringWithFormat:@"buddyList: %@ (%@)\n", [buddy objectForKey:@"displayId"], [buddy objectForKey:@"state"]];
      [self appendLog:log];
    }
  }
}

-(void)onIMSentEvent:(NSNotification *)notification
{
  [message setStringValue:@""];
}

-(void)onIMReceivedEvent:(NSNotification *)notification
{
  // WIM Events will contain a NSDictionary containing the data returned from the WIMServer
  // you can valueForKeyPath to access these structures

  // send specific event to context
  NSDictionary *imEvent = [notification userInfo];
  NSString *fromAimId = [imEvent valueForKeyPath:@"eventData.source.aimId"];
  NSString *messageText = [imEvent valueForKeyPath:@"eventData.message"];

	NSString *log = [NSString stringWithFormat:@"%@->%@: %@\n", fromAimId, [wimSession aimId], messageText];
  [self appendLog:log];
  [message setStringValue:@""];
}


-(void)onWatchNotification:(NSNotification*)notification
{
	[self appendLog:[NSString stringWithFormat:@"onWatchNotification %@", [notification name]]];
}

-(void)awakeFromNib
{
  // WimSession will post notifications as the session goes online and offline
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOnlineEvent:) name:kWimClientSessionOnline object:wimSession];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOnlineEvent:) name:kWimClientSessionOffline object:wimSession];

  // WIMSession (and others, see WimEvents.h for others) will post notifications as AIM events occur
  // [NSNotification userInfo] will usually contain a NSDictionary which maps to WIM Event objects as documented at
  // http://dev.aol.com/aim/web/serverapi_reference

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPresenceEvent:) name:kWimSessionPresenceEvent object:nil];	
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onIMSentEvent:) name:kWimClientIMSent object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onIMReceivedEvent:) name:kWimSessionIMEvent object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onBuddyListArrived:) name:kWimSessionBuddyListEvent object:nil];
  
  // load our default values
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [username setStringValue:[defaults valueForKey:kScreenNamePref]];
  [password setStringValue:[defaults valueForKey:kPasswordPref]];
  [aimDeveloperKey setStringValue:[defaults valueForKey:kDevIdPref]];
}

- (IBAction)onSignOff:(id)sender
{
	[wimSession disconnect];
}

- (IBAction)onSignOn:(id)sender
{
  // register a delegate to handle UI for secondary challenges (wrong password, captcha, alternate security question)
  [wimSession setDelegate:self];
  
  // set your application's developer key
  [wimSession setDevID:[aimDeveloperKey stringValue]];
  
  // set the username and password on the wimSession
	[wimSession setUserName:[username stringValue]];
	[wimSession setPassword:[password stringValue]];
  
  // only used for testing of the captcha secondary challenge
  [wimSession setForceCaptcha:[forceCaptcha state]==NSOnState];
  
  // update preferences
  [[NSUserDefaults standardUserDefaults] setObject:[username stringValue]
                                            forKey:kScreenNamePref];
  
  [[NSUserDefaults standardUserDefaults] setObject:[password stringValue]
                                            forKey:kPasswordPref];

  [[NSUserDefaults standardUserDefaults] setObject:[aimDeveloperKey stringValue]
                                            forKey:kDevIdPref];

  
  // start an online session
	[wimSession connect];
}

- (IBAction)onSend:(id)sender
{
	NSLog(@"message sending %@:%@", [to stringValue], [message stringValue]);

  NSString *log = [NSString stringWithFormat:@"%@->%@: %@\n", [wimSession aimId], [to stringValue], [message stringValue]];
  [self appendLog:log];

	[wimSession sendInstantMessage:[message stringValue] toAimId:[to stringValue]];
}

- (IBAction)onPresence:(id)sender
{
	NSLog(@"request presence %@", [to stringValue]);
	[wimSession requestPresenceForAimId:[to stringValue]];
}

- (IBAction)closeCustomSheet:(id)sender
{
  [NSApp stopModalWithCode:[sender tag]];
}

- (IBAction)clearHistory:(id)sender
{
  [sessionLog setString:@""];
  [sessionLog setNeedsDisplay:YES];
}

- (void)setAwayMessage:(NSString *)aAwayMessage
{
  aAwayMessage = [aAwayMessage copy];
  [awayMessage autorelease];
  awayMessage = aAwayMessage;
  
  [wimSession setState:_status withMessage:aAwayMessage];
}

- (NSString *)awayMessage
{
  return awayMessage;
}

- (void)setStatusMessage:(NSString *)aMessage
{
  aMessage = [aMessage copy];
  [statusMessage autorelease];
  statusMessage = aMessage;

  [wimSession setStatus:aMessage];
}

- (NSString *)statusMessage
{
  return statusMessage;
}

- (int)status
{
  return _status;
}

- (void)setStatus:(int)aStatus
{
  _status = aStatus;
  [wimSession setState:_status withMessage:awayMessage];
}

- (void)setProfileMessage:(NSAttributedString *)aMessage
{
  aMessage = [aMessage copy];
  [profileMessage autorelease];
  profileMessage = aMessage;
  
  [wimSession setProfile:[profileMessage string]];
}

- (NSAttributedString *)profileMessage
{
  return profileMessage;
}

- (BOOL)connected
{
  return _connected;
}

- (BOOL)online
{
  return _connected;
}

#pragma mark WimSession Delegate callbacks to handle special authentication events

// These are secondary challenges sometimes required by the login server.  In the event of 
// a secondary challenge - the application is required to present UI in order to collect 
// answers to login challenges.  Currently three challenges are supported here
// SecurID (RSA tokens - typically used by AOL employees)
// Password -- in the event that the password entered is wrong or has changed
// Captcha -- an image/text challenge - typically used to verify the user is a person and not an automated script

- (void) wimSessionRequiresCaptcha:(WimSession *)aWimSession url:(NSURL *)url
{
  // called when WIM authentication needs user needs to validate himself with a captcha image
  NSImage *image = [[[NSImage alloc] initWithContentsOfURL:url] autorelease];
  [captchaImage setImage:image];
  [captcha setStringValue:@""];
 
  [wimSession setForceCaptcha:NO];
  
  [NSApp beginSheet:captchaPanel
     modalForWindow:[self window]
      modalDelegate:nil
     didEndSelector:nil
        contextInfo:nil];
  
  int code = [NSApp runModalForWindow:captchaPanel];
  [forceCaptcha setState:NSOffState];
  
  NSString *answer = nil;
  
  if (code > 0)
  {
    answer = [captcha stringValue];
  }
  
  [NSApp endSheet:captchaPanel];
  
  [captchaPanel orderOut:self];
  
  if (answer)
  {
    [aWimSession answerChallenge:answer];
  }
  else
  {
    [aWimSession disconnect];
  }
  
  [captcha setStringValue:@""];
}


- (void) wimSessionRequiresPassword:(WimSession *)aWimSession
{
  // called when WIM authentication needs a different password
  [challengePassword setStringValue:@""];
  
  [NSApp beginSheet:passwordPanel
     modalForWindow:[self window]
      modalDelegate:nil
     didEndSelector:nil
        contextInfo:nil];
  
  int code = [NSApp runModalForWindow:passwordPanel];
  
  [NSApp endSheet:passwordPanel];
  
  [passwordPanel orderOut:self];
  
  if (code > 0)
  {
    [aWimSession answerChallenge:[challengePassword stringValue]];
  }
  else
  {
    [aWimSession disconnect];
  }
  
  [challengePassword setStringValue:@""];
}

- (void) wimSessionRequiresChallenge:(WimSession *)aWimSession
{
  // called when WIM authentication needs an answer to a secondary challenge (SecureID)
  [securId setStringValue:@""];
  
  [NSApp beginSheet:securIdPanel
     modalForWindow:[self window]
      modalDelegate:nil
     didEndSelector:nil
        contextInfo:nil];
  
  int code = [NSApp runModalForWindow:securIdPanel];
  
  NSString *answer = nil;
  
  if (code > 0)
  {
    answer = [securId stringValue];
  }
  
  [NSApp endSheet:securIdPanel];
  
  [securIdPanel orderOut:self];
  
  if (answer)
  {
    [aWimSession answerChallenge:answer];
  }
  else
  {
    [aWimSession disconnect];
  }
  
  [securId setStringValue:@""];
}
@end
