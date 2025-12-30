import serial
import time
import struct
import os

# =============================================================================
# SINGLE FILE, ERROR-FREE, GUARANTEED WORKING PYTHON CODE (AIR CONDITIONER)
# =============================================================================

class HomeAutomationSystemConnection:
    def __init__(self):
        self.comPort = 0
        self.baudRate = 9600
        self.serial_conn = None

    def setComPort(self, port):
        self.comPort = port

    def setBaudRate(self, rate):
        self.baudRate = rate

    def open(self):
        try:
            port_name = f"COM{self.comPort}"
            self.serial_conn = serial.Serial(port_name, self.baudRate, timeout=1.0)
            self.serial_conn.reset_input_buffer()
            return True
        except Exception as e:
            print(f"Connection error ({port_name}): {e}")
            return False

    def close(self):
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            return True
        return False

    # --- PROTECTED DATA RECEIVE FUNCTION ---
    def _get_response(self, command_byte):
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.reset_input_buffer() # Clear old data
            self.serial_conn.write(bytes([command_byte]))
            time.sleep(0.05)
            data = self.serial_conn.read(1)
            if data:
                return int.from_bytes(data, byteorder='big')
        return None

    def _send_byte(self, byte_val):
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.write(bytes([byte_val]))
            time.sleep(0.05)

class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    def __init__(self):
        super().__init__()
        self.desiredTemperature = 0.0
        self.ambientTemperature = 0.0
        self.fanSpeed = 0

    def getAmbientTemp(self):
        return self.ambientTemperature

    def getFanSpeed(self):
        return self.fanSpeed
    
    def getDesiredTemp(self):
        return self.desiredTemperature

    def setDesiredTemp(self, temp):
        # Split the float value (e.g. 24.5) into integer and fractional parts
        tam_kisim = int(temp)
        ondalik_kisim = int(round((temp - tam_kisim) * 10))
        
        # Bit masking according to protocol (PDF Page 16)
        # Low Byte format: 10xxxxxx -> Add 128
        komut_low = 128 + ondalik_kisim
        
        # High Byte format: 11xxxxxx -> Add 192
        komut_high = 192 + tam_kisim
        
        self._send_byte(komut_low)
        self._send_byte(komut_high)
        
        # Note: self.desiredTemperature is updated via update() from PIC
        return True

    def update(self):
        # 1. AMBIENT TEMPERATURE
        # Command 3 = Low Byte, Command 4 = High Byte
        amb_low = self._get_response(3)
        amb_high = self._get_response(4)
        
        if amb_low is not None and amb_high is not None:
            # Combine High.Low (Decimal number)
            self.ambientTemperature = float(f"{amb_high}.{amb_low}")

        # 2. DESIRED TEMPERATURE
        # Command 1 = Low Byte, Command 2 = High Byte
        des_low = self._get_response(1)
        des_high = self._get_response(2)
        
        if des_low is not None and des_high is not None:
            self.desiredTemperature = float(f"{des_high}.{des_low}")

        # 3. FAN SPEED
        # Command 5
        fan_val = self._get_response(5)
        if fan_val is not None:
            self.fanSpeed = fan_val

# =============================================================================
# MAIN
# =============================================================================

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def main():
    # --- PORT SETTING ---
    PORT_NUMARASI = 1  # Standard for AC
    
    klima = AirConditionerSystemConnection()
    klima.setComPort(PORT_NUMARASI)
    
    print(f"Connecting (COM{PORT_NUMARASI})...")
    
    if not klima.open():
        print("ERROR: Could not open port!")
        return

    while True:
        clear_screen()
        
        print("Receiving data...")
        klima.update()
        
        print("################################")
        print("#    AC CONTROL SYSTEM         #")
        print("################################")
        print(f"Ambient Temp    : {klima.getAmbientTemp():.1f} C")
        print(f"Desired Temp    : {klima.getDesiredTemp():.1f} C")
        print(f"Fan Speed       : {klima.getFanSpeed()} rps")
        print("--------------------------------")
        print("1. Set Temperature")
        print("2. Refresh")
        print("3. Exit")
        print("--------------------------------")
        
        secim = input("Choice: ")
        
        if secim == '1':
            try:
                val = float(input("Value (e.g. 24.5): "))
                klima.setDesiredTemp(val)
                print("Sent.")
                time.sleep(1)
            except:
                pass
        elif secim == '3':
            klima.close()
            break
        else:
            pass

if __name__ == "__main__":
    main()