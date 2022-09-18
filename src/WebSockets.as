namespace Net {


    shared class WebSocketClient {
        Net::Socket@ Client;
        string Protocol;

        WebSocketClient(Net::Socket@ client, const string &in protocol) {
            @Client = @client;
            Protocol = protocol;
        }

        // Method for reading data from client
        dictionary@ ReadData() {
            if (Client !is null && Client.CanRead()) {
                MemoryBuffer buffer;
                while (Client.Available() != 0) {
                    buffer.Write(Client.ReadUint8());
                }
                
                return WSUtils::parseFrame(Client, buffer);
            } else {
                return dictionary = {};
            }
        }

        // method for sending Text data to client
        void SendData(const string &in data) {
            if (Client !is null && Client.CanWrite()) {
                MemoryBuffer@ msg = WSUtils::generateFrame(data);

                // Send msg over websockets
                if (!Client.Write(msg)) {
                    trace("Failed to send data to client");
                    Client.Close();
                    @Client = null;
                }
            }
        }
    }


    shared class WebSocket {
        // "private"
        Net::Socket@ tcpsocket;
        // "public"
        array<WebSocketClient@> Clients;
        uint MaxClients;

        funcdef void CALLBACK(dictionary@);
        CALLBACK@ OnMessage;

        WebSocket() {
            @tcpsocket = Net::Socket();
        }

        bool Connect(const string &in host, uint16 port, const string &in protocol = "") {
            int resourceIndex = host.IndexOf("/");
            string resource;
            string baseHost;
            if (resourceIndex != -1) {
                baseHost = host.SubStr(0, resourceIndex);
                resource = host.SubStr(resourceIndex);
            } else {
                baseHost = host;
                resource = "/";
            }

            if (!tcpsocket.Connect(baseHost, port)) {
                // trace("Could not establish a TCP socket!");
                return false;
            }

            while (!tcpsocket.CanWrite()) {
                yield();
            }

            // Generate Random Key
            MemoryBuffer nonce = MemoryBuffer(16);
            for (uint8 i = 0; i < nonce.GetSize(); i++) {
                nonce.Write(uint8(Math::Rand(0, 256)));
            }
            nonce.Seek(0);
            string key = nonce.ReadToBase64(nonce.GetSize());

            // to validate in response
            string b64key = WSUtils::computeHash(key);

            // Initiate Handshake
            if (!tcpsocket.WriteRaw(
                "GET " + resource + " HTTP/1.1\r\n" +
                "Host: " + baseHost + " \r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Key: " + key + "\r\n" +
                "Sec-WebSocket-Version: 13\r\n" +
                ((protocol != "") ? "Sec-WebSocket-Protocol: " + protocol + "\r\n" : "") +
                "\r\n"
            )) {
                // print("Couldn't send connection data.");
                return false;
            }

            bool validResponse = true;
            dictionary headers = WSUtils::parseResponseHeaders(@tcpsocket);
            if (string(headers["status_code"]) != "101") {
                validResponse = false;
            }
            if (string(headers["connection"]).ToLower() != "upgrade") {
                validResponse = false;
            }
            if (string(headers["upgrade"]).ToLower() != "websocket") {
                validResponse = false;
            }
            if (string(headers["sec-websocket-accept"]) != b64key) {
                validResponse = false;
            }
            if (!validResponse) {
                // trace("Unable to connect to websockets. Closing...");
                Close();
                return false;
            }
            
            // we've validated and now can send/receive messages
            startnew(CoroutineFunc(Loop));
            return true;
        }

        void Loop() {
            while (true) {
                if (tcpsocket.CanRead()) {

                    MemoryBuffer buffer;
                    while (tcpsocket.Available() != 0) {
                        buffer.Write(tcpsocket.ReadUint8());
                    }
                    
                    dictionary@ data = WSUtils::parseFrame(tcpsocket, buffer);
                    if (OnMessage !is null) {
                        OnMessage(data);
                    }
                }
                yield();
            }
        }

        void Send(const string &in data) {
            if (tcpsocket.CanWrite()) {
                auto msg = WSUtils::generateFrame(data, true);

                // Send msg over websockets
                if (!tcpsocket.Write(msg)) {
                    trace("unable to send message");
                    tcpsocket.Close();
                }
                
            }
        }


        bool Listen(const string &in host, uint16 port, uint maxClients = 5) {
            MaxClients = maxClients;

            if (!tcpsocket.Listen(host, port)) {
                trace("Could not establish a TCP socket!");
                return false;
            }

            trace("Listening for clients...");

            while (!tcpsocket.CanRead()) {
                yield();
            }

            startnew(CoroutineFunc(ServerLoop));
            return true;
        }

        void ServerLoop(){
            while (true) {
                // we accept any incoming connections
                // acceptclient will only accept max specified
                AcceptClient();


                // this is a bit janky
                // I think this can be improved
                array<int> cleanup;
                // // cleanup the failed connections
                for (uint i = 0; i < Clients.Length; i++) {
                    // trace(Clients[i].Client is null);
                    if (Clients[i].Client is null) {
                        cleanup.InsertLast(i);
                    }
                }
                // print("Cleanup " + cleanup.Length);
                for (uint i = 0; i < cleanup.Length; i++) {
                    if (i < Clients.Length) {
                        Clients.RemoveAt(i);
                    }
                }
                        
                // do other activity
                yield();
            }
        }

        void AcceptClient() {
            if (Clients.Length == MaxClients) {
                // if full just return
                return;
            }
            auto client = tcpsocket.Accept();
            // trace("accepted websocket client");

            if (client is null) {
                return;
            }

            dictionary headers = WSUtils::parseResponseHeaders(client);

            // We did not get a websocket header request
            // Close connection
            if (!headers.Exists("sec-websocket-key")) {
                client.Close();
                return;
            }

            // Complete handshake
            string b64key = WSUtils::computeHash(string(headers["sec-websocket-key"]));

            // Complete the handshake
            if (!client.WriteRaw(
                "HTTP/1.1 101 Switching Protocols\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Version: 13\r\n" +
                "Sec-WebSocket-Accept: " + b64key + "\r\n" +
                ((headers.Exists("sec-websocket-protocol")) ? "Sec-WebSocket-Protocol: " + string(headers["sec-websocket-protocol"]) + "\r\n" : "") +
                "\r\n"
            )) {
                print("Could not complete handshake");
                return;
            }
            trace("successfully upgraded connection to sockets");
            // add to connections
            Clients.InsertLast(WebSocketClient(@client, (headers.Exists("sec-websocket-protocol")) ? string(headers["sec-websocket-protocol"]) : ""));
        }

        void Close() {
            trace("WebSocket Server closed");
            tcpsocket.Close();
        }

    }


}


// https://www.honeybadger.io/blog/building-a-simple-websockets-server-from-scratch-in-ruby/
// https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers