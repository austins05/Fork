#!/usr/bin/env python3
import socket
import struct
import json
import time
import sys
import os

# Configuration
IPAD_PORT = 2345
FRAME_TYPE_TEMPERATURE = 100
PTPROTOCOL_VERSION = 1

# Try to import SMtc sensor library
try:
    import sm_tc
    SMTC_AVAILABLE = True
    print("✅ sm_tc library loaded successfully")
except ImportError:
    SMTC_AVAILABLE = False
    print("⚠️  sm_tc library not available - using simulated data")

class SMTCReader:
    """Read temperatures from SMtc HAT boards (same logic as GATT server)"""
    
    def __init__(self):
        self.egt_sensor = None
        self.cht_sensor = None
        self.hardware_available = False
        
        # K-type thermocouples (same as GATT server)
        self.thermocouple_type = 3
        
        # Channel mapping: probes 1-6 use channels 1-4,7-8 (same as GATT server)
        self.egt_channel_map = [1, 2, 3, 4, 7, 8]
        self.cht_channel_map = [1, 2, 3, 4, 7, 8]
        
        if not SMTC_AVAILABLE:
            print("⚠️  Running in simulation mode (sm_tc not available)")
            return
        
        # Initialize HAT boards
        try:
            self.egt_sensor = sm_tc.SMtc(0)  # Stack level 0 for EGT
            print("✅ EGT SMtc HAT (stack level 0) initialized")
        except Exception as e:
            print(f"⚠️  EGT SMtc HAT not available: {e}")
        
        try:
            self.cht_sensor = sm_tc.SMtc(1)  # Stack level 1 for CHT
            print("✅ CHT SMtc HAT (stack level 1) initialized")
        except Exception as e:
            print(f"⚠️  CHT SMtc HAT not available: {e}")
        
        self.hardware_available = (self.egt_sensor is not None or self.cht_sensor is not None)
        
        if self.hardware_available:
            # Configure all channels for K-type thermocouples
            for channel in range(1, 9):
                try:
                    if self.egt_sensor:
                        self.egt_sensor.set_sensor_type(channel, self.thermocouple_type)
                    if self.cht_sensor:
                        self.cht_sensor.set_sensor_type(channel, self.thermocouple_type)
                except Exception as e:
                    print(f"⚠️  Could not configure channel {channel}: {e}")
            
            print(f"✅ All channels configured for K-type thermocouples")
            print(f"✅ EGT channels: {self.egt_channel_map} (probes 1-6)")
            print(f"✅ CHT channels: {self.cht_channel_map} (probes 1-6)")
        else:
            print("⚠️  No SMtc HATs detected - using simulation mode")
    
    def read_cht_probe(self, probe_id):
        """Read CHT probe (0-5) in Fahrenheit"""
        try:
            if self.cht_sensor is not None:
                if probe_id < 0 or probe_id >= len(self.cht_channel_map):
                    return 0.0
                
                channel = self.cht_channel_map[probe_id]
                temp_c = self.cht_sensor.get_temp(channel)
                temp_f = (temp_c * 9/5) + 32
                return temp_f
            else:
                # Simulation fallback
                import random
                return 300.0 + random.uniform(0, 100)
        except Exception as e:
            print(f"❌ CHT probe {probe_id + 1} error: {e}")
            return 0.0
    
    def read_egt_probe(self, probe_id):
        """Read EGT probe (0-5) in Fahrenheit"""
        try:
            if self.egt_sensor is not None:
                if probe_id < 0 or probe_id >= len(self.egt_channel_map):
                    return 0.0
                
                channel = self.egt_channel_map[probe_id]
                temp_c = self.egt_sensor.get_temp(channel)
                temp_f = (temp_c * 9/5) + 32
                return temp_f
            else:
                # Simulation fallback
                import random
                return 1200.0 + random.uniform(0, 300)
        except Exception as e:
            print(f"❌ EGT probe {probe_id + 1} error: {e}")
            return 0.0

# Initialize sensor reader
sensor_reader = SMTCReader()

