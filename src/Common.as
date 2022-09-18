namespace Net {
    // "Private" namespace for internal functions
    // in order to keep Net namespace clean
    namespace WSUtils {
        // helper function to convert hex to dec values
        // only used in retrieving the bytes of the SHA1 key
        // in computeHash function
        shared int getHexToDec(const string &in val) {
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

        shared string computeHash(const string &in key) {
            string hashkey = Hash::Sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
            auto bytearray = MemoryBuffer(20);
            for (int i = 0; i < hashkey.Length; i+=2) {
                uint8 dec = getHexToDec(hashkey.SubStr(i,1)) * 16 + getHexToDec(hashkey.SubStr(i+1,1));
                bytearray.Write(dec);
            }
            bytearray.Seek(0);
            return bytearray.ReadToBase64(bytearray.GetSize());
        }


        shared dictionary parseResponseHeaders(Net::Socket@ conn) {
            dictionary headers = {};
            // While loop code snippet taken from Network test example script and slightly modified
            // https://github.com/openplanet-nl/example-scripts/blob/master/Plugin_NetworkTest.as
            while (true) {
                // If there is no data available yet, yield and wait.
                while (conn.Available() == 0) {
                    yield();
                }

                // There's buffered data! Try to get a line from the buffer.
                string line;
                if (!conn.ReadLine(line)) {
                    // We couldn't get a line at this point in time, so we'll wait a
                    // bit longer.
                    yield();
                    continue;
                }

                // We got a line! Trim it, since ReadLine() returns the line including
                // the newline characters.
                line = line.Trim();
                
                // If the line is empty, we are done reading all headers.
                if (line == "") {
                    break;
                }

                // Get first line which contains HTTP version and status code
                if (line.Contains("HTTP/")) {
                    auto parts = line.Split(" ", 3);
                    headers.Set("http_version", parts[0]);
                    headers.Set("status_code", parts[1]);
                    headers.Set("status_message", parts[2]);
                } else {
                    // Parse the header line.
                    auto parts = line.Split(":", 2);
                    if (parts.Length == 2) {
                        headers.Set(parts[0].ToLower(), parts[1].Trim()); 
                    } else {
                        trace("Unable to parse header line.");
                    }
                }
            }
            return headers;
        }


        shared MemoryBuffer@ xorMask(MemoryBuffer@ frame, MemoryBuffer@ maskingKey, uint8 offset, uint64 size) {
            MemoryBuffer coded = MemoryBuffer(size);
            for (uint64 i = 0; i < size; i++) {
                frame.Seek(offset + i);
                maskingKey.Seek(i % 4);
                coded.Seek(i);
                coded.Write(uint8(frame.ReadUInt8() ^ maskingKey.ReadUInt8()));
            }
            coded.Seek(0);
            return coded;
        }

        shared MemoryBuffer@ generateFrame(const string &in data, bool client = false) {
            uint8 padBytes;
            uint8 payloadLen;
            if (data.Length <= 125) {
                padBytes = 2;
                payloadLen = data.Length;
            } else if (data.Length < Math::Pow(2,16)) {
                padBytes = 4;
                payloadLen = 126;
            } else if (data.Length < Math::Pow(2,64)) {
                padBytes = 10;
                payloadLen = 127;
            }

            // if we're sending data as client we need to mask
            if (client) {
                padBytes += 4;
            }

            // Construct the Data Frame
            // Preallocate the buffer
            MemoryBuffer msg = MemoryBuffer(padBytes + data.Length);
            // Opcode and Text Data flags
            msg.Write(uint8(0x81));
            // Message Length
            if (client) {
                // add masking bit
                msg.Write(uint8(0x80 | payloadLen));
            } else {
                msg.Write(uint8(payloadLen));
            }

            if (payloadLen == 126) {
                msg.Write(Math::SwapBytes(uint16(data.Length)));
            } else if (payloadLen == 127) {
                msg.Write(Math::SwapBytes(uint64(data.Length)));
            }

            // Write data to frame
            if (client) {
                // Generate masking key
                MemoryBuffer maskingKey = MemoryBuffer(4);
                uint randomMask = (Math::Rand(0,65536) << 16) | Math::Rand(0,65536);
                maskingKey.Write(randomMask);
                maskingKey.Seek(0);
                msg.WriteFromBuffer(maskingKey, 4);

                // Write data to buffer for masking operation
                MemoryBuffer buffer = MemoryBuffer();
                buffer.Write(data);

                // offset is 0 because we're reading from new buffer
                MemoryBuffer@ maskedData = xorMask(buffer, maskingKey, 0, data.Length);
                msg.WriteFromBuffer(maskedData, maskedData.GetSize());
            } else {
                msg.Write(data);
            }
            msg.Seek(0);

            return msg;
        }

        shared dictionary@ parseFrame(Net::Socket@ socket, MemoryBuffer@ frame) {
            dictionary frameDict = {};
            frame.Seek(0);
            if (frame.GetSize() == 0) {
                return frameDict;
            }
            // print("frame size: " + frame.GetSize());
            uint8 opCode = frame.ReadUInt8();

            // This is a singular frame and text data
            if (opCode == 0x81) {
                uint8 maskAndPayloadLen = frame.ReadUInt8();
                bool maskBit = ((maskAndPayloadLen & (1 << 7)) != 0) ? true : false;
                
                // Get actual payload size
                uint64 actualPayloadLen;
                uint8 offset;
                uint8 payloadLen = maskAndPayloadLen & ~0x80;
                if (payloadLen <= 125) {
                    // 1 bytes of frame payload size
                    actualPayloadLen = payloadLen;
                    offset = 2;
                } else if (payloadLen == 126) {
                    // 2 bytes of frame payload size
                    actualPayloadLen = Math::SwapBytes(frame.ReadUInt16());
                    offset = 4;
                } else if (payloadLen == 127) {
                    // 8 bytes of frame payload size
                    actualPayloadLen = Math::SwapBytes(frame.ReadUInt64());
                    offset = 10;
                }

                if (maskBit) {
                    offset += 4;
                    // 4 bytes of Masking key
                    MemoryBuffer maskingKey = MemoryBuffer(4);
                    maskingKey.Write(frame.ReadUInt32());
                    // Unmask the data and return
                    MemoryBuffer@ data = xorMask(frame, maskingKey, offset, actualPayloadLen);
                    frameDict.Set("message", data.ReadString(actualPayloadLen));
                    return frameDict;
                } else {
                    // if no masking we can just return the data from frame
                    frameDict.Set("message", frame.ReadString(actualPayloadLen));
                    return frameDict;
                }

            } else if (opCode == 0x82) {
                // binary data not supported (yet)
                trace("data type not supported (yet)...");
            } else if (opCode == 0x89) {
                // got ping?
                trace("ping...");
            } else if (opCode == 0x8A) {
                // pong? 
                trace("pong...");
            } else if (opCode == 0x88) {
                // close?
                trace("got close opCode");
                socket.Close();
            } else {
                // websockets also supports multiple frames 
                // (i.e. first bit 0; 0x0X)
                // seems to be very rare
                // print(opCode);
                trace("data type not supported...");
            }
            return frameDict;
        }
    }
}