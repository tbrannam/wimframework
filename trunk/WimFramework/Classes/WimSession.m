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


#import "WimSession.h"
#import "WimRequest.h"
#import "WimEvents.h"
#import "ClientLogin.h"
#import "ClientLogin+Private.h"
#import "NSDataAdditions.h"
#import "WimConstants.h"
#import "JSON.h"

#if MAC_OS_X_VERSION_MIN_REQUIRED > MAC_OS_X_VERSION_10_4
#import <CommonCrypto/CommonHMAC.h>
#else
#import "CommonHMAC.h"
#endif

#import "MLog.h"

WimSession* gDefaultSession = nil;

@interface WimSession (PRIVATEAPI)
- (BOOL)canRestartSession;
- (void)requestTokenForName:(NSString*)screenName withPassword:(NSString*)password;
- (void)startSession;
- (void)endSession;
- (void)onAimPresenceResponse:(NSNotification *)notification;
- (void)setBuddyList:(NSDictionary *)buddyList;

@end

NSDictionary *WimSession_OnlineStateInts;
NSDictionary *WimSession_OnlineStateStrings;

@implementation WimSession

+ (WimSession*) defaultSession
{
  if (gDefaultSession == nil)
  {
    gDefaultSession = [[WimSession alloc] init];
  }
  return gDefaultSession;
}



+ (void)initialize
{
  WimSession_OnlineStateInts = [[NSDictionary dictionaryWithObjectsAndKeys:
    @"1"  , @"online", 
    @"2",  @"invisible",
    @"3",  @"notFound",
    @"4",  @"idle", 
    @"5"  , @"away", 
    @"6",  @"mobile",
    @"7",  @"offline",
    nil ] retain];

  WimSession_OnlineStateStrings = [[NSDictionary dictionaryWithObjectsAndKeys:
    @"online",  @"1",
    @"invisible", @"2",
    @"notFound", @"3",
    @"idle", @"4", 
    @"away", @"5", 
    @"mobile", @"6",  
    @"offline", @"7", 
    nil ] retain];
}

- (id)init
{
  if (self = [super init])
  {
  }
  return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  _userName = [[coder decodeObjectForKey:@"userName"] retain];
  _sessionKey = [[coder decodeObjectForKey:@"sessionKey"] retain];
  _authToken = [[coder decodeObjectForKey:@"authToken"] retain];
  _tokenExpiration = [[coder decodeObjectForKey:@"tokenExpiration"] retain];
  
  // this seems wrong - perhaps defaultSession should be a property allowing the caller to specify which object is the defaultSession?
  if (!gDefaultSession)
    gDefaultSession = self;
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:_userName forKey:@"userName"];
  [coder encodeObject:_sessionKey forKey:@"sessionKey"];
  [coder encodeObject:_authToken forKey:@"authToken"];
  [coder encodeObject:_tokenExpiration forKey:@"tokenExpiration"];
}

- (void)dealloc 
{
  [_wimFetchRequest setDelegate:nil];
  [_userName release];
  [_password release];
  [_sessionId release];
  [_authToken release];
  [_fetchBaseUrl release];
  [_tokenExpiration release];
  [_clientLogin release];
  [_devID release];
  [_clientVersion release];
  [_clientName release];
  
  if (self == gDefaultSession)
    gDefaultSession = nil;
  
  [super dealloc];
}


#pragma mark WimSession core methods

// AIM Clients are required to use a application/developmenent ID - request yours at developer.aim.com
- (NSString *)devID
{
  return _devID;
}

- (void)setDevID:(NSString *)aDevID
{
  aDevID = [aDevID copy];
  [_devID release];
  _devID = aDevID;
}


- (NSString *)clientName
{
  return _clientName;
}

- (void)setClientName:(NSString *)aClientName
{
  aClientName = [aClientName copy];
  [_clientName release];
  _clientName = aClientName;
}

- (NSString *)clientVersion
{
  return _clientVersion;
}

- (void)setClientVersion:(NSString *)aClientVersion
{
  aClientVersion = [aClientVersion copy];
  [_clientVersion release];
  _clientVersion = aClientVersion;
}


- (void)connect
{
  if ([self canRestartSession])
  {
    [self startSession];
  }
  else
  {
    [_clientLogin release];
    _clientLogin = [[ClientLogin alloc] init];
    [_clientLogin setDelegate:self];
    
    if ([_userName length])
    {
      if ([_password length])
      {
        [self requestTokenForName:_userName withPassword:_password];
      }
      else
      {
        if ([_delegate respondsToSelector:@selector(wimSessionRequiresPassword:)])
          [_delegate performSelector:@selector(wimSessionRequiresPassword:) withObject:self];
      }
    }
    else
    {
      MLog(@"could not log on without username and password");
      //TODO: fire Log off event
    }
  }
}

- (BOOL)connected
{
  return _connected;
}

