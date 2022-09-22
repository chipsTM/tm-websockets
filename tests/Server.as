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
            wsc.SendData("test");
            auto data = wsc.ReadData();
            if (data.Exists("message")){
                print(string(data["message"]));
            }
        }
        yield();
    }

    // Close websockets server when finished
    websocket.Close();
}