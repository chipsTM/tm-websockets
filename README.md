# [WebSockets](https://openplanet.dev/plugin/websockets)

![Image](./opfiles/WebSockets.png)

Provides a Websocket Client (secure and unsecure) and Server (unsecure) for Openplanet developers to use for plugins.


Example Client Usage
```
// setup a coroutine for repeatedly fetching messages from server
void ReadLoop() {
    while (true) {
        // returns a dictionary
        auto msg = websocket.GetMessage();
        if (msg.Exists("message")) {
            print(string(msg["message"]).Trim());
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
    websocket.Close();

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

    // Close websockets server when finished
    websocket.Close();
}
```