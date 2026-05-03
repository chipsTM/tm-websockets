void Main() {
    // We can only start a unsecure websockets server
    Net::WebSocket@ wsServer = Net::WebSocket();

    // start server with default of 5 max clients
    // you can pass in third argument to decrease or increase 
    if (!wsServer.Listen("localhost", 5432)){
        print("unable to start websocket server");
        return;
    }

    // DON'T call these methods on the server object
    // warning will be shown and nothing will happen
    // wsServer.SendMessage("test");
    // dictionary@ test = wsServer.GetMessage();

    
    int ind = 0;
    while (ind < 1000) { // simulating frames as example, normally you would place in your Update function or other appropriate location

        // Clients is an array of websocket connections accepted by the server
        for (uint i = 0; i < wsServer.Clients.Length; i++) {
            Net::WebSocketClient@ wsClient = wsServer.Clients[i];
            wsClient.SendMessage("test");
            dictionary@ data = wsClient.GetMessage();
            if (data.Exists("message")){
                print(string(data["message"]));
            }
        }

        ind += 1;
        // print(ind);
        yield();
    }

    // Good practice to close clients first before server
    for (uint i = 0; i < wsServer.Clients.Length; i++) {
        Net::WebSocketClient@ wsClient = wsServer.Clients[i];
        wsClient.Close(3000, "closed from TM sockets");
    }

    // Close websockets server when finished
    wsServer.Close();
}