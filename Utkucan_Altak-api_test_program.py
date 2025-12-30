import time
import sys
import os

# =============================================================================
# FILE: api_test_program.py
# PURPOSE: Test the API functionalities for Air Conditioner and Curtain Systems
# =============================================================================

# Fix for VS Code file path issues
sys.path.append(os.getcwd())

try:
    from air_conditioner_api import AirConditionerSystemConnection
    from curtain_api import CurtainControlSystemConnection

except ImportError as e:
    print("\n[CRITICAL ERROR] API files not found!")
    print(f"Error Details: {e}")
    print("Please ensure 'air_conditioner_api.py' and 'curtain_api.py' are in the same folder.\n")
    exit()

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

# ---------------------------------------------------------
# TEST 1: AIR CONDITIONER SYSTEM
# ---------------------------------------------------------
def test_air_conditioner_system():
    print("------------------------------------------------")
    print("TEST 1: Air Conditioner System (AC) Starting")
    print("------------------------------------------------")
    
    # Instantiate the class
    ac = AirConditionerSystemConnection()
    # Set Port directly to 1 (for COM1)
    ac.setComPort(1)
    
    # 1. Connection Test
    if ac.open():
        print("[SUCCESS] Port (COM1) opened.")
    else:
        print("[ERROR] Port (COM1) could not be opened! Test aborted.")
        return

    # 2. Update Data Test (Read)
    try:
        print("Reading data from PIC...")
        ac.update()
        print(f"[READ] Ambient Temp: {ac.getAmbientTemp()} C")
        print(f"[READ] Fan Speed: {ac.getFanSpeed()} rps")
    except Exception as e:
        print(f"[ERROR] Error reading data: {e}")

    # 3. Write Data Test (Set Desired Temp)
    try:
        test_val = 26.5
        print(f"Setting desired temperature to {test_val}...")
        ac.setDesiredTemp(test_val)
        
        # Wait for PIC to process
        print("Waiting for PIC processing (1.5s)...")
        time.sleep(1.5) 
        
        # Confirmation Read
        ac.update()
        read_val = ac.getDesiredTemp()
        
        if read_val == test_val:
             print(f"[SUCCESS] Desired temperature verified as {read_val} C.")
        else:
             print(f"[WARNING] Sent: {test_val} | Read: {read_val}")
             print("(Simulator might be closed or slow)")

    except Exception as e:
        print(f"[ERROR] Error writing data: {e}")

    ac.close()
    print("AC Test Finished.\n")


# ---------------------------------------------------------
# TEST 2: CURTAIN CONTROL SYSTEM
# ---------------------------------------------------------
def test_curtain_control_system():
    print("------------------------------------------------")
    print("TEST 2: Curtain Control System Starting")
    print("------------------------------------------------")
    
    # Instantiate the class
    curtain = CurtainControlSystemConnection()
    # Set Port directly to 2 (for COM2)
    curtain.setComPort(2)
    
    # 1. Connection Test
    if curtain.open():
        
        print("[SUCCESS] Port (COM2) opened.")
    else:
        print("[ERROR] Port (COM2) could not be opened! Test aborted.")
        return

    # 2. Update Data Test (Read)
    try:
        print("Reading sensor data...")
        curtain.update()
        print(f"[READ] Outdoor Temp: {curtain.getOutdoorTemp()} C")
        print(f"[READ] Pressure: {curtain.getOutdoorPress()} hPa")
        print(f"[READ] Light Intensity: {curtain.getLightIntensity()} Lux")
    except Exception as e:
        print(f"[ERROR] Error reading data: {e}")

    # 3. Write Data Test (Set Curtain Status)
    try:
        test_status = 75.0
        print(f"Setting curtain status to %{test_status}...")
        curtain.setCurtainStatus(test_status)
        
        # Wait for motor movement
        print("Waiting for motor movement (1.5s)...")
        time.sleep(1.5)
        
        curtain.update()
        
        # Check tolerance for float values
        if abs(curtain.curtainStatus - test_status) < 1.0:
            print(f"[SUCCESS] Curtain status verified as %{curtain.curtainStatus}.")
        else:
            print(f"[WARNING] Desired: %{test_status} | Read: %{curtain.curtainStatus}")
            
    except Exception as e:
        print(f"[ERROR] Error writing data: {e}")

    curtain.close()
    print("Curtain Test Finished.\n")


# ---------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------
if __name__ == "__main__":
    clear_screen()
    print("=== API TEST PROGRAM STARTING ===\n")
    print("Note: Ensure Simulator (PICSimLab) is running.\n")
    
    test_air_conditioner_system()
    
    time.sleep(1)
    
    test_curtain_control_system()
    
    print("=== ALL TESTS COMPLETED ===")
    input("Press Enter to exit...")