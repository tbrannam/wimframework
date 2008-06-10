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


// WIMSession provides an abstraction for the authentication and state housekeeping required for
// a Web AIM Session.

// Fetched Events from the Web AIM Server are parsed, and dispatched via NSNotification
// Event Notification constants are defined in WimEvents.h
// 
// http://dev.aol.com/aim/web/serverapi_reference

#import "WimPlatform.h"

@class WimRequest;
@class ClientLogin;
@protocol WimSessionSecondaryChallengeDelegate;


enum OnlineState
{
  OnlineState_online = 1,//	Online State
  OnlineState_invisible,//	Invisible - Only valid in myInfo objects
  OnlineState_notFound,//	For email lookups the address was not found
  OnlineState_idle,//	Idle State
  OnlineState_away,//	Away State
  OnlineState_mobile,//	Mobile State
  OnlineState_offline,//	Offline State
};

// WimSession is the client interface for the AIM WIM API, WIM is a Web API, which
// in this case uses JSON as a response format.   Authentication is handled internally
// by WimSession.   AIM Fetched Events (incoming IM, buddy list arrived, etc) 
// are broadcast as NSNotifications to registered listeners - use the constants defined in WimConstants.h


@interface WimSession : NSCoder<NSCoding> 
{
@private
  id _delegate;
  NSString *_userName;
  BOOL _forceCaptcha;
  NSMutableDictionary *_myInfo;
  NSMutableDictionary *_buddyList;
  NSString *_password;
  NSString *_sessionId;
  NSString *_authToken;
  NSString *_fetchBaseUrl;
  NSString *_sessionKey;
  BOOL _connected;
  BOOL _pendingEndSession;
  NSDate *_tokenExpiration;
  ClientLogin *_clientLogin;
  int _loginAttempt;
  int _sessionAttempt;
  WimRequest *_wimFetchRequest;
  NSString *_devID;
  NSString *_clientVersion;
  NSString *_clientName;
}

+ (WimSession*)defaultSession;

// associated delegate for Secondary Challenges
- (void)setDelegate:(id<WimSessionSecondaryChallengeDelegate>)aDelegate;
- (id)delegate;

// AIM Clients are required to use a application/developmenent ID - request yours at developer.aim.com
- (NSString *)devID;
- (void)setDevID:(NSString *)aDevID;

// AIM Clients are required to specify a client name
- (NSString *)clientName;
- (void)setClientName:(NSString *)aClientName;

// AIM Clients are required to specify a client version
- (NSString *)clientVersion;
- (void)setClientVersion:(NSString *)aClientVersion;

// Connect attempts to authenticate with the backend with the set username and password
// and then starts dispatching events from the WIM Backend
- (void)connect;

// Disconnect from the WIM backend
- (void)disconnect;

// WIM Session has an active session with the WIM backend
- (BOOL)connected;

// answerChallenge: is called by WimSessionSecondaryChallenge Delegates provide security answers, and proceed with authentication
- (void)answerChallenge:(NSString *)aAnswer;

// Add/Remove Buddies
- (void)addBuddy:(NSString *)aimId withFriendlyName:(NSString *)friendlyName toGroup:(NSString *)groupName;
- (void)removeBuddy:(NSString *)aimId fromGroup:(NSString *)groupName;

- (void)moveGroup:(NSString *)groupName beforeGroup:(NSString *)beforeGroup;

// Send a instant message to aAimId
- (void)sendInstantMessage:(NSString *)aMessage toAimId:(NSString *)aAimId;
- (void)requestPresenceForAimId:(NSString*)aAimId;

// Result returned via Notification kWimSessionHostBuddyInfoEvent, userInfo = {kWimSessionHostBuddyInfoAimId, kWimSessionHostBuddyInfoHtml}
- (void)requestBuddyInfoForAimId:(NSString*)aimId;
- (void)setState:(enum OnlineState)aState withMessage:(NSString *)aMessage;
- (void)setStatus:(NSString *)aMessage;
- (void)setProfile:(NSString *)aProfile;

- (void)setLargeBuddyIcon:(NSData*)iconData;

- (void)setUserName:(NSString*)username;
- (NSString *)userName;

- (void)setPassword:(NSString*)password;
- (NSString *)password;

// for testing of authentication piece only
- (void)setForceCaptcha:(BOOL)aForceCaptcha;


// returns the current presence information for this user
- (NSDictionary *)myInfo;

// returns the current identity of the user's aimID, which usually is the same as username
- (NSString *)aimId;

// Returns the most recent copy of the complete buddy list
- (NSDictionary *)buddyList;
@end


// WimSessionSecondaryChallenge delegate object - required to support secondary password
// challenges, such as Wrong Password, SecurID, or Captcha
// the delegate should implement a UI to prompt for requested information, and provide the answer
// to [WimSession answerChallenge:]
@protocol WimSessionSecondaryChallengeDelegate <NSObject>
- (void) wimSessionRequiresCaptcha:(WimSession *)aWimSession url:(NSURL *)captchaURL;
- (void) wimSessionRequiresPassword:(WimSession *)aWimSession;
- (void) wimSessionRequiresChallenge:(WimSession *)aWimSession;
@end
