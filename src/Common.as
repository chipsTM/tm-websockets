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


        shared dictionary parseResponseHeaders(array<string>@ headerLines) {
            dictionary headers = {};
            for (uint i = 0; i < headerLines.Length; i++) {
                // Get first line which contains HTTP version and status code
                string line = headerLines[i];
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

        shared MemoryBuffer@ xorMask(MemoryBuffer@ dataBuffer, MemoryBuffer@ maskingKey, uint64 size) {
            MemoryBuffer coded = MemoryBuffer(size);
            for (uint64 i = 0; i < size; i++) {
                dataBuffer.Seek(i);
                maskingKey.Seek(i % 4);
                coded.Seek(i);
                coded.Write(uint8(dataBuffer.ReadUInt8() ^ maskingKey.ReadUInt8()));
            }
            coded.Seek(0);
            return coded;
        }

        shared MemoryBuffer@ generateFrame(uint8 opCode, const string &in data, bool client = false) {
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
            msg.Write(uint8(opCode));
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
                MemoryBuffer@ maskedData = xorMask(buffer, maskingKey, data.Length);
                msg.WriteFromBuffer(maskedData, maskedData.GetSize());
            } else {
                msg.Write(data);
            }
            msg.Seek(0);

            return msg;
        }

        shared MemoryBuffer@ generateFrame(uint8 opCode, MemoryBuffer@ data, bool client = false) {
            data.Seek(0);
            uint8 padBytes;
            uint8 payloadLen;
            if (data.GetSize() <= 125) {
                padBytes = 2;
                payloadLen = data.GetSize();
            } else if (data.GetSize() < uint64(Math::Pow(2,16))) {
                padBytes = 4;
                payloadLen = 126;
            } else if (data.GetSize() < uint64(Math::Pow(2,64))) {
                padBytes = 10;
                payloadLen = 127;
            }

            // if we're sending data as client we need to mask
            if (client) {
                padBytes += 4;
            }

            // Construct the Data Frame
            // Preallocate the buffer
            MemoryBuffer msg = MemoryBuffer(padBytes + data.GetSize());
            // Opcode and Text Data flags
            msg.Write(uint8(opCode));
            // Message Length
            if (client) {
                // add masking bit
                msg.Write(uint8(0x80 | payloadLen));
            } else {
                msg.Write(uint8(payloadLen));
            }

            if (payloadLen == 126) {
                msg.Write(Math::SwapBytes(uint16(data.GetSize())));
            } else if (payloadLen == 127) {
                msg.Write(Math::SwapBytes(uint64(data.GetSize())));
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
                buffer.WriteFromBuffer(data, data.GetSize());

                // offset is 0 because we're reading from new buffer
                MemoryBuffer@ maskedData = xorMask(buffer, maskingKey, data.GetSize());
                msg.WriteFromBuffer(maskedData, maskedData.GetSize());
            } else {
                msg.WriteFromBuffer(data, data.GetSize());
            }
            msg.Seek(0);

            return msg;
        }

        shared dictionary@ parseFrame(Net::Socket@ socket, bool client = false) {
            uint8 firstByte = socket.ReadUint8();
            uint8 secondByte = socket.ReadUint8();
            bool maskBit = ((secondByte & (1 << 7)) != 0) ? true : false;
            
            // Get actual payload size
            uint8 payloadLen = secondByte & ~0x80;
            uint64 actualPayloadLen;
            if (payloadLen <= 125) {
                // 1 bytes of frame payload size
                actualPayloadLen = payloadLen;
            } else if (payloadLen == 126) {
                // 2 bytes of frame payload size
                actualPayloadLen = Math::SwapBytes(socket.ReadUint16());
            } else if (payloadLen == 127) {
                // 8 bytes of frame payload size
                actualPayloadLen = Math::SwapBytes(socket.ReadUint64());
            }

            MemoryBuffer payloadData;
            if (maskBit) {
                // 4 bytes of Masking key
                MemoryBuffer maskingKey = MemoryBuffer(4);
                maskingKey.Write(socket.ReadUint32());

                // Write data to buffer for masking operation
                MemoryBuffer buffer = MemoryBuffer(actualPayloadLen);
                buffer.Write(socket.ReadRaw(actualPayloadLen));

                // Unmask the data and return
                payloadData = xorMask(buffer, maskingKey, actualPayloadLen);
            } else {
                // if no masking we can just return the data from buffer
                payloadData.Write(socket.ReadRaw(actualPayloadLen));
            }
            payloadData.Seek(0);

            dictionary frameDict = {};
            switch(firstByte) {
                case 0x81:
                    // text data
                    frameDict.Set("message", payloadData.ReadString(actualPayloadLen));
                    return frameDict;
                case 0x82:
                    // binary data not supported (yet)
                    trace("binary data type not supported (yet)...");
                    break;
                case 0x89:
                    // got ping control code
                    trace("ping...");
                    break;
                case 0x8A:
                    // pong control code 
                    trace("pong...");
                    break;
                case 0x88:
                    // close control code
                    {
                        trace("got close opCode");
                        dictionary closeEvent = {};
                        closeEvent.Set("wasClean", true);
                        if (client) {
                            if (!socket.Write(generateFrame(0x88, payloadData, true))) {
                                trace("failed to send close frame");
                                closeEvent.Set("wasClean", false);
                            }
                        } else {
                            if (!socket.Write(generateFrame(0x88, payloadData))) {
                                trace("failed to send close frame");
                                closeEvent.Set("wasClean", false);
                            }
                        }
                        payloadData.Seek(0);
                        closeEvent.Set("closeCode", Math::SwapBytes(payloadData.ReadUInt16()));
                        closeEvent.Set("reason", payloadData.ReadString(actualPayloadLen-2));
                        socket.Close();
                        return closeEvent;
                    }
                default:
                    // websockets also supports continuation frames 
                    // (i.e. first bit 0; 0x0X)
                    // seems to be very rare
                    // print(opCode);
                    trace("got unimplemented opcode...");
                    break;
            }
            return dictionary = {};
        }

        shared dictionary@ parseFrame(Net::SecureSocket@ socket, bool client = false) {
            uint8 firstByte = socket.ReadUint8();
            uint8 secondByte = socket.ReadUint8();
            bool maskBit = ((secondByte & (1 << 7)) != 0) ? true : false;
            
            // Get actual payload size
            uint8 payloadLen = secondByte & ~0x80;
            uint64 actualPayloadLen;
            if (payloadLen <= 125) {
                // 1 bytes of frame payload size
                actualPayloadLen = payloadLen;
            } else if (payloadLen == 126) {
                // 2 bytes of frame payload size
                actualPayloadLen = Math::SwapBytes(socket.ReadUint16());
            } else if (payloadLen == 127) {
                // 8 bytes of frame payload size
                actualPayloadLen = Math::SwapBytes(socket.ReadUint64());
            }

            MemoryBuffer payloadData;
            if (maskBit) {
                // 4 bytes of Masking key
                MemoryBuffer maskingKey = MemoryBuffer(4);
                maskingKey.Write(socket.ReadUint32());

                // Write data to buffer for masking operation
                MemoryBuffer buffer = MemoryBuffer(actualPayloadLen);
                buffer.Write(socket.ReadRaw(actualPayloadLen));

                // Unmask the data and return
                payloadData = xorMask(buffer, maskingKey, actualPayloadLen);
            } else {
                // if no masking we can just return the data from buffer
                payloadData.Write(socket.ReadRaw(actualPayloadLen));
            }
            payloadData.Seek(0);

            dictionary frameDict = {};
            switch(firstByte) {
                case 0x81:
                    // text data
                    frameDict.Set("message", payloadData.ReadString(actualPayloadLen));
                    return frameDict;
                case 0x82:
                    // binary data not supported (yet)
                    trace("binary data type not supported...");
                    break;
                case 0x89:
                    // got ping control code
                    trace("ping...");
                    break;
                case 0x8A:
                    // pong control code 
                    trace("pong...");
                    break;
                case 0x88:
                    // close control code
                    {
                        trace("got close opCode");
                        dictionary closeEvent = {};
                        closeEvent.Set("wasClean", true);
                        if (client) {
                            if (!socket.Write(generateFrame(0x88, payloadData, true))) {
                                trace("failed to send close frame");
                                closeEvent.Set("wasClean", false);
                            }
                        } else {
                            if (!socket.Write(generateFrame(0x88, payloadData))) {
                                trace("failed to send close frame");
                                closeEvent.Set("wasClean", false);
                            }
                        }
                        payloadData.Seek(0);
                        closeEvent.Set("closeCode", Math::SwapBytes(payloadData.ReadUInt16()));
                        closeEvent.Set("reason", payloadData.ReadString(actualPayloadLen-2));
                        socket.Close();
                        return closeEvent;
                    }
                default:
                    // websockets also supports continuation frames 
                    // (i.e. first bit 0; 0x0X)
                    // seems to be very rare
                    // print(opCode);
                    trace("got unimplemented opcode...");
                    break;
            }
            return dictionary = {};
        }
    }
}