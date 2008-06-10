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


#import "WimRequest.h"
#import "MLog.h"
#import "WimEvents.h"

static int WimRequestId = 0;

@implementation WimRequest

+ (int)nextRequestId
{
  return WimRequestId++;
}

+ (WimRequest *)wimRequest
{
  return [[[WimRequest alloc] init] autorelease];
}


- (void)dealloc
{
  [data release];
  [urlConnection release];
  [postData release];
  [userData release];
  [super dealloc];
}

- (id)delegate
{
  return delegate;
}

- (void)setDelegate:(id)aDelegate
{
  delegate = aDelegate; //weak
}

- (void)setAction:(SEL)aSelector
{
  action = aSelector;
}

- (SEL)action
{
  return action;
}


- (NSData *)data
{
	return data;
}

- (void)setUserData:(id)aUserData
{
	if (userData == aUserData)
		return;
	[userData release];
	userData = [aUserData retain];
}

- (id)userData
{
	return userData;
}

- (void)setSynchronous:(BOOL)useOnlyForEndSession
{
  synchronous = useOnlyForEndSession;
}

- (void)requestURL:(NSURL*)url 
{
  [self requestURL:url withData:nil];
}

- (void)requestURL:(NSURL*)url withData:(NSData*)aData
{
  [self retain];
  [postData release];
  postData = [aData retain];
  
  [data release];
  data = [[NSMutableData alloc] init];
	
	requestURL = [url retain];
  
  // lets load the url asynchronously here!
  NSMutableURLRequest*   urlRequest = [NSMutableURLRequest requestWithURL: url
                                                              cachePolicy: NSURLRequestReloadIgnoringCacheData
                                                          timeoutInterval: 30.0f];
  if (postData)
  {
    [urlRequest setHTTPBody:postData];
    [urlRequest setHTTPMethod:@"POST"];
  }

  if (urlConnection)
  {
    [urlConnection cancel];
    [urlConnection autorelease];
  }
  
  
  if (synchronous == NO)
  {
    urlConnection = [[NSURLConnection connectionWithRequest: urlRequest
                                                           delegate: self] retain];  
    // Send a generic notification that a request is being started
    NSDictionary *infoDict = [NSDictionary dictionaryWithObject:requestURL forKey:@"URL"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kWimRequestDidStart object:self userInfo:infoDict];
  }
  else
  {
     NSURLResponse* response = [[[NSURLResponse alloc] init] autorelease];  
     NSError* error = [[[NSError alloc] init] autorelease];  
     /*NSData* data = */[NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&response error:&error];  
  }
}


#pragma mark NSURLConnection delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
  if ([response isKindOfClass:[NSHTTPURLResponse class]])
    MLog(@"didReceiveResponse (%u)", [(NSHTTPURLResponse*)response statusCode]);

  
  if (urlConnection == connection)
  {
    [data setLength:0];
  }
  
  // we might get a 302, which means we may need to re-direct to the new location ourselves!
  NSString*   newlocationString = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"Location"];
  
  if ([(NSHTTPURLResponse*)response statusCode] == 302 && newlocationString)
  {
    [urlConnection cancel];
    [urlConnection release];
    urlConnection = nil;
	  // Report that this transaction finished, as we will be starting a new one
	  NSDictionary *closeDict = [NSDictionary dictionaryWithObject:requestURL forKey:@"URL"];
	  [[NSNotificationCenter defaultCenter] postNotificationName:kWimRequestDidFinish object:self userInfo:closeDict];
	  [requestURL release];
    NSURL* url = [NSURL URLWithString: newlocationString];
	  requestURL = [url retain];
    
    NSURLRequest* packageURLRequest = [NSURLRequest requestWithURL: url
                                                    cachePolicy: NSURLRequestReloadIgnoringCacheData
                                                    timeoutInterval: 30.0f];
    
    urlConnection = [[NSURLConnection connectionWithRequest: packageURLRequest
                                                           delegate: self] retain];
	  
	  // Send a generic notification that a request is being started
	  NSDictionary *startDict = [NSDictionary dictionaryWithObject:requestURL forKey:@"URL"];
	  [[NSNotificationCenter defaultCenter] postNotificationName:kWimRequestDidStart object:self userInfo:startDict];
  }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)aData
{  
  MLog(@"didReceiveData (%u)", [aData length]);
  
  if (urlConnection == connection)
  {
    [data appendData: aData];
  }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{  
  MLog(@"connectionDidFinishLoading");
  
  if (urlConnection == connection)
  {
    MLog ([connection description]);

    if (delegate)
      [delegate performSelector:action withObject:self withObject:nil];
  }
	
	// Send a generic notification that a request is finished
	NSDictionary *infoDict = [NSDictionary dictionaryWithObject:requestURL forKey:@"URL"];
	[[NSNotificationCenter defaultCenter] postNotificationName:kWimRequestDidFinish object:self userInfo:infoDict];
	[requestURL release];
  [self autorelease];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)connectionError
{  
  MLog(@"didFailWithError (%@)", [connectionError description]);
  
  if (urlConnection == connection)
  {
    [data setLength:0];

    if (delegate)
      [delegate performSelector:action withObject:self withObject:nil];
  }
	
	// Send a generic notification that a request is finished
	NSDictionary *infoDict = [NSDictionary dictionaryWithObject:requestURL forKey:@"URL"];
	[[NSNotificationCenter defaultCenter] postNotificationName:kWimRequestDidFinish object:self userInfo:infoDict];
	[requestURL release];
  [self autorelease];
}

@end

#pragma mark -

@implementation NSObject (KeyPathExtensions)
- (NSString*) stringValueForKeyPath:(NSString*)keyPath
{
   NSValue* value = [self valueForKeyPath:keyPath];
   return [value description];
}
@end
