# [WebSockets](https://openplanet.dev/plugin/websockets)


Provides a Websocket Client (secure and unsecure) and Server (unsecure) for Openplanet developers to use for plugins.


Example Client Usage
```
void Main() {
    // we can spin up a secure and unsecure client
    Net::WebSocket@ websocket = Net::SecureWebSocket();
    // Net::WebSocket@ websocket = Net::WebSocket();

    // setup a callback for what to do if we get data from the server
    @(websocket.OnMessage) = function(dictionary@ evt) {
        if (evt.Exists("message")) {
            print(string(evt["message"]));
        } else {
            print("not a message");
        }
    };

    if (!websocket.Connect("localhost", 5432)){
        print("unable to connect to websocket");
        return;
    }

    // we can also send data to server
    while (true) {
        websocket.Send("testing");
        sleep(100);
    }
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
        for (uint i = 0; i < websocket.Clients.Length; i++) {
            auto wsc = websocket.Clients[i];
            wsc.SendData("test");
            auto data = wsc.ReadData();
            if (data.Exists("message")){
                print(string(data["message"]));
            }
        }
        yield();
    }
}
```