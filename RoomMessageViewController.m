/*                                                                            
  Copyright (c) 2014-2015, GoBelieve     
    All rights reserved.		    				     			
 
  This source code is licensed under the BSD-style license found in the
  LICENSE file in the root directory of this source tree. An additional grant
  of patent rights can be found in the PATENTS file in the same directory.
*/

#import "RoomMessageViewController.h"
#import "FileCache.h"
#import "AudioDownloader.h"
#import "DraftDB.h"
#import "IMessage.h"
#import "Constants.h"
#import "RoomOutbox.h"
#import "UIImage+Resize.h"
#import "SDImageCache.h"

#define PAGE_COUNT 10

@interface RoomMessageViewController ()<OutboxObserver, AudioDownloaderObserver,RoomMessageObserver>

@property(nonatomic)int msgID;

@end

@implementation RoomMessageViewController

- (void)dealloc {
    NSLog(@"peermessageviewcontroller dealloc");
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setNormalNavigationButtons];

    self.navigationItem.title = @"聊天室";
    
    DraftDB *db = [DraftDB instance];
    NSString *draft = [db getDraft:self.receiver];
    [self setDraft:draft];
    
    [self addObserver];
    
    [[IMService instance] enterRoom:self.roomID];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void)addObserver {
    [[AudioDownloader instance] addDownloaderObserver:self];
    [[RoomOutbox instance] addBoxObserver:self];
    [[IMService instance] addConnectionObserver:self];
    [[IMService instance] addRoomMessageObserver:self];
}

-(void)removeObserver {
    [[AudioDownloader instance] removeDownloaderObserver:self];
    [[RoomOutbox instance] removeBoxObserver:self];
    [[IMService instance] removeConnectionObserver:self];
    [[IMService instance] removeRoomMessageObserver:self];
}

- (int64_t)sender {
    return self.uid;
}

- (int64_t)receiver {
    return self.roomID;
}

- (BOOL)isMessageSending:(IMessage*)msg {
    return [[IMService instance] isPeerMessageSending:self.uid id:msg.msgLocalID];
}

- (BOOL)isInConversation:(IMessage*)msg {
   BOOL r =  (msg.sender == self.uid && msg.receiver == self.roomID) ||
                (msg.receiver == self.uid && msg.sender == self.roomID);
    return r;
}

-(void)saveMessageAttachment:(IMessage*)msg address:(NSString*)address {
    //以附件的形式存储，以免第二次查询
    MessageAttachmentContent *att = [[MessageAttachmentContent alloc] initWithAttachment:msg.msgLocalID address:address];
    IMessage *attachment = [[IMessage alloc] init];
    attachment.sender = msg.sender;
    attachment.receiver = msg.receiver;
    attachment.rawContent = att.raw;
    [self saveMessage:attachment];
}


-(BOOL)saveMessage:(IMessage*)msg {
    self.msgID = self.msgID + 1;
    msg.msgLocalID = self.msgID;
    return YES;
}

-(BOOL)removeMessage:(IMessage*)msg {
    return YES;
}
-(BOOL)markMessageFailure:(IMessage*)msg {
    return YES;
}

-(BOOL)markMesageListened:(IMessage*)msg {
    return YES;
}

-(BOOL)eraseMessageFailure:(IMessage*)msg {
    return YES;
}

-(void) setNormalNavigationButtons{
    
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"对话"
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(returnMainTableViewController)];
    
    self.navigationItem.leftBarButtonItem = item;
}

- (void)returnMainTableViewController {
    DraftDB *db = [DraftDB instance];
    [db setDraft:self.roomID draft:[self getDraft]];
    
    [self removeObserver];
    [self stopPlayer];
    [[IMService instance] leaveRoom:self.roomID];
    [[RoomOutbox instance] clearMsgs];
    
    NSNotification* notification = [[NSNotification alloc] initWithName:CLEAR_PEER_NEW_MESSAGE
                                                                 object:[NSNumber numberWithLongLong:self.roomID]
                                                               userInfo:nil];
    [[NSNotificationCenter defaultCenter] postNotification:notification];

    [self.navigationController popViewControllerAnimated:YES];
}

//同IM服务器连接的状态变更通知
-(void)onConnectState:(int)state{
    if(state == STATE_CONNECTED){
        [self enableSend];
    } else {
        [self disableSend];
    }
}

- (void)loadConversationData {
    [self initTableViewData];
}

#pragma mark - RoomMessageObserver
-(void)onRoomMessage:(RoomMessage*)rm {
    IMessage *m = [[IMessage alloc] init];
    m.sender = rm.sender;
    m.receiver = rm.receiver;
    self.msgID = self.msgID + 1;
    m.msgLocalID = self.msgID;
    m.rawContent = rm.content;
    m.timestamp = [[NSDate date] timeIntervalSince1970];
    
    [self insertMessage:m];
}

-(void)onRoomMessageACK:(RoomMessage*)rm {
    NSNumber *k = [NSNumber numberWithLongLong:(long long)rm];
    NSNumber *o = [[RoomOutbox instance].msgs objectForKey:k];
    int msgLocalID = [o intValue];
    
    IMessage *msg = [self getMessageWithID:msgLocalID];
    msg.flags = msg.flags|MESSAGE_FLAG_ACK;
}

-(void)onRoomMessageFailure:(RoomMessage*)rm {
    NSNumber *k = [NSNumber numberWithLongLong:(long long)rm];
    NSNumber *o = [[RoomOutbox instance].msgs objectForKey:k];
    int msgLocalID = [o longValue];
    
    IMessage *msg = [self getMessageWithID:msgLocalID];
    msg.flags = msg.flags|MESSAGE_FLAG_FAILURE;
}


-(void)checkMessageFailureFlag:(IMessage*)msg {
    if (msg.isOutgoing) {
        if (msg.type == MESSAGE_AUDIO) {
            msg.uploading = [[RoomOutbox instance] isUploading:msg];
        } else if (msg.type == MESSAGE_IMAGE) {
            msg.uploading = [[RoomOutbox instance] isUploading:msg];
        }
        
        //消息发送过程中，程序异常关闭
        if (!msg.isACK && !msg.uploading &&
            !msg.isFailure && ![self isMessageSending:msg]) {
            [self markMessageFailure:msg];
            msg.flags = msg.flags|MESSAGE_FLAG_FAILURE;
        }
    }
}

-(void)checkMessageFailureFlag:(NSArray*)messages count:(int)count {
    for (int i = 0; i < count; i++) {
        IMessage *msg = [messages objectAtIndex:i];
        [self checkMessageFailureFlag:msg];
    }
}

