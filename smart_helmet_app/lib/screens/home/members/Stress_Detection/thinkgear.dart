class ThinkGearParser {
  List<int> buffer = [];

  /// Called when a valid raw EEG value is parsed (signed 16-bit)
  Function(int)? onRaw;

  /// Called when Poor Signal value is received (0 = good contact, 200 = no contact)
  Function(int)? onPoorSignal;

  /// Called when Attention value is received (0-100)
  Function(int)? onAttention;

  /// Called when Meditation value is received (0-100)
  Function(int)? onMeditation;

  /// Called when ASIC EEG Power bands are received (list of 8 integers: delta, theta, lowAlpha, highAlpha, lowBeta, highBeta, lowGamma, midGamma)
  Function(List<int>)? onPowerBands;

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

      // Extended codes (0x55 + extended code) – skip
      if (code == 0x55) {
        if (i >= payload.length) break;
        i++; // Skip extended code
        continue;
      }

      // Poor Signal (code 0x02, 1 byte)
      if (code == 0x02) {
        if (i >= payload.length) break;
        int poorSignal = payload[i++] & 0xFF;
        onPoorSignal?.call(poorSignal);
      }
      // Attention (code 0x04, 1 byte)
      else if (code == 0x04) {
        if (i >= payload.length) break;
        int att = payload[i++] & 0xFF;
        onAttention?.call(att);
      }
      // Meditation (code 0x05, 1 byte)
      else if (code == 0x05) {
        if (i >= payload.length) break;
        int med = payload[i++] & 0xFF;
        onMeditation?.call(med);
      }
      // Raw EEG (code 0x80, 2 bytes)
      else if (code == 0x80) {
        if (i + 1 >= payload.length) break;
        int hi = payload[i++] & 0xFF;
        int lo = payload[i++] & 0xFF;
        int raw = (hi << 8) | lo;
        if (raw > 32767) raw -= 65536;
        onRaw?.call(raw);
      }
      // ASIC EEG Power (code 0x83, length byte + 24 bytes: 8 bands x 3 bytes each)
      else if (code == 0x83) {
        if (i >= payload.length) break;
        int len = payload[i++]; // Should be 24
        if (i + len > payload.length || len != 24) {
          i += len; // Skip if invalid
          continue;
        }
        List<int> bands = [];
        for (int j = 0; j < 8; j++) {
          int val = (payload[i] << 16) | (payload[i + 1] << 8) | payload[i + 2];
          bands.add(val);
          i += 3;
        }
        onPowerBands?.call(bands);
      }
      // Other codes – skip value length
      else {
        if (i >= payload.length) break;
        int valueLength = payload[i++];
        i += valueLength;
      }
    }
  }

  /// Reset parser state
  void reset() {
    buffer.clear();
  }
}
