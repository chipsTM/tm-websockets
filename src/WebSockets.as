namespace Net {

    // Server class for managing clients
    shared class WebSocketClient {
        Net::Socket@ Client;
        string Protocol;

        WebSocketClient(Net::Socket@ client, const string &in protocol) {
            @Client = @client;
            Protocol = protocol;
        }

        // Method for reading data from client
        dictionary@ GetMessage() {
            if (Client !is null && Client.CanRead()) {
                // we need at least 2 bytes to read a beginning of frame
                if (Client.Available() >= 2) {
                    return WSUtils::parseFrame(@Client);
                }
            }
            return dictionary = {};    
        }

        // method for sending Text data to client
        void SendMessage(const string &in data) {
            if (Client !is null && Client.CanWrite()) {
                MemoryBuffer@ msg = WSUtils::generateFrame(0x81, data);

                // Send msg over websockets
                if (!Client.Write(msg)) {
                    trace("Failed to send data to client. Closing connection");
                    Client.Close();
                    @Client = null;
                }
            }
        }

        void Close(uint16 code = 1000, const string &in reason = "") {
            MemoryBuffer@ closeData = MemoryBuffer(2);
            closeData.Write(Math::SwapBytes(code));
            closeData.Write(reason);
            if (!Client.Write(WSUtils::generateFrame(0x88, closeData))) {
                throw("failed to send close frame");
            }
            trace("WebSocket Client closed from server");
            Client.Close();
            @Client = null;
        }
    }


    shared class WebSocket {
        // "private"
        Net::Socket@ tcpsocket;
        bool serverrunning;
        bool isClient;
        // "public"
        array<WebSocketClient@> Clients;
        uint MaxClients;

        WebSocket() {
            @tcpsocket = Net::Socket();
        }

        bool Connect(const string &in host, uint16 port, const string &in protocol = "") {
            isClient = true;
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


            // While loop code snippet taken from Network test example script and slightly modified
            // https://github.com/openplanet-nl/example-scripts/blob/master/Plugin_NetworkTest.as
            array<string> headerLines;
            while (true) {
                while (tcpsocket.Available() == 0) {
                    yield();
                }
                string line;
                if (!tcpsocket.ReadLine(line)) {
                    yield();
                    continue;
                }
                line = line.Trim();
                if (line == "") {
                    break;
                }
                headerLines.InsertLast(line);
            }
            dictionary@ headers = WSUtils::parseResponseHeaders(@headerLines);

            bool validResponse = true;
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
                tcpsocket.Close();
                return false;
            }
            
            // we've validated and now can send/receive messages
            return true;
        }

        dictionary@ GetMessage() {
            if (!tcpsocket.CanRead()) {
                yield();
            }
            // we need at least 2 bytes to read a beginning of frame
            while (tcpsocket.Available() < 2) {
                yield();
            }

            return WSUtils::parseFrame(@tcpsocket, isClient);
        }

        void SendMessage(const string &in data) {
            if (!tcpsocket.CanWrite()) {
                yield();
            }

            MemoryBuffer@ msg = WSUtils::generateFrame(0x81, data, isClient);

            // Send msg over websockets
            if (!tcpsocket.Write(msg)) {
                trace("unable to send message");
                tcpsocket.Close();
            }                
        }


        bool Listen(const string &in host, uint16 port, uint maxClients = 5) {
            MaxClients = maxClients;
            isClient = false;

            if (!tcpsocket.Listen(host, port)) {
                trace("Could not establish a TCP socket!");
                return false;
            }

            trace("Listening for clients...");

            while (!tcpsocket.CanRead()) {
                yield();
            }

            // print("starting server loop");

            serverrunning = true;
            startnew(CoroutineFunc(ServerLoop));
            return true;
        }

        void ServerLoop() {
            while (true) {
                if (!serverrunning) {
                    // finish coroutine if Close called 
                    break;
                }
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
            trace("Server stopped");
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

            // While loop code snippet taken from Network test example script and slightly modified
            // https://github.com/openplanet-nl/example-scripts/blob/master/Plugin_NetworkTest.as
            array<string> headerLines;
            while (true) {
                while (client.Available() == 0) {
                    yield();
                }
                string line;
                if (!client.ReadLine(line)) {
                    yield();
                    continue;
                }
                line = line.Trim();
                if (line == "") {
                    break;
                }
                headerLines.InsertLast(line);
            }
            dictionary@ headers = WSUtils::parseResponseHeaders(@headerLines);

            // We did not get a websocket header request
            // Close connection
            if (!headers.Exists("sec-websocket-key")) {
                client.Close();
                return;
            }
            string key = string(headers["sec-websocket-key"]);

            // Complete handshake
            string b64key = WSUtils::computeHash(key);

            // get a protocol if asked
            string protocol;
            if (headers.Exists("sec-websocket-protocol")) {
                protocol = string(headers["sec-websocket-protocol"]);
            } else {
                protocol = "";
            }

            // Complete the handshake
            if (!client.WriteRaw(
                "HTTP/1.1 101 Switching Protocols\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Version: 13\r\n" +
                "Sec-WebSocket-Accept: " + b64key + "\r\n" +
                ((protocol != "") ? "Sec-WebSocket-Protocol: " + protocol + "\r\n" : "") +
                "\r\n"
            )) {
                print("Could not complete handshake");
                return;
            }
            trace("successfully upgraded connection to sockets");
            // add to connections
            Clients.InsertLast(WebSocketClient(@client, protocol));
        }

        void Close(uint16 code = 1000, const string &in reason = "") {
            if (isClient) {
                MemoryBuffer@ closeData = MemoryBuffer(2);
                closeData.Write(Math::SwapBytes(code));
                closeData.Write(reason);
                if (!tcpsocket.Write(WSUtils::generateFrame(0x88, closeData, isClient))) {
                    throw("failed to send close frame");
                }
                trace("WebSocket Client closed");
            } else {
                serverrunning = false;
                trace("WebSocket Server closed");
            }
            tcpsocket.Close();
        }

    }


}


// https://www.honeybadger.io/blog/building-a-simple-websockets-server-from-scratch-in-ruby/
// https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers