namespace Net {

 
    shared class SecureWebSocket {
        // "private"
        Net::SecureSocket@ tcpsocket;

        SecureWebSocket() {
            @tcpsocket = Net::SecureSocket();
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

            while (tcpsocket.Connecting()) {
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

            while (!tcpsocket.CanWrite()) {
                yield();
            }
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

            return WSUtils::parseFrame(@tcpsocket, true);
        }


        void SendMessage(const string &in data) {
            if (!tcpsocket.CanWrite()) {
                yield();
            }

            MemoryBuffer@ msg = WSUtils::generateFrame(0x81, data, true);

            // Send msg over websockets
            if (!tcpsocket.Write(msg)) {
                trace("unable to send message");
                tcpsocket.Close();
            }  
        }

        bool Close() {
            MemoryBuffer@ closeData = MemoryBuffer(2);
            closeData.Write(Math::SwapBytes(uint16(1000)));
            closeData.Write("Closed from TM WebSockets");
            if (!tcpsocket.Write(WSUtils::generateFrame(0x88, closeData, true))) {
                trace("failed to send close frame");
                return false;
            }
            
            trace("WebSocket Server closed");
            tcpsocket.Close();
            return true;
        }

    }


}