- (void)disconnect
{
  [_clientLogin release];
   _clientLogin = nil;
  
  [self endSession];
}

- (void)answerChallenge:(NSString *)challengeAnswer
{
  if (![_password length])
  {
    [_password autorelease];
    _password = [challengeAnswer copy];
    [self connect];
  }
  else
  {
    [_clientLogin answerChallenge:challengeAnswer];
  }
} 

- (void)requestPresenceForAimId:(NSString*)aBuddyName 
{
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventPresenceResponse:withError:)];
    
  NSString* urlString = [NSString stringWithFormat:kUrlPresenceRequest, kAPIBaseURL, [[self devID] urlencode], aBuddyName];
  NSURL *url = [NSURL URLWithString:urlString];

  [wimRequest setUserData:self];
  [wimRequest requestURL:url];
}

- (void)requestBuddyInfoForAimId:(NSString*)aimId
{
  NSString *kUrlGetBuddyInfo = @"%@aim/getHostBuddyInfo?f=html&k=%@a=%@&aimsid=%@&r=%d&t=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, aimId
  
  NSString* urlString = [NSString stringWithFormat: kUrlGetBuddyInfo, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
                         [aimId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventGetHostBuddyInfoResponse:withError:)];
  
  MLog (@"fetching %@", urlString);
  
  NSArray *userData = [NSArray arrayWithObjects:aimId, nil];
  [wimRequest setUserData:userData];
  [wimRequest requestURL:url];
}


// Add/Remove Buddies
- (void)addBuddy:(NSString *)aimId withFriendlyName:(NSString *)friendlyName toGroup:(NSString *)groupName
{
  NSString *kUrlAddBuddy = @"%@buddylist/addBuddy?f=json&k=%@a=%@&aimsid=%@&r=%d&buddy=%@&group=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, newBuddy, groupName

  NSString* urlString = [NSString stringWithFormat: kUrlAddBuddy, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
                         [aimId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [groupName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventAddBuddyResponse:withError:)];
  
  MLog (@"fetching %@", urlString);
  
  NSArray *userData = [NSArray arrayWithObjects:aimId, friendlyName, nil];
  
  [wimRequest setUserData:userData];
  [wimRequest requestURL:url];
}

- (void)removeBuddy:(NSString *)aimId fromGroup:(NSString *)groupName
{
  NSString *kUrlRemoveBuddy = @"%@buddylist/removeBuddy?f=json&k=%@a=%@&aimsid=%@&r=%d&buddy=%@&group=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, newBuddy, groupName
  
  NSString* urlString = [NSString stringWithFormat: kUrlRemoveBuddy, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
                         [aimId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [groupName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventRemoveBuddyResponse:withError:)];
  
  MLog (@"fetching %@", urlString);
  
 
  [wimRequest requestURL:url];
}


- (void)setFriendlyName:(NSString*)friendlyName toAimId:(NSString*)aimId
{
  NSString* urlString = [NSString stringWithFormat: kUrlSetBuddyAttribute, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
                         [aimId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [friendlyName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventSetBuddyAttributeResponse:withError:)];
  
  MLog (@"fetching %@", urlString);
  [wimRequest setUserData:aimId];
  [wimRequest requestURL:url];
  
}

- (void)moveGroup:(NSString *)groupName beforeGroup:(NSString *)beforeGroup
{
  NSString* urlString;
  if (beforeGroup)
  {
    NSString *kUrlMoveGroup = @"%@buddylist/moveGroup?f=json&k=%@a=%@&aimsid=%@&r=%d&group=%@&beforeGroup=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, groupName, beforeGroup
  
    urlString = [NSString stringWithFormat: kUrlMoveGroup, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
                         [groupName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [beforeGroup stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  }
  else
  {
    NSString *kUrlMoveGroup = @"%@buddylist/moveGroup?f=json&k=%@a=%@&aimsid=%@&r=%d&group=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, groupName, beforeGroup
    urlString = [NSString stringWithFormat: kUrlMoveGroup, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
                           [groupName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  }
  
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventMoveGroupResponse:withError:)];
  
  MLog (@"fetching %@", urlString);
  
  [wimRequest requestURL:url];
}



- (void)sendInstantMessage:(NSString*)message toAimId:(NSString*)aimId
{
  NSString* urlString = [NSString stringWithFormat: kUrlSendIMRequest, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
      [message stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], aimId];
  
  NSURL *url = [NSURL URLWithString:urlString];
  
  //http://api.oscar.aol.com/im/sendIM?f=json&k=MYKEY&c=callback&aimsid=AIMSID&msg=Hi&t=ChattingChuck
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventIMSentResponse:withError:)];

  MLog (@"fetching %@", urlString);
  [wimRequest setUserData:aimId];
  [wimRequest requestURL:url];
}


- (void)setState:(enum OnlineState)onlineState withMessage:(NSString *)message
{
  //http://api.oscar.aol.com/presence/setState?f=json&k=MYKEY&c=callback&aimsid=AIMSID&view=away&away=Gone
  NSString *stateString = [WimSession_OnlineStateStrings valueForKey:[NSString stringWithFormat:@"%d", onlineState]];
  
  NSString *kUrlSetState = @"%@presence/setState?f=json&aimsid=%@&r=%d&view=%@"; // requires kAPIBaseURL, authtoken, requestid, state

  NSMutableString* urlString = [NSMutableString stringWithString:[NSString stringWithFormat: kUrlSetState, kAPIBaseURL, _sessionId, [WimRequest nextRequestId], stateString]];

  if (onlineState == OnlineState_away && message)
  {
    [urlString appendFormat:@"&away=%@", [[message stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] urlencode]];
  }
  
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventSetStateResponse:withError:)];

  MLog (@"fetching %@", urlString);
  [wimRequest requestURL:url];
}

- (void)setStatus:(NSString *)message
{
  NSMutableString *queryString = [[[NSMutableString alloc] init] autorelease];
  [queryString appendValue:@"json" forName:@"f"];
  [queryString appendValue:[NSString stringWithFormat:@"%d", [WimRequest nextRequestId]] forName:@"r"];
  [queryString appendValue:_sessionId forName:@"aimsid"];
  //[queryString appendValue:message forName:@"statusMsg"];
  [queryString appendFormat:@"&statusMsg=%@", [[message stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] urlencode]];

  
  NSString *urlString = [NSMutableString stringWithFormat:@"http://api.oscar.aol.com/presence/setStatus?%@", queryString];
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventSetStatusResponse:withError:)];
  
  MLog (@"fetching %@", urlString);
  [wimRequest requestURL:url];
}

- (void)setProfile:(NSString *)message
{
  NSMutableString *queryString = [[[NSMutableString alloc] init] autorelease];
  [queryString appendValue:@"json" forName:@"f"];
  [queryString appendValue:[NSString stringWithFormat:@"%d", [WimRequest nextRequestId]] forName:@"r"];
  [queryString appendValue:_sessionId forName:@"aimsid"];
  //[queryString appendValue:message forName:@"profile"];
  [queryString appendFormat:@"&profile=%@", [[message stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] urlencode]];

  NSString *urlString = [NSMutableString stringWithFormat:@"http://api.oscar.aol.com/presence/setProfile?%@", queryString];
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventSetProfileResponse:withError:)];
  
  MLog (@"fetching %@", urlString);
  [wimRequest requestURL:url];
}



- (void)setLargeBuddyIcon:(NSData*)iconData
{
  // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, expression type
  NSString* urlString = [NSString stringWithFormat: kUrlUploadExpression, kAPIBaseURL, [self devID], _authToken, _sessionId, [WimRequest nextRequestId], 
                        @"buddyIcon"];
  
  NSURL *url = [NSURL URLWithString:urlString];
  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventSetLargeBuddyIconResponse:withError:)];
  
  MLog (@"posting %@", urlString);
  [wimRequest requestURL:url withData:iconData];
}

#pragma mark ClientLogin Delegate

- (void) clientLoginRequiresChallenge:(ClientLogin *)aClientLogin
{
  // delegate UI handling login challenge - delegate should relogin after providing answer to challenge
  int code = [[aClientLogin statusDetailCode] intValue];
  
  switch (code)
  {
    case 3011: // password challenge
      if ([_delegate respondsToSelector:@selector(wimSessionRequiresPassword:)])
        [_delegate performSelector:@selector(wimSessionRequiresPassword:) withObject:self];
      break;
    case 3012: // securid challenge
    case 3013: // securid seconde challenge
      if ([_delegate respondsToSelector:@selector(wimSessionRequiresChallenge:)])
        [_delegate performSelector:@selector(wimSessionRequiresChallenge:) withObject:self];
      break;
    case 3015: // captcha challenge
      if ([_delegate respondsToSelector:@selector(wimSessionRequiresCaptcha:url:)])
      {
        NSString *captchaURL = [NSString stringWithFormat:@"%@?devId=%@&f=image&context=%@", [aClientLogin challengeURL], [self devID], [aClientLogin challengeContext]];
        NSURL *url = [NSURL URLWithString:captchaURL];
        [_delegate performSelector:@selector(wimSessionRequiresCaptcha:url:) withObject:self withObject:url];
      }
      break;
    default:
      MLog(@"clientLoginRequiresChallenge unsupported secondary challenge");
      break;
  }
}

