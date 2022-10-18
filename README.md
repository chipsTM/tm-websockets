# [WebSockets](https://openplanet.dev/plugin/websockets)

![Image](./opfiles/WebSockets.png)

Provides a Websocket Client (secure and unsecure) and Server (unsecure) for Openplanet developers to use for plugins.


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

void Main() {
    // we can spin up a secure and unsecure client
    Net::WebSocket@ websocket = Net::SecureWebSocket();
    // Net::WebSocket@ websocket = Net::WebSocket();


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
    Net::WebSocket@ websocket = Net::WebSocket();

    if (!websocket.Listen("localhost", 5432)){
        print("unable to start websocket server");
        return;
    }

    while (true) {
        // Clients is an array of websocket connections accepted by the server
        for (uint i = 0; i < websocket.Clients.Length; i++) {
            auto wsc = websocket.Clients[i];
            wsc.SendMessage("test");
            auto data = wsc.GetMessage();
            if (data.Exists("message")){
                print(string(data["message"]));
            }
        }
        yield();
    }

    // Good practice to close clients first before server
    for (uint i = 0; i < websocket.Clients.Length; i++) {
        auto wsc = websocket.Clients[i];
        wsc.Close();
    }

    // Close websockets server when finished
    websocket.Close();
}
```