def read_temperature_data():
    """Read actual temperature data from SMTC thermocouples"""
    
    # Read all 6 CHT probes
    cht_temps = []
    for probe_id in range(6):
        temp = sensor_reader.read_cht_probe(probe_id)
        cht_temps.append(temp)
    
    # Read all 6 EGT probes
    egt_temps = []
    for probe_id in range(6):
        temp = sensor_reader.read_egt_probe(probe_id)
        egt_temps.append(temp)
    
    return {
        "cht": cht_temps,
        "egt": egt_temps,
        "timestamp": time.time(),
        "unit": "F"
    }

def send_peertalk_frame(sock, frame_type, payload_data):
    """Send a PeerTalk frame with CORRECT header format"""
    try:
        # Convert payload to JSON bytes
        if isinstance(payload_data, dict):
            payload_bytes = json.dumps(payload_data).encode('utf-8')
        else:
            payload_bytes = payload_data
        
        # CORRECT PeerTalk frame structure (from PTProtocol.m):
        # typedef struct _PTFrame {
        #   uint32_t version;       // Protocol version (1)
        #   uint32_t type;          // Frame type (100 for temperature)
        #   uint32_t tag;           // Tag (0 for untagged)
        #   uint32_t payloadSize;   // Size of payload
        # } PTFrame;
        #
        # All fields in network byte order (big-endian)
        
        frame_header = struct.pack('>IIII', 
                                   PTPROTOCOL_VERSION,  # version = 1
                                   frame_type,           # type = 100
                                   0,                    # tag = 0
                                   len(payload_bytes))   # payloadSize
        
        # Send header + payload
        sock.sendall(frame_header + payload_bytes)
        return True
    except Exception as e:
        print(f"Error sending frame: {e}")
        return False

def connect_to_ipad():
    """Connect to iPad through iproxy"""
    try:
        # Connect to localhost:2345 (forwarded by iproxy to iPad)
        ipad_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ipad_sock.settimeout(5)
        ipad_sock.connect(('127.0.0.1', IPAD_PORT))
        
        print(f"✅ Connected to iPad on port {IPAD_PORT}")
        return ipad_sock
        
    except socket.timeout:
        print("⏱️  Connection timeout - iPad may not be connected")
        return None
    except ConnectionRefusedError:
        print("❌ Connection refused - iPad app may not be running")
        return None
    except Exception as e:
        print(f"❌ Connection error: {e}")
        return None

def main():
    print("="*60)
    print("PeerTalk Temperature Sender v3 (ACTUAL SMTC THERMOCOUPLE)")
    print("="*60)
    print(f"SMtc Available: {SMTC_AVAILABLE}")
    print(f"Hardware Available: {sensor_reader.hardware_available}")
    print("="*60)
    print("Connecting to iPad...")
    
    while True:
        try:
            # Try to connect to iPad
            sock = connect_to_ipad()
            
            if sock is None:
                print("Retrying in 5 seconds...")
                time.sleep(5)
                continue
            
            print("🌡️  Starting temperature streaming...")
            
            # Main loop - send temperature data every second
            frame_num = 0
            while True:
                try:
                    # Read temperature data from actual thermocouples
                    temp_data = read_temperature_data()
                    
                    if temp_data:
                        # Send to iPad
                        frame_num += 1
                        if send_peertalk_frame(sock, FRAME_TYPE_TEMPERATURE, temp_data):
                            cht_avg = sum(temp_data['cht'])/6 if temp_data['cht'] else 0
                            egt_avg = sum(temp_data['egt'])/6 if temp_data['egt'] else 0
                            status = "[LIVE]" if sensor_reader.hardware_available else "[SIM]"
                            print(f"📤 Frame #{frame_num} {status} - CHT avg={cht_avg:.1f}°F, EGT avg={egt_avg:.1f}°F")
                        else:
                            print(f"❌ Failed after {frame_num} frames")
                            break
                    
                    time.sleep(1)  # Send updates every second
                    
                except KeyboardInterrupt:
                    print("\n⏹️  Stopping...")
                    break
                except Exception as e:
                    print(f"❌ Error in main loop after {frame_num} frames: {e}")
                    break
            
            sock.close()
            print(f"🔌 Disconnected from iPad (sent {frame_num} frames total)")
            
        except KeyboardInterrupt:
            print("\n👋 Shutting down...")
            sys.exit(0)
        except Exception as e:
            print(f"❌ Fatal error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
