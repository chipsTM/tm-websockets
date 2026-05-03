# [WebSockets](https://openplanet.dev/plugin/websockets)

![Image](./opfiles/WebSockets.png)

Provides a Websocket Client (secure and unsecure) and Server (unsecure) for Openplanet developers to use for plugins.

Minimum Openplanet Version: 1.29.6

Example Client Usage
```
// setup a coroutine for repeatedly fetching messages from server
void ReadLoop() {
    while (true) {
        // important to prevent crashes
        if (websocket is null) {
            break;
        }

        // returns a dictionary
        dictionary@ msg = websocket.GetMessage();

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

void Main() {
    Net::WebSocket@ websocket = Net::WebSocket();

    // client is now defaulted to secure
    // pass `secure = false` to unset
    if (!websocket.Connect("localhost", 5432)){
        print("unable to connect to websocket");
        return;
    }

    startnew(ReadLoop);

    // we can also send data to server
    while (true) {
        websocket.SendMessage("testing");
        sleep(100);
    }

    // Close websockets client when finished
    // Set websocket to null to stop ReadLoop
    websocket.Close();
    @websocket = null;
}
```

Example Server Usage
```
void Main() {
    // We can only start a unsecure websockets server
    Net::WebSocket@ wsServer = Net::WebSocket();

    if (!wsServer.Listen("localhost", 5432)){
        print("unable to start websocket server");
        return;
    }

    // simulating update loop
    while (true) {
        // Clients is an array of websocket connections accepted by the server
        for (uint i = 0; i < wsServer.Clients.Length; i++) {
            Net::WebSocketClient@ wsClient = wsServer.Clients[i];
            wsClient.SendMessage("test");
            dictionary@ data = wsClient.GetMessage();
            if (data.Exists("message")){
                print(string(data["message"]));
            }
        }
        yield();
    }

    // Good practice to close clients first before server
    for (uint i = 0; i < wsServer.Clients.Length; i++) {
        Net::WebSocketClient@ wsClient = wsServer.Clients[i];
        wsClient.Close();
    }

    // Close websockets server when finished
    wsServer.Close();
}
```