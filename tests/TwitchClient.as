void ReadLoop() {
    while (true) {
        // important to prevent crashes
        if (websocket is null) {
            break;
        }

        // returns a dictionary
        auto msg = websocket.GetMessage();

        // check if message exists and print
        if (msg.Exists("message")) {
            print(string(msg["message"]).Trim());
        }
        
        // can check for close code and reason
        if (msg.Exists("closeCode")) {
            print(uint16(msg["closeCode"]));
            print(string(msg["reason"]));
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

    // websocket.SendMessage("PRIVMSG #chipstm :Test message from TM Websockets");

    sleep(15000);

    websocket.Close();
    @websocket = null;
}