# RoomMultimediaMsg

###RoomMessageViewController
原来的*RoomViewController*，不支持图片，语音，地理定位。只是单纯的纯文本。*RoomMessageViewController*做了这些（图片，语音，地理定位）支持。

*RoomMessageViewController* 主要使用
*PeerMessageViewController*的多媒体上传和处理逻辑，对应附加上  *RoomViewController*里面所添加的聊天室接口的监听，以及进入聊天室和退出聊天室两个命令的调用。 

*RoomMessageViewController*的对消息ack的处理没有采用*RoomViewController*自身存储*self.msgs*。而是采用*[RoomOutbox instance].msgs*。


###RoomOutbox 

*RoomViewController*只支持文本消息，采用了ViewController自己存储msgs，在处理ack时直接遍历。因为要支持（图片，语音，地理定位）需要调用*RoomOutbox*来处理上传，转存到*RoomOutbox*。

文本消息发送后，暂存到[[RoomOutbox instance].msgs。
	
	     RoomMessage *im = [[RoomMessage alloc] init];
        im.sender = message.sender;
        im.receiver = message.receiver;
        im.content = message.rawContent;
        [[IMService instance] sendRoomMessage:im];
        
        NSNumber *o = [NSNumber numberWithLongLong:message.msgLocalID];
        NSNumber *k = [NSNumber numberWithLongLong:(long long)im];
        [[RoomOutbox instance].msgs setObject:o forKey:k];
 
多媒体发送暂存到[[RoomOutbox instance].msgs

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

*RoomMessageViewController*做ACK处理时，遍历[RoomOutbox instance].msgs

	- (void)onRoomMessageACK:(RoomMessage*)rm {
    	NSNumber *k = [NSNumber numberWithLongLong:(long long)rm];
   	 	NSNumber *o = [[RoomOutbox instance].msgs objectForKey:k];
    	int msgLocalID = [o intValue];
    
    	IMessage *msg = [self getMessageWithID:msgLocalID];
    	msg.flags = msg.flags|MESSAGE_FLAG_ACK;
	}

###RoomOutbox的msgs clear的时机
调用leaveRoom后清空RoomOutbox的msgs。
	
    [[IMService instance] leaveRoom:self.roomID];
    [[RoomOutbox instance] clearMsgs];