- (void)sendMessage:(IMessage *)msg withImage:(UIImage*)image {
    msg.uploading = YES;
    [[RoomOutbox instance] uploadImage:msg withImage:image];
    NSNotification* notification = [[NSNotification alloc] initWithName:LATEST_PEER_MESSAGE object:msg userInfo:nil];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)sendMessage:(IMessage*)message {
    if (message.type == MESSAGE_AUDIO) {
        message.uploading = YES;
        [[RoomOutbox instance] uploadAudio:message];
    } else if (message.type == MESSAGE_IMAGE) {
        message.uploading = YES;
        [[RoomOutbox instance] uploadImage:message];
    } else {
        RoomMessage *im = [[RoomMessage alloc] init];
        im.sender = message.sender;
        im.receiver = message.receiver;
        im.content = message.rawContent;
        [[IMService instance] sendRoomMessage:im];
        
        NSNumber *o = [NSNumber numberWithLongLong:message.msgLocalID];
        NSNumber *k = [NSNumber numberWithLongLong:(long long)im];
        [[RoomOutbox instance].msgs setObject:o forKey:k];
    }

    
    NSNotification* notification = [[NSNotification alloc] initWithName:LATEST_PEER_MESSAGE object:message userInfo:nil];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

#pragma mark - Outbox Observer
- (void)onAudioUploadSuccess:(IMessage*)msg URL:(NSString*)url {
    if ([self isInConversation:msg]) {
        IMessage *m = [self getMessageWithID:msg.msgLocalID];
        m.uploading = NO;
        
        MessageAudioContent *content = msg.audioContent;
        NSString *c = [[FileCache instance] queryCacheForKey:content.url];
        if (c.length > 0) {
            NSData *data = [NSData dataWithContentsOfFile:c];
            if (data.length > 0) {
                [[FileCache instance] storeFile:data forKey:url];
            }
        }
    }
}

-(void)onAudioUploadFail:(IMessage*)msg {
    if ([self isInConversation:msg]) {
        IMessage *m = [self getMessageWithID:msg.msgLocalID];
        m.flags = m.flags|MESSAGE_FLAG_FAILURE;
        m.uploading = NO;
    }
}

- (void)onImageUploadSuccess:(IMessage*)msg URL:(NSString*)url {
    if ([self isInConversation:msg]) {
        IMessage *m = [self getMessageWithID:msg.msgLocalID];
        m.uploading = NO;
    }
}

- (void)onImageUploadFail:(IMessage*)msg {
    if ([self isInConversation:msg]) {
        IMessage *m = [self getMessageWithID:msg.msgLocalID];
        m.flags = m.flags|MESSAGE_FLAG_FAILURE;
        m.uploading = NO;
    }
}


#pragma mark - Audio Downloader Observer
- (void)onAudioDownloadSuccess:(IMessage*)msg {
    if ([self isInConversation:msg]) {
        IMessage *m = [self getMessageWithID:msg.msgLocalID];
        m.downloading = NO;
    }
}

- (void)onAudioDownloadFail:(IMessage*)msg {
    if ([self isInConversation:msg]) {
        IMessage *m = [self getMessageWithID:msg.msgLocalID];
        m.downloading = NO;
    }
}


#pragma mark - send message
- (void)sendLocationMessage:(CLLocationCoordinate2D)location address:(NSString*)address {
    IMessage *msg = [[IMessage alloc] init];
    
    msg.sender = self.sender;
    msg.receiver = self.receiver;

    MessageLocationContent *content = [[MessageLocationContent alloc] initWithLocation:location];
    msg.rawContent = content.raw;
    
    content = msg.locationContent;
    content.address = address;
    
    msg.timestamp = (int)time(NULL);
    msg.isOutgoing = YES;

    [self loadSenderInfo:msg];
    
    [self saveMessage:msg];
    
    [self sendMessage:msg];
    
    [[self class] playMessageSentSound];
    
    [self createMapSnapshot:msg];
    if (content.address.length == 0) {
        [self reverseGeocodeLocation:msg];
    } else {
        [self saveMessageAttachment:msg address:content.address];
    }
    [self insertMessage:msg];
}

- (void)sendAudioMessage:(NSString*)path second:(int)second {
    IMessage *msg = [[IMessage alloc] init];
    
    msg.sender = self.sender;
    msg.receiver = self.receiver;

    MessageAudioContent *content = [[MessageAudioContent alloc] initWithAudio:[self localAudioURL] duration:second];
    
    msg.rawContent = content.raw;
    msg.timestamp = (int)time(NULL);
    msg.isOutgoing = YES;
    
    [self loadSenderInfo:msg];
    
    //todo 优化读文件次数
    NSData *data = [NSData dataWithContentsOfFile:path];
    FileCache *fileCache = [FileCache instance];
    [fileCache storeFile:data forKey:content.url];
    
    [self saveMessage:msg];
    
    [self sendMessage:msg];
    
    [[self class] playMessageSentSound];
    
    [self insertMessage:msg];
}


- (void)sendImageMessage:(UIImage*)image {
    if (image.size.height == 0) {
        return;
    }
    
    IMessage *msg = [[IMessage alloc] init];
    
    msg.sender = self.sender;
    msg.receiver = self.receiver;

    CGRect screenRect = [[UIScreen mainScreen] bounds];
    CGFloat screenHeight = screenRect.size.height;
    float newHeight = screenHeight;
    float newWidth = newHeight*image.size.width/image.size.height;
    
    MessageImageContent *content = [[MessageImageContent alloc] initWithImageURL:[self localImageURL] width:newWidth height:newHeight];
    msg.rawContent = content.raw;
    msg.timestamp = (int)time(NULL);
    msg.isOutgoing = YES;
    
    [self loadSenderInfo:msg];
    
    UIImage *sizeImage = [image resizedImage:CGSizeMake(128, 128) interpolationQuality:kCGInterpolationDefault];
    image = [image resizedImage:CGSizeMake(newWidth, newHeight) interpolationQuality:kCGInterpolationDefault];
    
    [[SDImageCache sharedImageCache] storeImage:image forKey:content.imageURL];
    NSString *littleUrl =  [content littleImageURL];
    [[SDImageCache sharedImageCache] storeImage:sizeImage forKey: littleUrl];
    
    [self saveMessage:msg];
    
    [self sendMessage:msg withImage:image];
    
    [self insertMessage:msg];
    
    [[self class] playMessageSentSound];
}

-(void) sendTextMessage:(NSString*)text {
    IMessage *msg = [[IMessage alloc] init];
    
    msg.sender = self.sender;
    msg.receiver = self.receiver;

    MessageTextContent *content = [[MessageTextContent alloc] initWithText:text];
    msg.rawContent = content.raw;
    msg.timestamp = (int)time(NULL);
    msg.isOutgoing = YES;
    [self loadSenderInfo:msg];
    
    [self saveMessage:msg];
    
    [self sendMessage:msg];
    
    [[self class] playMessageSentSound];
    
    [self insertMessage:msg];
}


-(void)resendMessage:(IMessage*)message {
    message.flags = message.flags & (~MESSAGE_FLAG_FAILURE);
    [self eraseMessageFailure:message];
    [self sendMessage:message];
}


@end