- (void) clientLoginComplete:(ClientLogin *)aClientLogin
{
  _loginAttempt=0;
  MLog(@"onAimLoginEventTokenGranted");
  [_sessionKey release];
  _sessionKey = [[aClientLogin sessionKey] retain];
  
  [_authToken release];
  _authToken = [[aClientLogin tokenStr] retain];
  
  NSTimeInterval seconds = [[aClientLogin expiresIn] intValue];
  NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:seconds];
  [_tokenExpiration release];
  _tokenExpiration = [expirationDate retain];

  
  // we are done with the client login
  [_clientLogin release];
  _clientLogin = nil;
  
  
  [self startSession];

}

- (void) clientLoginFailed:(ClientLogin *)aClientLogin
{
  // TODO: display error UI to user - allow application level to handle retrys
  MLog(@"onAimLoginEventTokenFailure");
  _loginAttempt++;
  if (_loginAttempt < 4)
  {
    // if login is failing - don't use cached credentials
    if (_tokenExpiration)
      NSLog(@"clientLoginFailed cached login failed");
    [_tokenExpiration release];
    _tokenExpiration = nil;
    [_authToken release];
    _authToken = nil;
    [_sessionKey release];
    _sessionKey = nil;

    [self connect];
  }
  else
  {
    // we are done with the client login
    [_clientLogin release];
    _clientLogin = nil;
    
    _connected = NO;
  }
}

- (void)buddyListArrived
{
  MLog(@"buddyListArrived");
#if 0
	// We don't want to fire presence events when we get a buddy list
  NSArray *buddyList = [_buddyList valueForKey:@"groups"];
  NSEnumerator* buddyListGroups = [buddyList objectEnumerator];
  NSArray* buddyGroups;
  
  while ((buddyGroups = [buddyListGroups nextObject])) 
  {
    NSEnumerator *buddies = [[buddyGroups valueForKey:@"buddies"] objectEnumerator];
    NSMutableDictionary *buddy;
    while (buddy = [buddies nextObject])
    {
      [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionPresenceEvent object:self userInfo:buddy];
    }
  }
#else
  [[NSNotificationCenter defaultCenter] postNotificationName:kWimSessionBuddyListEvent object:self userInfo:_buddyList];
#endif
}

- (void)updateBuddyListWithBuddy:(NSDictionary*)newBuddyInfo
{
  MLog(@"updateBuddyListwithBuddy: %@", newBuddyInfo );
  
  NSArray *buddyList = [_buddyList valueForKey:@"groups"];
  
  NSEnumerator* buddyListGroups = [buddyList objectEnumerator];
  NSArray* buddyGroups;
  
  while ((buddyGroups = [buddyListGroups nextObject])) 
  {
    NSEnumerator *buddies = [[buddyGroups valueForKey:@"buddies"] objectEnumerator];
    NSMutableDictionary *buddy;
    while (buddy = [buddies nextObject])
    {
      // fire presence events for existing UI - allowing prexisting UI to update state
      if ( [[buddy stringValueForKeyPath:@"aimId"] isEqual:[newBuddyInfo stringValueForKeyPath:@"aimId"]] ) 
      {
        // We found the same aimID, so let's update the contents of this NSMutableDictionary to reflect the new status...
        [buddy removeAllObjects];
        [buddy addEntriesFromDictionary:newBuddyInfo];

        //NSString* aimId = [buddy stringValueForKeyPath:@"aimId"];        
        //[[NSNotificationCenter defaultCenter]  postNotificationName:@"prenotifiy.buddy" object:buddy];

        //NSString* notificationName = [NSString stringWithFormat:@"%@.%@", kWimSessionPresenceEvent, aimId];
        //[[NSNotificationCenter defaultCenter]  postNotificationName:notificationName object:buddy];

        [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionPresenceEvent object:self userInfo:buddy];
      }
    }
  }
  
	// We don't want to fire a buddy list event when we just update presence. this causes a lot of recalculations in the table view
  //[[NSNotificationCenter defaultCenter] postNotificationName:kWimSessionBuddyListEvent object:self userInfo:_buddyList];
}


#pragma mark EventParser

