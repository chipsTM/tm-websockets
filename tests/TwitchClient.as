void ReadLoop() {
    while (true) {
        auto msg = websocket.GetMessage();
        if (msg.Exists("message")) {
            print(string(msg["message"]).Trim());
        }
        
        yield();
    }
}

Net::SecureWebSocket@ websocket;

void Main() {
    @websocket = Net::SecureWebSocket();

    if (!websocket.Connect("irc-ws.chat.twitch.tv", 443)){
        print("unable to connect to websocket");
        return;
    }

    startnew(ReadLoop);

    websocket.SendMessage("PASS XXXXXXXXXXXXXXX");
    websocket.SendMessage("NICK chipstm");
    websocket.SendMessage("JOIN #chipstm");

    websocket.SendMessage("PRIVMSG #chipstm :Test message from TM Websockets");

    websocket.Close();
}