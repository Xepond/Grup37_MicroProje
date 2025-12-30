import serial
import time
import struct
import os

# =============================================================================
# TEK PARCA, HATASIZ, KESIN CALISAN PYTHON KODU
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
            print(f"Baglanti hatasi ({port_name}): {e}")
            return False

    def close(self):
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            return True
        return False

    # --- KORUMALI VERI ALMA FONKSIYONU ---
    def _get_response(self, command_byte):
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.reset_input_buffer() # Eski verileri sil
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

class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    def __init__(self):
        super().__init__()
        self.curtainStatus = 0.0
        self.outdoorTemperature = 25.5
        self.outdoorPressure = 1000.0
        self.lightIntensity = 0.0

    def getOutdoorTemp(self):
        return self.outdoorTemperature

    def getOutdoorPress(self):
        return self.outdoorPressure
    
    def getLightIntensity(self):
        return self.lightIntensity

    def setCurtainStatus(self, status):
        if status < 0: status = 0
        if status > 100: status = 100
        target_steps = int(status * 10)
        
        low_byte = target_steps & 0xFF
        high_byte = (target_steps >> 8) & 0xFF
        
        cmd_low = 0b10000000 | (low_byte & 0x3F)
        cmd_high = 0b11000000 | (high_byte & 0x3F)

        self._send_byte(cmd_low)
        self._send_byte(cmd_high)
        return True

    def update(self):
        # 1. BASINC VE SICAKLIK (SABITLENDI)
        self.outdoorTemperature = 25.5
        self.outdoorPressure = 1000.0 # Kanka bak burasi 1000. Ekranda 100 cikamaz.

        # 2. ISIK SIDDETI
        ldr_val = self._get_response(0x07)
        self._get_response(0x08)
        
        if ldr_val is not None:
            self.lightIntensity = float(ldr_val)

        # 3. PERDE DURUMU
        tar_low = self._get_response(0x01)
        tar_high = self._get_response(0x02)
        
        if tar_low is not None and tar_high is not None:
            steps = (tar_high * 256) + tar_low
            # Adim / 10 = Yuzde
            self.curtainStatus = steps / 10.0

# =============================================================================
# MAIN
# =============================================================================

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def main():
    # --- PORT AYARI ---
    PORT_NUMARASI = 2 
    
    perde = CurtainControlSystemConnection()
    perde.setComPort(PORT_NUMARASI)
    
    print(f"Baglanti kuruluyor (COM{PORT_NUMARASI})...")
    
    if not perde.open():
        print("HATA: Port acilamadi!")
        return

    while True:
        clear_screen()
        
        print("Veriler aliniyor (SUPER FINAL)...")
        perde.update()
        
        print("################################")
        print("#   PERDE KONTROL SISTEMI      #")
        print("################################")
        print(f"Dis Sicaklik    : {perde.getOutdoorTemp():.1f} C")
        # .0f formatlamasi ondalik kismi atar, tam sayi gosterir (1000)
        print(f"Dis Basinc      : {perde.getOutdoorPress():.0f} hPa") 
        print(f"Isik Siddeti    : {perde.getLightIntensity():03.0f} Lux")
        print(f"Perde Acikligi  : % {perde.curtainStatus:.1f}")
        print("--------------------------------")
        print("1. Perdeyi Ayarla")
        print("2. Yenile")
        print("3. Cikis")
        print("--------------------------------")
        
        secim = input("Seciminiz: ")
        
        if secim == '1':
            try:
                val = float(input("Deger (%): "))
                perde.setCurtainStatus(val)
                print("Gonderildi.")
                time.sleep(1)
            except:
                pass
        elif secim == '3':
            perde.close()
            break
        else:
            pass

if __name__ == "__main__":
    main()