- (void)parseEvents:(NSArray*)aEvents
{
  NSEnumerator* enumerator = [aEvents objectEnumerator];
  NSArray* event;
  
  while ((event = [enumerator nextObject])) 
  {
    // should eventdata be reparsed as Dictionary?
    NSString* type = [event stringValueForKeyPath:@"type"];
    if ([type isEqualToString:@"myInfo"])
    {
      NSDictionary *buddy = [event valueForKey:@"eventData"];
      NSLog(@"MyInfo: %@", buddy);
      
      [_myInfo release];
      _myInfo = [buddy retain];
      [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionMyInfoEvent object:self userInfo:buddy];
    }
    else if ([type isEqualToString:@"presence"]) 
    {
      NSDictionary *buddy = [event valueForKey:@"eventData"];
      [self updateBuddyListWithBuddy:buddy];  // Update the data to keep it in sync...
    }
    else if ([type isEqualToString:@"buddylist"]) 
    {
      [self setBuddyList:[event valueForKey:@"eventData"]];
    }
    else if ([type isEqualToString:@"typing"]) 
    {
      NSDictionary *buddy = [event valueForKey:@"eventData"];
      [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionTypingEvent object:self userInfo:buddy];
    }
    else if ([type isEqualToString:@"im"]) 
    {
      NSString *aimId = [event stringValueForKeyPath:@"eventData.source.aimId"];
      MLog(@"received IM %@", aimId);
      [[NSNotificationCenter defaultCenter] postNotificationName:kWimSessionIMEvent object:self userInfo:(NSDictionary*)event];
    }
    else if ([type isEqualToString:@"dataIM"]) 
    {
      [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionDataIMEvent object:self userInfo:(NSDictionary*)event];
    }
    else if ([type isEqualToString:@"endSession"]) 
    {
      _pendingEndSession = YES;
      [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionSessionEndedEvent object:self userInfo:(NSDictionary*)event];
    }
    else if ([type isEqualToString:@"offlineIM"]) 
    {
      // send generic handler out first - allowing application to create correct context
      [[NSNotificationCenter defaultCenter] postNotificationName:kWimSessionOfflineIMEvent object:self userInfo:(NSDictionary*)event];
    }
  }
}


#pragma mark Web API Interface
/**
 * Actually performs a startSession query to WIM. It is the target of the SESSION_STARTING event.
 * It packages up all the parameters into a query string and SHA256 signs the resulting string.
 * @param evt
 *  challenge
 */ 

- (void)requestTokenForName:(NSString*)screenName withPassword:(NSString*)password // andChallengeAnswer:(NSString*)answer
{
  if (_pendingEndSession==YES)
  {
    MLog(@"requestTokenForName aborted - due to session ending");
    return;
  }
  
  MLog(@"Token expired - due to requesting fetch token");
  [_clientLogin requestSessionKey:screenName withPassword:password forceCaptcha:_forceCaptcha];
}

- (BOOL)canRestartSession
{
  if (_tokenExpiration && [[NSDate date] earlierDate:_tokenExpiration] && _authToken && _sessionKey)
  {
    NSLog(@"canRestartSession YES");
    return YES;
  }

  return NO;
}

// http://api.oscar.aol.com/aim/startSession
- (void)startSession
{
  NSString *capabilities = @"myInfo,presence,buddylist,typing,im,offlineIM";
  //NSString *capabilities = @"myInfo,presence,buddylist,typing,im,dataIM,offlineIM";
  
  NSMutableString *queryString;
  
  // Set up params in alphabetical order
  queryString = [NSMutableString stringWithFormat:@"a=%@&clientName=%@&clientVersion=%@&events=%@&f=json&k=%@&ts=%d",
                     _authToken, [_clientName urlencode], [_clientVersion urlencode], [capabilities urlencode],
                     [_devID urlencode], abs([[NSDate date] timeIntervalSince1970])];

//                 _authToken, kClientName, kClientVersion, [capabilities urlencode],
//                 kDevId, abs([[NSDate date] timeIntervalSince1970])];
    
  
  CFStringRef encodedQueryStringRef = CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)queryString,
                                                                              NULL, (CFStringRef)@";/?:@&=+$,",
                                                                              kCFStringEncodingUTF8);
  
  NSString *encodedQueryString = [(NSString*)encodedQueryStringRef autorelease];
  
  // Generate OAuth Signature Base
  NSString *temp = [[NSString stringWithFormat:@"%@%@", kAPIBaseURL, @"aim/startSession"] urlencode];
  NSString *openAuthSignatureBase = [NSString stringWithFormat:@"GET&%@&%@", temp, encodedQueryString];
  
  MLog(@"AIMBaseURL %@   : ", kAPIBaseURL);
  MLog(@"QueryParams %@   : ", queryString);
  MLog(@"encodedQueryString %@:", encodedQueryString); 
  MLog(@"Session Key %@   : ", _sessionKey);
  MLog(@"Signature Base %@ : ", openAuthSignatureBase);
  
  const char* sessionKey = [_sessionKey cStringUsingEncoding:NSASCIIStringEncoding];
  const char* signatureBase = [openAuthSignatureBase cStringUsingEncoding:NSASCIIStringEncoding];
  
  unsigned char macOut[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, sessionKey, strlen(sessionKey), signatureBase, strlen(signatureBase), macOut);
  NSData *hash = [[[NSData alloc] initWithBytes:macOut length:sizeof(macOut)] autorelease];
  NSString *baseSixtyFourHash = [hash base64Encoding];
  
  // Append the sig_sha256 data
  CFStringRef encodedB64Ref = CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)baseSixtyFourHash,
                                                                      NULL, (CFStringRef)@";/?:@&=+$,", kCFStringEncodingUTF8);
  NSString *encodedB64 = [(NSString*)encodedB64Ref autorelease];
  
  MLog(@"StartSessionQuery: %@", queryString);
  NSString *urlString = [NSString stringWithFormat:@"%@aim/startSession?%@&sig_sha256=%@", kAPIBaseURL, queryString,encodedB64];
  
  //will trigger onWimEventSessionStarted
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventStartSession:withError:)];
  [wimRequest setUserData:self];
  [wimRequest requestURL:[NSURL URLWithString:urlString]];
}


