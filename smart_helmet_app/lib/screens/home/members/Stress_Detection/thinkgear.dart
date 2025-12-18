class ThinkGearParser {
  List<int> buffer = [];

  /// Called when a valid raw EEG value is parsed (signed 16-bit)
  Function(int)? onRaw;

  /// Called when Poor Signal value is received (0 = good contact, 200 = no contact)
  Function(int)? onPoorSignal;

  /// Feed incoming bytes from Bluetooth stream
  void feed(List<int> data) {
    buffer.addAll(data);

    // Process complete packets
    while (buffer.length >= 4) {
      // Look for sync bytes
      if (buffer[0] != 0xAA || buffer[1] != 0xAA) {
        buffer.removeAt(0);
        continue;
      }

      // Need at least 3 bytes for length
      if (buffer.length < 3) break;

      int payloadLength = buffer[2];

      // Need full packet: sync(2) + length(1) + payload + checksum(1)
      if (buffer.length < 4 + payloadLength) break;

      List<int> payload = buffer.sublist(3, 3 + payloadLength);
      int receivedChecksum = buffer[3 + payloadLength];

      // Verify checksum
      int calculatedChecksum = 0;
      for (int b in payload) {
        calculatedChecksum += b;
      }
      calculatedChecksum = (~calculatedChecksum) & 0xFF;

      if (receivedChecksum != calculatedChecksum) {
        // Checksum failed → drop one byte and continue searching
        buffer.removeAt(0);
        continue;
      }

      // Valid packet → parse payload
      _parsePayload(payload);

      // Remove processed packet
      buffer.removeRange(0, 4 + payloadLength);
    }
  }

  void _parsePayload(List<int> payload) {
    int i = 0;

    while (i < payload.length) {
      if (i >= payload.length) break;

      int code = payload[i++];

      // Extended codes (0x55 + extended code) – skip for now
      if (code == 0x55) {
        if (i >= payload.length) break;
        i++; // Skip extended code
        continue;
      }

      // Single-byte value codes (e.g., Poor Signal)
      if (code == 0x02) {
        if (i >= payload.length) break;
        int poorSignal = payload[i++] & 0xFF; // 0 = perfect, 200 = no contact
        onPoorSignal?.call(poorSignal);
      }
      // Raw EEG (2 bytes)
      else if (code == 0x80) {
        if (i + 1 >= payload.length) break;
        int hi = payload[i++] & 0xFF;
        int lo = payload[i++] & 0xFF;
        int raw = (hi << 8) | lo;

        // Convert to signed 16-bit
        if (raw > 32767) {
          raw -= 65536;
        }

        onRaw?.call(raw);
      }
      // Other codes (e.g., ASIC EEG Power 0x83, Attention 0x04, Meditation 0x05) – skip value length
      else {
        if (i >= payload.length) break;
        int valueLength = payload[i++];
        i += valueLength; // Skip the value bytes
      }
    }
  }

  /// Reset parser state (useful on disconnect/reconnect)
  void reset() {
    buffer.clear();
  }
}
