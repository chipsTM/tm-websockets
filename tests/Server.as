void Main() {
    // We can only start a unsecure websockets server
    Net::WebSocket@ websocket = Net::WebSocket();

    if (!websocket.Listen("localhost", 5432)){
        print("unable to start websocket server");
        return;
    }

    int ind = 0;
    while (ind < 1000) {
        // Clients is an array of websocket connections accepted by the server
        for (uint i = 0; i < websocket.Clients.Length; i++) {
            auto wsc = websocket.Clients[i];
            wsc.SendMessage("test");
            auto data = wsc.GetMessage();
            if (data.Exists("message")){
                print(string(data["message"]));
            }
        }
        ind += 1;
        // print(ind);
        yield();
    }

    // Good practice to close clients first before server
    for (uint i = 0; i < websocket.Clients.Length; i++) {
        auto wsc = websocket.Clients[i];
        wsc.Close(3000, "closed from TM sockets");
    }

    // Close websockets server when finished
    websocket.Close();
}