- (void)fetchEvents
{
  if (_pendingEndSession==YES)
  {
    return;
  }
  
  NSString* urlString = [NSString stringWithFormat: kUrlFetchRequest, _fetchBaseUrl, [WimRequest nextRequestId], kUrlFetchTimeout];
  NSURL *url = [NSURL URLWithString:urlString];
  MLog (@"fetching %@", urlString);
  
  [_wimFetchRequest release];
  _wimFetchRequest = [[WimRequest wimRequest] retain];
 
  [_wimFetchRequest setDelegate:self];
  [_wimFetchRequest setAction:@selector(onWimEventFetchEvents:withError:)];
  [_wimFetchRequest setUserData:self];
  [_wimFetchRequest requestURL:url];
}


- (void)endSession
{
  _pendingEndSession = YES;
  NSString *urlString = [NSString stringWithFormat:kUrlEndSession, kAPIBaseURL, _sessionId]; 
  MLog (@"endSession %@", urlString);

  [_wimFetchRequest setDelegate:nil];
  [_wimFetchRequest release];
  _wimFetchRequest = nil;

  
  WimRequest *wimRequest = [WimRequest wimRequest];
  [wimRequest setDelegate:self];
  [wimRequest setAction:@selector(onWimEventEndSession:withError:)];
  [wimRequest setUserData:self];
  [wimRequest setSynchronous:YES];
  [wimRequest requestURL:[NSURL URLWithString:urlString]];

  _connected = NO;
  _pendingEndSession = NO;
  [[NSNotificationCenter defaultCenter] postNotificationName:kWimClientSessionOffline object:self];
}

#pragma mark Event handlers for Web API response

- (void)onWimEventStartSession:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"EventSessionStarted failed with error: %@", [error description]);
    return;
  }
  
  MLog(@"onWimEventSessionStarted");
  
  NSString *jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  NSDictionary* dictionary = [jsonResponse JSONValue];//[NSDictionary dictionaryWithJSONString:jsonResponse];
  
  NSString* statusCode = [dictionary stringValueForKeyPath:@"response.statusCode"];
  
  if (!dictionary || [statusCode isEqualToString:@"200"]==NO)
  {
    if ([statusCode isEqualToString:@"607"]==YES)
    {
      _sessionAttempt = 0;
      MLog(@"account has been rate limited");
      return;
    }
    
    _sessionAttempt++;
    
    if (_sessionAttempt < 4)
    {
      MLog(@"retrying session start");
      [self startSession];
    }
    
    return;
  }
  
  _sessionAttempt = 0;
  [_sessionId release];
  _sessionId = [[dictionary stringValueForKeyPath:@"response.data.aimsid"] retain];
  [_fetchBaseUrl release];
  _fetchBaseUrl = [[dictionary stringValueForKeyPath:@"response.data.fetchBaseURL"] retain];
  
  NSMutableDictionary *myInfo = [[[NSMutableDictionary alloc] initWithDictionary:[dictionary valueForKeyPath:@"response.data.myInfo"]] autorelease];
  [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionMyInfoEvent object:self userInfo:myInfo]; 
  
  [_myInfo release];
  _myInfo = [myInfo retain];
  
  if ([dictionary valueForKeyPath:@"response.data.myInfo.aimId"])
  {
    // TODO:should this set?  or just ASSERT to be TRUE?
    [self setUserName:[dictionary valueForKeyPath:@"response.data.myInfo.aimId"]];
  }
 
#if 1 // do we not get our own statusMsg?
  if ([dictionary valueForKeyPath:@"response.data.myInfo.statusMsg"] == nil)
  {
    // dispatch a presence update event
    NSString *aimId = [dictionary valueForKeyPath:@"response.data.myInfo.aimId"];
    if (aimId)
      [self requestPresenceForAimId:aimId];
  }
#endif
  
  _connected = YES;
  [[NSNotificationCenter defaultCenter] postNotificationName:kWimClientSessionOnline object:self];
  
  [self fetchEvents];
}        


