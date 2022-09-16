namespace Net {


    shared class WebSocketClient {
        Net::Socket@ Client;
        string Protocol;

        WebSocketClient(Net::Socket@ client, const string &in protocol) {
            @Client = @client;
            Protocol = protocol;
        }

        // Method for reading data from client
        string ReadData() {
            if (Client !is null && Client.CanRead()) {
                MemoryBuffer buffer;
                
                while (Client.Available() != 0) {
                    buffer.Write(Client.ReadUint8());
                }

                buffer.Seek(0);
                auto opCode = buffer.ReadUInt8();

                // This is a singular frame and text data
                if (opCode == 0x81) {
                    buffer.Seek(1);
                    uint8 maskAndPayloadLen = buffer.ReadUInt8();
                    // check for masking bit and payload length
                    uint actualPayloadLen;
                    MemoryBuffer maskingKey;
                    uint padBytes;
                    string data;
                    if (maskAndPayloadLen & (1 << 7) != 0) {
                        uint8 payloadLen = maskAndPayloadLen & ~0x80;
                        if (payloadLen <= 125) {
                            // Length is same is original
                            actualPayloadLen = payloadLen;
                            // Read Masking key
                            buffer.Seek(2);
                            maskingKey.Write(buffer.ReadUInt32());
                            padBytes = 6;
                        } else if (payloadLen == 126) {
                            buffer.Seek(2);
                            actualPayloadLen = (buffer.ReadUInt8() << 8) | buffer.ReadUInt8();
                            // Read Masking key
                            buffer.Seek(4);
                            maskingKey.Write(buffer.ReadUInt32());
                            padBytes = 8;
                        } else if (payloadLen == 127) {
                            trace("data is too large...");
                            return "";
                            // buffer.Seek(2);
                            // actualPayloadLen = (buffer.ReadUInt8() << 8*7) | 
                            //                    (buffer.ReadUInt8() << 8*6) | 
                            //                    (buffer.ReadUInt8() << 8*5) | 
                            //                    (buffer.ReadUInt8() << 8*4) | 
                            //                    (buffer.ReadUInt8() << 8*3) | 
                            //                    (buffer.ReadUInt8() << 8*2) | 
                            //                    (buffer.ReadUInt8() << 8*1) | 
                            //                    buffer.ReadUInt8();
                            // // Read Masking key
                            // buffer.Seek(10);
                            // maskingKey.Write(buffer.ReadUInt32());
                            // padBytes = 14;
                        }
                        // print(actualPayloadLen);

                        MemoryBuffer decoded = MemoryBuffer(actualPayloadLen);
                        for (uint i = 0; i < actualPayloadLen; i++) {
                            buffer.Seek(padBytes + i);
                            maskingKey.Seek(i % 4);
                            decoded.Seek(i);
                            decoded.Write(buffer.ReadUInt8() ^ maskingKey.ReadUInt8());
                        }
                        decoded.Seek(0);
                        auto textData = decoded.ReadString(actualPayloadLen);
                        return textData;
                        
                    } else {
                        trace("data is not masked, disconnecting...");
                        Client.Close();
                        @Client = null;
                    }
                } else if (opCode == 0x82) {
                    // binary data not supported (yet)
                    trace("data type not supported...");
                } else if (opCode == 0x89) {
                    // got ping?
                    trace("ping...");
                } else if (opCode == 0x8A) {
                    // pong? 
                    trace("pong...");
                } else if (opCode == 0x88) {
                    // close?
                    trace("close...");
                } else {
                    trace("data type not supported...");
                }
                return "";
            } else {
                return "";
            }
        }

        // method for sending Text data to client
        void SendData(const string &in data) {
            if (Client !is null && Client.CanWrite()) {
                if (data.Length < 3 || data.Length > Math::Pow(2,16)) {
                    // not sure what issue is here, but
                    // for some reason connection fails with very short length
                    // we also return if data has excessive length
                    return;
                }
                
                int padBytes;
                uint payloadLen;
                if (data.Length <= 125) {
                    padBytes = 1;
                    payloadLen = data.Length;
                } else if (data.Length < Math::Pow(2,16)) {
                    padBytes = 3;
                    payloadLen = 126;
                } else if (data.Length < Math::Pow(2,64)) {
                    padBytes = 9;
                    payloadLen = 127;
                }

                // Construct the Data Frame
                // Preallocate 1 byte then payload size then payload
                auto msg = MemoryBuffer(1 + padBytes + data.Length);
                // Opcode and Text Data flags
                msg.Seek(0);
                msg.Write(0x81);
                // Message Length
                msg.Seek(1);
                msg.Write(payloadLen);
                
                if (payloadLen == 126) {
                    for (int i = 0; i < padBytes - 1 ; i++) {
                        msg.Seek(2 + i);
                        msg.Write((data.Length >> (8*(padBytes-2-i))) & 0xff);
                    }
                } else if (payloadLen == 127) {
                    for (int i = 0; i < padBytes - 1; i++) {
                        msg.Seek(2 + i);
                        msg.Write((data.Length >> (8*(padBytes-2-i))) & 0xff);
                    }
                }

                // Write data to frame
                msg.Seek(1 + padBytes);
                msg.Write(data);
                msg.Seek(0);
                // Send msg over websockets
                if (!Client.Write(msg)) {
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

        WebSocket() {
            @tcpsocket = Net::Socket();
        }

        void Connect(const string &in host, uint16 port, const string &in protocol = "") {
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
                trace("Could not establish a TCP socket!");
                return;
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
            string b64key = computeHash(key);

            // Initiatie Handshake
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
                print("Couldn't send connection data.");
                return;
            }

            bool validResponse = true;
            while (validResponse) {
                // If there is no data available yet, yield and wait.
                while (tcpsocket.Available() == 0) {
                    yield();
                }

                // There's buffered data! Try to get a line from the buffer.
                string line;
                if (!tcpsocket.ReadLine(line)) {
                    // We couldn't get a line at this point in time, so we'll wait a
                    // bit longer.
                    yield();
                    continue;
                }

                // We got a line! Trim it, since ReadLine() returns the line including
                // the newline characters.
                line = line.Trim();

                if (line.Contains("HTTP/")) {
                    if (!line.Contains("101")) {
                        validResponse = false;
                    }
                }

                // Parse the header line.
                auto parse = line.Split(":");
                if (parse.Length == 2 && parse[0].ToLower() == "connection") {
                    if (parse[1].Trim().ToLower() != "upgrade") {
                        validResponse = false;
                    }
                } else if (parse.Length == 2 && parse[0].ToLower() == "upgrade") {
                    if (parse[1].Trim().ToLower() != "websocket") {
                        validResponse = false;
                    }
                } else if (parse.Length == 2 && parse[0].ToLower() == "sec-websocket-accept") {
                    if (parse[1].Trim() != b64key) {
                        validResponse = false;
                    }
                }

                // If the line is empty, we are done reading all headers.
                if (line == "") {
                    break;
                }

                // Print the header line.
                // print("\"" + line + "\"");
            }

            if (!validResponse) {
                Close();
                return;
            }
            
            // we've validated and now can send/receive messages
            startnew(CoroutineFunc(Loop));
        }

        void Loop() {
            while (true) {
                if (tcpsocket.CanRead()) {

                    MemoryBuffer buffer;
                    while (tcpsocket.Available() != 0) {
                        buffer.Write(tcpsocket.ReadUint8());
                    }

                    buffer.Seek(0);
                    auto opCode = buffer.ReadUInt8();

                    // This is a singular frame and text data
                    if (opCode == 0x81) {
                        buffer.Seek(1);
                        uint8 payloadLen = buffer.ReadUInt8();
                        // check for masking bit and payload length
                        uint actualPayloadLen;
                        uint padBytes;
                        string data;
                        if (payloadLen <= 125) {
                            // Length is same is original
                            actualPayloadLen = payloadLen;
                            // Read Masking key
                            buffer.Seek(2);
                            print(buffer.ReadString(actualPayloadLen));
                        } else if (payloadLen == 126) {
                            buffer.Seek(2);
                            actualPayloadLen = (buffer.ReadUInt8() << 8) | buffer.ReadUInt8();
                            // Read Masking key
                            buffer.Seek(4);
                            print(buffer.ReadString(actualPayloadLen));
                        } else if (payloadLen == 127) {
                            trace("data is too large...");
                        }

                    }
                }
                yield();
            }
        }

        void Send(const string &in data) {
            if (tcpsocket.CanWrite()) {

                if (data.Length < 3 || data.Length > Math::Pow(2,16)) {
                    // not sure what issue is here, but
                    // for some reason connection fails with very short length
                    // we also return if data has excessive length
                    return;
                }
                
                int padBytes;
                uint payloadLen;
                if (data.Length <= 125) {
                    padBytes = 1;
                    payloadLen = data.Length;
                } else if (data.Length < Math::Pow(2,16)) {
                    padBytes = 3;
                    payloadLen = 126;
                } else if (data.Length < Math::Pow(2,64)) {
                    padBytes = 9;
                    payloadLen = 127;
                }

                // Construct the Data Frame
                // Preallocate 1 byte then payload size then payload
                auto msg = MemoryBuffer(1 + padBytes + 4 + data.Length);
                // Opcode and Text Data flags
                // msg.Seek(0);
                msg.Write(uint8(0x81));
                // Message Length
                // msg.Seek(1);
                // needs to be masked
                msg.Write(uint8(0x80 | payloadLen));
                
                if (payloadLen == 126) {
                    msg.Write(uint16(data.Length));
                    // for (int i = 0; i < padBytes - 1 ; i++) {
                    //     msg.Seek(2 + i);
                    //     msg.Write((data.Length >> (8*(padBytes-2-i))) & 0xff);
                    // }
                } else if (payloadLen == 127) {
                    msg.Write(uint64(data.Length));
                    // for (int i = 0; i < padBytes - 1; i++) {
                    //     msg.Seek(2 + i);
                    //     msg.Write((data.Length >> (8*(padBytes-2-i))) & 0xff);
                    // }
                }

                // msg.Seek(padBytes);
                MemoryBuffer maskingKey = MemoryBuffer(4);
                uint randomMask = (Math::Rand(0,65536) << 16) | Math::Rand(0,65536);
                // print(randomMask);
                maskingKey.Write(Math::SwapBytes(randomMask));
                maskingKey.Seek(0);
                msg.WriteFromBuffer(maskingKey, 4);

                // Write data to frame
                // msg.Seek(padBytes + 4);
                MemoryBuffer buffer = MemoryBuffer();
                buffer.Write(data);
                MemoryBuffer encoded = MemoryBuffer(data.Length);
                for (int i = 0; i < data.Length; i++) {
                    buffer.Seek(i);
                    maskingKey.Seek(i % 4);
                    encoded.Seek(i);
                    encoded.Write(uint8(buffer.ReadUInt8() ^ maskingKey.ReadUInt8()));
                }

                encoded.Seek(0);
                msg.WriteFromBuffer(encoded, encoded.GetSize());
                // for (uint i = 0; i < msg.GetSize(); i++) {
                //     msg.Seek(i);
                //     print(msg.ReadUInt8());
                // }
                msg.Seek(0);
                // print("sending: " + data);
                // Send msg over websockets
                if (!tcpsocket.Write(msg)) {
                    // tcpsocket.Close();
                    trace("unable to send message");
                }
                
            }
        }


        void Listen(const string &in host, uint16 port, uint maxClients = 5) {
            MaxClients = maxClients;

            if (!tcpsocket.Listen(host, port)) {
                trace("Could not establish a TCP socket!");
                return;
            }

            trace("Connecting to host...");

            while (!tcpsocket.CanRead()) {
                yield();
            }

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
            
            string key;
            string protocol;

            if (client is null) {
                return;
            }

            // While loop code snippet taken from Network test example script and slightly modified
            // https://github.com/openplanet-nl/example-scripts/blob/master/Plugin_NetworkTest.as
            while (true) {
                // If there is no data available yet, yield and wait.
                while (client.Available() == 0) {
                    yield();
                }

                // There's buffered data! Try to get a line from the buffer.
                string line;
                if (!client.ReadLine(line)) {
                    // We couldn't get a line at this point in time, so we'll wait a
                    // bit longer.
                    yield();
                    continue;
                }

                // We got a line! Trim it, since ReadLine() returns the line including
                // the newline characters.
                line = line.Trim();

                // Parse the header line.
                auto parse = line.Split(":");
                if (parse.Length == 2 && parse[0].ToLower() == "sec-websocket-key") {
                    key = parse[1].Trim();
                } else if (parse.Length == 2 && parse[0].ToLower() == "sec-websocket-protocol") {
                    protocol = parse[1].Trim();
                }

                // If the line is empty, we are done reading all headers.
                if (line == "") {
                    break;
                }

                // Print the header line.
                // print("\"" + line + "\"");
            }

            // We did not get a websocket header request
            // Close connection
            if (key == "") {
                client.Close();
                return;
            }

            // Complete handshake
            string b64key = computeHash(key);

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

        void Close() {
            trace("tcpsocket closed");
            tcpsocket.Close();
        }

        // helper function to convert hex to dec values
        // only used in retrieving the bytes of the SHA1 key
        int getHexToDec(const string &in val) {
            if (val == "a") {
                return 10;
            } else if (val == "b") {
                return 11;
            } else if (val == "c") {
                return 12;
            } else if (val == "d") {
                return 13;
            } else if (val == "e") {
                return 14;
            } else if (val == "f") {
                return 15;
            } else {
                return Text::ParseInt(val);
            }
        }

        string computeHash(const string &in key) {
            string hashkey = Hash::Sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
            auto bytearray = MemoryBuffer(20);
            int counter = 0;
            for (int i = 0; i < hashkey.Length; i+=2) {
                uint8 dec = getHexToDec(hashkey.SubStr(i,1)) * 16 + getHexToDec(hashkey.SubStr(i+1,1));
                bytearray.Write(dec);
                counter += 1;
                bytearray.Seek(counter);
            }
            bytearray.Seek(0);
            return bytearray.ReadToBase64(bytearray.GetSize());
        }

    }


}


// https://www.honeybadger.io/blog/building-a-simple-websockets-server-from-scratch-in-ruby/
// https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers