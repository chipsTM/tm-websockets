// namespace WebSockets {


//     shared class SecureWebSocketClient {
//         Net::SecureSocket@ Client;
//         string Protocol;

//         SecureWebSocketClient(Net::SecureSocket@ client, string protocol) {
//             @Client = @client;
//             Protocol = protocol;
//         }

//         // Method for reading data from client
//         string ReadData() {
//             if (Client !is null && Client.CanRead()) {
//                 MemoryBuffer buffer;
                
//                 while (Client.Available() != 0) {
//                     buffer.Write(Client.ReadUint8());
//                 }

//                 buffer.Seek(0);
//                 auto opCode = buffer.ReadUInt8();

//                 // This is a singular frame and text data
//                 if (opCode == 0x81) {
//                     buffer.Seek(1);
//                     uint8 maskAndPayloadLen = buffer.ReadUInt8();
//                     // check for masking bit and payload length
//                     uint actualPayloadLen;
//                     MemoryBuffer maskingKey;
//                     uint padBytes;
//                     string data;
//                     if (maskAndPayloadLen & (1 << 7) != 0) {
//                         uint8 payloadLen = maskAndPayloadLen & ~0x80;
//                         if (payloadLen <= 125) {
//                             // Length is same is original
//                             actualPayloadLen = payloadLen;
//                             // Read Masking key
//                             buffer.Seek(2);
//                             maskingKey.Write(buffer.ReadUInt32());
//                             padBytes = 6;
//                         } else if (payloadLen == 126) {
//                             buffer.Seek(2);
//                             actualPayloadLen = (buffer.ReadUInt8() << 8) | buffer.ReadUInt8();
//                             // Read Masking key
//                             buffer.Seek(4);
//                             maskingKey.Write(buffer.ReadUInt32());
//                             padBytes = 8;
//                         } else if (payloadLen == 127) {
//                             trace("data is too large...");
//                             return "";
//                             // buffer.Seek(2);
//                             // actualPayloadLen = (buffer.ReadUInt8() << 8*7) | 
//                             //                    (buffer.ReadUInt8() << 8*6) | 
//                             //                    (buffer.ReadUInt8() << 8*5) | 
//                             //                    (buffer.ReadUInt8() << 8*4) | 
//                             //                    (buffer.ReadUInt8() << 8*3) | 
//                             //                    (buffer.ReadUInt8() << 8*2) | 
//                             //                    (buffer.ReadUInt8() << 8*1) | 
//                             //                    buffer.ReadUInt8();
//                             // // Read Masking key
//                             // buffer.Seek(10);
//                             // maskingKey.Write(buffer.ReadUInt32());
//                             // padBytes = 14;
//                         }
//                         // print(actualPayloadLen);

//                         MemoryBuffer decoded = MemoryBuffer(actualPayloadLen);
//                         for (uint i = 0; i < actualPayloadLen; i++) {
//                             buffer.Seek(padBytes + i);
//                             maskingKey.Seek(i % 4);
//                             decoded.Seek(i);
//                             decoded.Write(buffer.ReadUInt8() ^ maskingKey.ReadUInt8());
//                         }
//                         decoded.Seek(0);
//                         auto textData = decoded.ReadString(actualPayloadLen);
//                         return textData;
                        
//                     } else {
//                         trace("data is not masked, disconnecting...");
//                         Client.Close();
//                         @Client = null;
//                     }
//                 } else if (opCode == 0x82) {
//                     // binary data not supported (yet)
//                     trace("data type not supported...");
//                 } else if (opCode == 0x89) {
//                     // got ping?
//                     trace("ping...");
//                 } else if (opCode == 0x8A) {
//                     // pong? 
//                     trace("pong...");
//                 } else if (opCode == 0x88) {
//                     // close?
//                     trace("close...");
//                 } else {
//                     trace("data type not supported...");
//                 }
//                 return "";
//             } else {
//                 return "";
//             }
//         }

//         // TODO Commented out because SecureSocket::Write(MemoryBuffer@&) doesn exist yet

//         // method for sending Text data to client
//         // void SendData(const string &in data) {
//         //     if (Client !is null && Client.CanWrite()) {
//         //         if (data.Length < 3 || data.Length > Math::Pow(2,16)) {
//         //             // not sure what issue is here, but
//         //             // for some reason connection fails with very short length
//         //             // we also return if data has excessive length
//         //             return;
//         //         }
                
//         //         int padBytes;
//         //         uint payloadLen;
//         //         if (data.Length <= 125) {
//         //             padBytes = 1;
//         //             payloadLen = data.Length;
//         //         } else if (data.Length < Math::Pow(2,16)) {
//         //             padBytes = 3;
//         //             payloadLen = 126;
//         //         } else if (data.Length < Math::Pow(2,64)) {
//         //             padBytes = 9;
//         //             payloadLen = 127;
//         //         }

//         //         // Construct the Data Frame
//         //         // Preallocate 1 byte then payload size then payload
//         //         auto msg = MemoryBuffer(1 + padBytes + data.Length);
//         //         // Opcode and Text Data flags
//         //         msg.Seek(0);
//         //         msg.Write(0x81);
//         //         // Message Length
//         //         msg.Seek(1);
//         //         msg.Write(payloadLen);
                
//         //         if (payloadLen == 126) {
//         //             for (int i = 0; i < padBytes - 1 ; i++) {
//         //                 msg.Seek(2 + i);
//         //                 msg.Write((data.Length >> (8*(padBytes-2-i))) & 0xff);
//         //             }
//         //         } else if (payloadLen == 127) {
//         //             for (int i = 0; i < padBytes - 1; i++) {
//         //                 msg.Seek(2 + i);
//         //                 msg.Write((data.Length >> (8*(padBytes-2-i))) & 0xff);
//         //             }
//         //         }

//         //         // Write data to frame
//         //         msg.Seek(1 + padBytes);
//         //         msg.Write(data);
//         //         msg.Seek(0);
//         //         // Send msg over websockets
//         //         if (!Client.Write(msg)) {
//         //             Client.Close();
//         //             @Client = null;
//         //         }
//         //     }
//         // }
//     }


//     shared class SecureWebSocket {
//         // "private"
//         Net::SecureSocket@ tcpsocket;
//         // "public"
//         array<SecureWebSocketClient@> Clients;
//         uint MaxClients;

//         SecureWebSocket(const string &in host, int port, uint maxClients = 5) {
//             @tcpsocket = Net::SecureSocket();
//             MaxClients = maxClients;

//             // TODO implement Listen() on SecureSocket

//             // if (!tcpsocket.Listen(host, port)) {
//             //     trace("Could not establish a TCP socket!");
//             //     return;
//             // }

//             // trace("Connecting to host...");

//             // while (!tcpsocket.CanRead()) {
//             //     yield();
//             // }

//         }

//         void Listen() {
//             while (true) {
//                 // we accept any incoming connections
//                 // acceptclient will only accept max specified
//                 AcceptClient();


//                 // this is a bit janky
//                 // I think this can be improved
//                 array<int> cleanup;
//                 // // cleanup the failed connections
//                 for (uint i = 0; i < Clients.Length; i++) {
//                     // trace(Clients[i].Client is null);
//                     if (Clients[i].Client is null) {
//                         cleanup.InsertLast(i);
//                     }
//                 }
//                 // print("Cleanup " + cleanup.Length);
//                 for (uint i = 0; i < cleanup.Length; i++) {
//                     if (i < Clients.Length) {
//                         Clients.RemoveAt(i);
//                     }
//                 }
                        
//                 // do other activity
//                 yield();
//             }
//         }

//         void AcceptClient() {
//             if (Clients.Length == MaxClients) {
//                 // if full just return
//                 return;
//             }
//             auto client = tcpsocket.Accept();
//             // trace("accepted websocket client");
            
//             string key;
//             string protocol;

//             if (client is null) {
//                 return;
//             }

//             // While loop code snippet taken from Network test example script and slightly modified
//             // https://github.com/openplanet-nl/example-scripts/blob/master/Plugin_NetworkTest.as
//             while (true) {
//                 // If there is no data available yet, yield and wait.
//                 while (client.Available() == 0) {
//                     yield();
//                 }

//                 // There's buffered data! Try to get a line from the buffer.
//                 string line;
//                 if (!client.ReadLine(line)) {
//                     // We couldn't get a line at this point in time, so we'll wait a
//                     // bit longer.
//                     yield();
//                     continue;
//                 }

//                 // We got a line! Trim it, since ReadLine() returns the line including
//                 // the newline characters.
//                 line = line.Trim();

//                 // Parse the header line.
//                 auto parse = line.Split(":");
//                 if (parse.Length == 2 && parse[0].ToLower() == "sec-websocket-key") {
//                     key = parse[1].Trim();
//                 } else if (parse.Length == 2 && parse[0].ToLower() == "sec-websocket-protocol") {
//                     protocol = parse[1].Trim();
//                 }

//                 // If the line is empty, we are done reading all headers.
//                 if (line == "") {
//                     break;
//                 }

//                 // Print the header line.
//                 // print("\"" + line + "\"");
//             }

//             // We did not get a websocket header request
//             // Close connection
//             if (key == "") {
//                 client.Close();
//                 return;
//             }

//             // Complete handshake
//             string hashkey = Hash::Sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
//             auto bytearray = MemoryBuffer(20);
//             int counter = 0;
//             for (int i = 0; i < hashkey.Length; i+=2) {
//                 uint8 dec = getHexToDec(hashkey.SubStr(i,1)) * 16 + getHexToDec(hashkey.SubStr(i+1,1));
//                 bytearray.Write(dec);
//                 counter += 1;
//                 bytearray.Seek(counter);
//             }
//             bytearray.Seek(0);
//             string b64key = bytearray.ReadToBase64(bytearray.GetSize());

//             // Complete the handshake
//             if (!client.WriteRaw(
//                 "HTTP/1.1 101 Switching Protocols\r\n" +
//                 "Upgrade: websocket\r\n" +
//                 "Connection: Upgrade\r\n" +
//                 "Sec-WebSocket-Version: 13\r\n" +
//                 "Sec-WebSocket-Accept: " + b64key + "\r\n" +
//                 // we're overriding protocol in order to allow
//                 // client to request specific data points
//                 // this is more efficient as we don't need to 
//                 // send the entire VehicleState or whatever back to client
//                 ((protocol != "") ? "Sec-WebSocket-Protocol: " + protocol + "\r\n" : "") +
//                 "\r\n"
//             )) {
//                 print("Could not complete handshake");
//                 return;
//             }
//             trace("successfully upgraded connection to sockets");
//             // add to connections
//             Clients.InsertLast(SecureWebSocketClient(@client, protocol));
//         }

//         void Close() {
//             trace("tcpsocket closed");
//             tcpsocket.Close();
//         }

//         // helper function to convert hex to dec values
//         // only used in retrieving the bytes of the SHA1 key
//         int getHexToDec(const string &in val) {
//             if (val == "a") {
//                 return 10;
//             } else if (val == "b") {
//                 return 11;
//             } else if (val == "c") {
//                 return 12;
//             } else if (val == "d") {
//                 return 13;
//             } else if (val == "e") {
//                 return 14;
//             } else if (val == "f") {
//                 return 15;
//             } else {
//                 return Text::ParseInt(val);
//             }
//         }
//     }

    
// }
