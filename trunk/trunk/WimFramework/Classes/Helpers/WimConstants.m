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

#import "WimPlatform.h"
#import "WimConstants.h"



NSString* kUrlFetchTimeout = @"28000";

NSString* kAuthOffMethod = @"auth/logout";

NSString* kAPIBaseURL = @"http://api.oscar.aol.com/";
NSString* kAuthBaseURL = @"https://api.screenname.aol.com/";

NSString* kUrlGetClientLogin = @"%@auth/clientLogin"; // requires kAuthBaseURL

NSString* kUrlStartSession = @"%@aim/startSession?f=json&r=dk=%@&a=%a"; // requires kAPIBaseURL, requestId, a
NSString* kUrlEndSession = @"%@aim/endSession?f=json&aimsid=%@"; // requires kAPIBaseURL, aimsid
NSString* kUrlFetchRequest = @"%@&f=json&r=%d&timeout=%@ "; // requires: fetchBaseUrl, requestId, aimSid, timeout
NSString* kUrlPresenceRequest = @"%@presence/get?f=json&k=%@&t=%@&awayMsg=1&profileMsg=1&emailLookup=1&location=1&memberSince=1"; // requires: kAPIBaseURL,  key, targetAimId
NSString* kUrlSendIMRequest = @"%@im/sendIM?f=json&k=%@&a=%@&aimsid=%@&r=%d&message=%@&t=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid,requestid,message, target
NSString *kUrlSetState = @"%@presence/setState?f=json&k=%@&aimsid=%@&r=%d&view=%@"; // requires kAPIBaseURL, key, authtoken, requestid, state
NSString *kUrlUploadExpression = @"%@expressions/upload?f=json&k=%@&a=%@&aimsid=%@&r=%d&type=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, expression type
NSString *kUrlAddBuddy = @"%@buddylist/addBuddy?f=json&k=%@a=%@&aimsid=%@&r=%d&buddy=%@&group=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, newBuddy, groupName
NSString *kUrlSetBuddyAttribute = @"%@buddylist/setBuddyAttribute?f=json&k=%@a=%@&aimsid=%@&r=%d&buddy=%@&friendly=%@"; // requires: kAPIBaseURL, key, authtoken, aimSid, requestid, aimId, friendlyName
// Fetched Event
NSString *kWimSessionMyInfoEvent = @"com.aol.aim.event.myInfoEvent";
NSString *kWimSessionPresenceEvent = @"com.aol.aim.event.presenceEvent";
NSString *kWimSessionTypingEvent = @"com.aol.aim.event.typingEvent";
NSString *kWimSessionDataIMEvent = @"com.aol.aim.event.dataIMEvent";
NSString *kWimSessionIMEvent = @"com.aol.aim.event.imEvent";
NSString *kWimSessionOfflineIMEvent = @"com.aol.aim.event.offineIMEvent";
NSString *kWimSessionBuddyListEvent = @"com.aol.aim.event.buddyListEvent";
NSString *kWimSessionSessionEndedEvent = @"com.aol.aim.event.sessionEndedEvent";
NSString *kWimSessionHostBuddyInfoEvent = @"com.aol.aim.event.hostBuddyInfoEvent";
 


// Client Events
NSString *kWimClientIMSent = @"com.aol.aim.client.imSent";
NSString *kWimClientSessionOnline = @"com.aol.aim.client.session.online";
NSString *kWimClientSessionOffline = @"com.aol.aim.client.session.offline";

// WIMRequest events
NSString *kWimRequestDidStart = @"com.aol.aim.requestDidStart";
NSString *kWimRequestDidFinish = @"com.aol.aim.requestDidFinish";

NSString *WimSessionBuddyInfoAimIdKey = @"WimSessionBuddyInfoAimId";
NSString *WimSessionBuddyInfoHtmlKey = @"WimSessionBuddyInfoHtml";

