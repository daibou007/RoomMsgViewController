/*                                                                            
  Copyright (c) 2014-2015, GoBelieve     
    All rights reserved.		    				     			
 
  This source code is licensed under the BSD-style license found in the
  LICENSE file in the root directory of this source tree. An additional grant
  of patent rights can be found in the PATENTS file in the same directory.
*/

#import "RoomOutbox.h"
#import "IMHttpAPI.h"
#import "FileCache.h"
#import "IMService.h"
#import "PeerMessageDB.h"
#import "GroupMessageDB.h"
#import "wav_amr.h"
#import "UIImageView+WebCache.h"

@implementation RoomOutbox
+(RoomOutbox*)instance {
    static RoomOutbox *box;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!box) {
            box = [[RoomOutbox alloc] init];
        }
    });
    return box;
}

-(id)init {
    self = [super init];
    if (self) {
        self.msgs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)clearMsgs{
    if (self.msgs) {
        [self.msgs removeAllObjects];
    }
}

- (void)sendMessage:(IMessage*)msg{
    RoomMessage *im = [[RoomMessage alloc] init];
    im.sender = msg.sender;
    im.receiver = msg.receiver;
    im.content = msg.rawContent;
    [[IMService instance] sendRoomMessage:im];
    
    NSNumber *o = [NSNumber numberWithLongLong:msg.msgLocalID];
    NSNumber *k = [NSNumber numberWithLongLong:(long long)im];
    [self.msgs setObject:o forKey:k];
}

-(void)markMessageFailure:(IMessage*)msg {
    
}

-(void)saveMessageAttachment:(IMessage*)msg url:(NSString*)url {
    
}
@end