- (void)onWimEventFetchEvents:(WimRequest *)wimRequest withError:(NSError *)error
{
  [_wimFetchRequest release];
  _wimFetchRequest = nil;
  
  if (error)
  {
    MLog(@"onWimEventFetchEvents failed with error: %@", [error description]);
    // TODO: send offline event
    return;
  }
  NSString* jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  MLog (jsonResponse);
  
  NSDictionary* aDictionary = [jsonResponse JSONValue];//[NSDictionary dictionaryWithJSONString:jsonResponse];
  
  NSString* statusCode = [aDictionary stringValueForKeyPath:@"response.statusCode"];
  if ([statusCode isEqualToString:@"200"])
  {
    NSTimeInterval nextFetch = [[aDictionary stringValueForKeyPath:@"response.data.timeToNextFetch"] intValue];
    [_fetchBaseUrl release];
    _fetchBaseUrl = [[aDictionary stringValueForKeyPath:@"response.data.fetchBaseURL"] retain];
    
    NSArray* events = [aDictionary valueForKeyPath:@"response.data.events"];
    [self parseEvents:events];
    
    if (_pendingEndSession==NO)
    {
      // change this to delay - timeIntervals as in seconds -- timeToNextFetch is in milliseconds
      nextFetch = nextFetch / 1000;
      
      if (nextFetch == 0 )
      {
        // wait at least a second
        nextFetch = 1;
      }
      
      [self performSelector:@selector(fetchEvents) withObject:self afterDelay:nextFetch];
    }
  }
  else
  {
    MLog(@"received unexpected fetchfailure code");
  }
}

- (void)onWimEventEndSession:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventEndSession failed with error: %@", [error description]);
    // continue reseting application state
  }

  _connected = NO;
  _pendingEndSession = NO;
  [[NSNotificationCenter defaultCenter] postNotificationName:kWimClientSessionOffline object:self];
}


- (void)onWimEventPresenceResponse:(WimRequest *)wimRequest withError:(NSError *)error
{  
  if (error)
  {
    MLog(@"onWimEventPresenceResponse failed with error: %@", [error description]);
    return;
  }
  
  NSString* jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  NSDictionary* dictionary =  [jsonResponse JSONValue];
  NSNumber *statusCode = [dictionary valueForKeyPath:@"response.statusCode"];
  
  if ([statusCode isEqual:[NSNumber numberWithInt:200]])
  {
    NSEnumerator *buddies = [[dictionary valueForKeyPath:@"response.data.users"] objectEnumerator];
    NSMutableDictionary *buddy;
    while (buddy = [buddies nextObject])
    {
      [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionPresenceEvent object:self userInfo:buddy];
    }
  }
}

- (void)onWimEventIMSentResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventIMSentResponse failed with error: %@", [error description]);
    return;
  }
    
  NSString* jsonString = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  MLog (jsonString);
  
  NSDictionary* jsonDictionary =  [jsonString JSONValue];//[NSDictionary dictionaryWithJSONString:jsonString];
  NSNumber *statusCode = [jsonDictionary valueForKeyPath:@"response.statusCode"];
  
  
  if ([statusCode isEqual:[NSNumber numberWithInt:200]])
  {
    [[NSNotificationCenter defaultCenter] postNotificationName:kWimClientIMSent object:self userInfo:jsonDictionary];
  }
}

- (void)onWimEventSetStateResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventPresenceResponse failed with error: %@", [error description]);
    return;
  }
  
  NSString* jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  NSDictionary* dictionary = [jsonResponse JSONValue];//[NSDictionary dictionaryWithJSONString:jsonResponse];
  NSNumber *statusCode = [dictionary valueForKeyPath:@"response.statusCode"];
  
  if ([statusCode isEqual:[NSNumber numberWithInt:200]])
  {
    NSDictionary *buddy  = [dictionary valueForKeyPath:@"response.data.myInfo"];
    
    [_myInfo release];
    _myInfo = [buddy retain];
    
    //[[NSNotificationCenter defaultCenter]  postNotificationName:@"prenotifiy.buddy" object:buddy];

    
    //NSString* notificationName = [NSString stringWithFormat:@"%@.%@", kWimSessionPresenceEvent, [buddy valueForKey:@"aimId"]];
    //[[NSNotificationCenter defaultCenter]  postNotificationName:notificationName object:buddy];
    [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionMyInfoEvent object:self userInfo:buddy];
  }  
}

- (void)onWimEventSetStatusResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventSetStatusResponse failed with error: %@", [error description]);
    return;
  }
  
  NSString* jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  NSDictionary* dictionary = [jsonResponse JSONValue];//[NSDictionary dictionaryWithJSONString:jsonResponse];
  NSNumber *statusCode = [dictionary valueForKeyPath:@"response.statusCode"];
  
  if ([statusCode isEqual:[NSNumber numberWithInt:200]])
  {
//    NSDictionary *buddy  = [dictionary valueForKeyPath:@"response.data.myInfo"];
    
//    [_myInfo release];
//    _myInfo = [buddy retain];
    
//    NSString* notificationName = [NSString stringWithFormat:@"%@.%@", kWimSessionPresenceEvent, [buddy valueForKey:@"aimId"]];
//    [[NSNotificationCenter defaultCenter]  postNotificationName:notificationName object:buddy];
//    [[NSNotificationCenter defaultCenter]  postNotificationName:kWimSessionMyInfoEvent object:buddy];
  }  
}

- (void)onWimEventSetProfileResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventSetProfileResponse failed with error: %@", [error description]);
  }
}  

- (void)onWimEventSetBuddyAttributeResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventSetBuddyAttributeResponse failed with error: %@", [error description]);
  }
}  

- (void)onWimEventRemoveBuddyResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventRemoveBuddyResponse failed with error: %@", [error description]);
  }
}


- (void)onWimEventAddBuddyResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventAddBuddyResponse failed with error: %@", [error description]);
  }
  else
  {
    NSString* jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
    NSDictionary* dictionary = [jsonResponse JSONValue];//[NSDictionary dictionaryWithJSONString:jsonResponse];
    NSNumber *statusCode = [dictionary valueForKeyPath:@"response.statusCode"];
    
    if ([statusCode intValue] == 200)
    {
      // if success - then set the friendlyname if specified
      
      NSArray *userData = [wimRequest userData];
      if ([userData count] == 2)
      {
        [self setFriendlyName:[userData objectAtIndex:1] toAimId:[userData objectAtIndex:0]];
      }
    }
  }
}  


- (void)onWimEventSetLargeBuddyIconResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventSetLargeBuddyIconResponse failed with error: %@", [error description]);
    return;
  }

  //NSString* jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  //NSDictionary* dictionary = [jsonResponse JSONValue];//[NSDictionary dictionaryWithJSONString:jsonResponse];
  //NSNumber *statusCode = [dictionary valueForKeyPath:@"response.statusCode"];
}  

- (void)onWimEventMoveGroupResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventMoveGroupResponse failed with error: %@", [error description]);
    return;
  }
  
  //NSString* jsonResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];
  //NSDictionary* dictionary = [jsonResponse JSONValue];//[NSDictionary dictionaryWithJSONString:jsonResponse];
  //NSNumber *statusCode = [dictionary valueForKeyPath:@"response.statusCode"];
}  

- (void)onWimEventGetHostBuddyInfoResponse:(WimRequest *)wimRequest withError:(NSError *)error
{
  if (error)
  {
    MLog(@"onWimEventGetHostBuddyInfoResponse failed with error: %@", [error description]);
    return;
  }
  
  // resulting data is HTML
  NSString *htmlResponse = [[[NSString alloc] initWithData:[wimRequest data] encoding:NSUTF8StringEncoding] autorelease];

  NSArray *userData = [wimRequest userData];
  if ([userData count] == 1)
  {
    NSString *aimId = [userData objectAtIndex:0];

    NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                aimId, WimSessionBuddyInfoAimIdKey,
                                htmlResponse ? htmlResponse : @"", WimSessionBuddyInfoHtmlKey,
                                nil];
                                
    [[NSNotificationCenter defaultCenter] postNotificationName:kWimSessionHostBuddyInfoEvent object:nil userInfo:dictionary];
  }
}  


#pragma mark Class Accessors

- (void)setDelegate:(id<WimSessionSecondaryChallengeDelegate>)aDelegate
{
  _delegate = aDelegate; // weak
}

- (id)delegate
{
  return _delegate;
}

// this method is really meant for testing of captcha based secondary challenges
- (void)setForceCaptcha:(BOOL)aForceCaptcha
{
  _forceCaptcha = aForceCaptcha;
}

- (void)setUserName:(NSString*)username
{
  username = [username copy];
  [_userName autorelease];
  _userName = username;
  [[NSNotificationCenter defaultCenter]  postNotificationName:@"prenotifiy.buddy" object:self userInfo:[self myInfo]];
}

- (NSString *)userName
{
  return _userName;
}

- (void)setPassword:(NSString*)password
{
  password = [password copy];
  [_password autorelease];
  _password = password;
}

- (NSString *)password
{
  return _password;
}

- (NSDictionary *)buddyList
{
  return _buddyList;
}


- (void)setBuddyList:(NSDictionary *)buddyList
{
  NSMutableDictionary* mutableList = [buddyList mutableCopy];
  [_buddyList autorelease];
  _buddyList = mutableList;
  [self buddyListArrived];
}


- (NSString*)aimId
{
  return _userName;
} 

- (NSDictionary*)myInfo
{
  if(!_myInfo) 
  {
    MLog(@"Returning minimal myInfo!");
    NSMutableDictionary *fakeMyInfo = [[NSMutableDictionary alloc] init];
    [fakeMyInfo setObject:[self userName] forKey:@"aimId"];
    [fakeMyInfo setObject:[self userName] forKey:@"displayId"];
    
    [[NSNotificationCenter defaultCenter]  postNotificationName:@"prenotifiy.buddy" object:self userInfo:fakeMyInfo];
    
    _myInfo = fakeMyInfo;
  }
  return _myInfo;
} 



@end
