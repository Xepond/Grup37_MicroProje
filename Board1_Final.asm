; ==============================================================================
; PROJE: Board #1 - Ev ?klimlendirme Sistemi
; KATKIDA BULUNAN: [Senin Ad?n/Kullan?c? Ad?n]
; GÖREVLER: Keypad Interrupts, 7-Segment Multiplexing, UART Communication
; ==============================================================================

#include <xc.inc>

; --- KONFIGURASYON (Ortak Alan) ---
config FOSC = XT
config WDTE = OFF
config PWRTE = ON
config BOREN = ON
config LVP = OFF
config CPD = OFF
config CP = OFF

; --- HAFIZA YONETIMI (Ortak De?i?kenler) ---
DESIRED_TEMP_INT    EQU 0x20
DESIRED_TEMP_FRAC   EQU 0x21
AMBIENT_TEMP_INT    EQU 0x22
AMBIENT_TEMP_FRAC   EQU 0x23
FAN_SPEED           EQU 0x24

SYSTEM_MODE         EQU 0x25
INPUT_BUFFER_INT    EQU 0x26
INPUT_BUFFER_FRAC   EQU 0x27
DISPLAY_MODE        EQU 0x28
DISPLAY_TIMER       EQU 0x29
RX_DATA             EQU 0x2A
TMR0_OVERFLOW_CNT   EQU 0x2B

; Display ve Keypad De?i?kenleri (Senin K?sm?n)
ADC_H               EQU 0x30
ADC_L               EQU 0x31
DISP_DIG1           EQU 0x32
DISP_DIG2           EQU 0x33
DISP_DIG3           EQU 0x34
DISP_DIG4           EQU 0x35
DELAY_COUNT         EQU 0x36
KEY_PRESSED         EQU 0x37
WAIT_VAR            EQU 0x38
INPUT_STEP          EQU 0x39
DEBOUNCE_COUNT      EQU 0x3A
LAST_KEY            EQU 0x3B
SEG_TEMP            EQU 0x7E

W_TEMP              EQU 0x70
STATUS_TEMP         EQU 0x71

; --- PIN TANIMLAMALARI ---
#define HEATER_PIN      PORTC, 1
#define COOLER_PIN      PORTC, 2

; ==============================================================================
; RESET VEKTORU
; ==============================================================================
PSECT resetVec, class=CODE, delta=2
ORG 0x00
    GOTO MAIN

; ==============================================================================
; KESME SERVIS RUTINI (ISR)
; ==============================================================================
PSECT isrVec, class=CODE, delta=2
ORG 0x04
    ; Context Save
    MOVWF W_TEMP
    SWAPF STATUS, W
    MOVWF STATUS_TEMP

    ; --- 1. UART KESMESI (Senin Kodun) ---
    BCF STATUS, 5           
    BTFSC PIR1, 5           ; RCIF
    CALL ISR_UART_HANDLER

    ; --- 2. KEYPAD KESMESI (Senin Kodun) ---
    BTFSC INTCON, 0         ; RBIF
    CALL ISR_KEYPAD_HANDLER

    ; --- TIMER KESMES? (Di?er Üye) ---
    ; (Fan h?z? ölçümü buraya gelecek)

    ; Context Restore
    SWAPF STATUS_TEMP, W
    MOVWF STATUS
    SWAPF W_TEMP, F
    SWAPF W_TEMP, W
    RETFIE

; ==============================================================================
; ANA PROGRAM (MAIN)
; ==============================================================================
MAIN:
    CALL SYSTEM_INIT        
    
    ; Ba?lang?ç De?erleri (Ortak)
    MOVLW 30
    MOVWF DESIRED_TEMP_INT
    MOVLW 5
    MOVWF DESIRED_TEMP_FRAC
    CLRF SYSTEM_MODE
    CLRF INPUT_STEP

MAIN_LOOP:
    ; --- MOD KONTROLÜ (Senin Kodun: Giri? Modu Tetikleyicisi) ---
    MOVF SYSTEM_MODE, W
    SUBLW 1
    BTFSC STATUS, 2         
    GOTO HANDLE_INPUT_MODE  
    
    ; --- SENSÖR OKUMA (Di?er Üye) ---
    CALL READ_TEMP_SENSOR
    
    ; --- FAN HIZI ÖLÇÜMÜ (Di?er Üye) ---
    ; (Kod buraya eklenecek)

    ; --- MANTIK KONTROLÜ (Di?er Üye) ---
    CALL LOGIC_CONTROL

    ; --- EKRAN YÖNET?M? (Senin Kodun) ---
    CALL UPDATE_DISPLAY_DATA
    CALL REFRESH_DISPLAY_LOOP
    
    ; Döngü Zamanlamas?
    INCF DISPLAY_TIMER, F
    MOVLW 100               
    SUBWF DISPLAY_TIMER, W
    BTFSS STATUS, 0
    GOTO MAIN_LOOP
    
    CLRF DISPLAY_TIMER
    INCF DISPLAY_MODE, F
    MOVLW 3
    SUBWF DISPLAY_MODE, W
    BTFSC STATUS, 2
    CLRF DISPLAY_MODE
    
    GOTO MAIN_LOOP

; ==============================================================================
; MANTIK KONTROLÜ (ISITMA/SO?UTMA)
; ==============================================================================
LOGIC_CONTROL:
    ; *** BU KISIM TAKIM ARKADA?I TARAFINDAN KODLANACAK ***
    ; (Compare temperatures and set Heater/Cooler pins)
    RETURN

; ==============================================================================
; SENSÖR OKUMA
; ==============================================================================
READ_TEMP_SENSOR:
    ; *** BU KISIM TAKIM ARKADA?I TARAFINDAN KODLANACAK ***
    ; (Read ADC from RA0 and convert to Temp)
    RETURN

; ==============================================================================
; KEYPAD G?R?? S?STEM? (Senin Kodun)
; ==============================================================================
HANDLE_INPUT_MODE:
    ; Ekran? temizle
    CLRF DISP_DIG1
    CLRF DISP_DIG2
    CLRF DISP_DIG3
    CLRF DISP_DIG4
    
    MOVF INPUT_STEP, F
    BTFSS STATUS, 2      
    GOTO INPUT_STEP_HANDLER 

    ; ?lk giri? temizli?i
    CLRF INPUT_BUFFER_INT
    CLRF INPUT_BUFFER_FRAC
    
    MOVLW 0
    MOVWF DISP_DIG1
    MOVWF DISP_DIG2
    MOVWF DISP_DIG4

INPUT_STEP_HANDLER:
    MOVF INPUT_STEP, W
    XORLW 0
    BTFSC STATUS, 2
    GOTO STEP_0_ONLAR

    MOVF INPUT_STEP, W
    XORLW 1
    BTFSC STATUS, 2
    GOTO STEP_1_BIRLER

    MOVF INPUT_STEP, W
    XORLW 2
    BTFSC STATUS, 2
    GOTO STEP_2_YILDIZ

    MOVF INPUT_STEP, W
    XORLW 3
    BTFSC STATUS, 2
    GOTO STEP_3_ONDALIK

    MOVF INPUT_STEP, W
    XORLW 4
    BTFSC STATUS, 2
    GOTO STEP_4_KARE

    GOTO ABORT_INPUT

STEP_0_ONLAR:
    CALL GET_KEY_BLOCKING_NEW
    MOVWF LAST_KEY
    MOVLW 10
    SUBWF LAST_KEY, W
    BTFSC STATUS, 0     
    GOTO ABORT_INPUT    

    MOVF LAST_KEY, W
    MOVWF INPUT_BUFFER_INT 
    MOVWF DISP_DIG1        
    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

STEP_1_BIRLER:
    CALL GET_KEY_BLOCKING_NEW
    MOVWF LAST_KEY
    MOVLW 10
    SUBWF LAST_KEY, W
    BTFSC STATUS, 0
    GOTO ABORT_INPUT

    MOVF INPUT_BUFFER_INT, W
    MOVWF KEY_PRESSED
    MOVLW 9
    MOVWF DELAY_COUNT
MUL_LOOP:
    MOVF KEY_PRESSED, W
    ADDWF INPUT_BUFFER_INT, F
    DECFSZ DELAY_COUNT, F
    GOTO MUL_LOOP
    
    MOVF LAST_KEY, W
    ADDWF INPUT_BUFFER_INT, F
    MOVWF DISP_DIG2        
    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

STEP_2_YILDIZ:
    CALL GET_KEY_BLOCKING_NEW
    XORLW 0x0E          
    BTFSS STATUS, 2
    GOTO ABORT_INPUT    
    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

STEP_3_ONDALIK:
    CALL GET_KEY_BLOCKING_NEW
    MOVWF LAST_KEY
    MOVLW 10
    SUBWF LAST_KEY, W
    BTFSC STATUS, 0
    GOTO ABORT_INPUT
    MOVF LAST_KEY, W
    MOVWF INPUT_BUFFER_FRAC
    MOVWF DISP_DIG4     
    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

STEP_4_KARE:
    CALL GET_KEY_BLOCKING_NEW
    XORLW 0x0F          
    BTFSS STATUS, 2
    GOTO ABORT_INPUT
    
    MOVF INPUT_BUFFER_INT, W
    MOVWF DESIRED_TEMP_INT
    MOVF INPUT_BUFFER_FRAC, W
    MOVWF DESIRED_TEMP_FRAC
    
    CLRF SYSTEM_MODE
    CLRF INPUT_STEP
    GOTO MAIN_LOOP

ABORT_INPUT:
    CLRF SYSTEM_MODE
    CLRF DISPLAY_MODE
    CLRF INPUT_STEP
    GOTO MAIN_LOOP

; ==============================================================================
; TU? OKUMA FONKS?YONU (Senin Kodun)
; ==============================================================================
GET_KEY_BLOCKING_NEW:
WAIT_RELEASE:
    CALL REFRESH_INPUT_DISPLAY  
    MOVLW 11110000B
    MOVWF PORTB
    MOVLW 5
    MOVWF DEBOUNCE_COUNT
DEB_REL:
    MOVF PORTB, W
    ANDLW 11110000B
    XORLW 11110000B         
    BTFSS STATUS, 2
    GOTO WAIT_RELEASE       
    DECFSZ DEBOUNCE_COUNT, F
    GOTO DEB_REL
    
SCAN_KEYS:
    CALL REFRESH_INPUT_DISPLAY 

    ; Sütun 1
    MOVLW 11111110B
    MOVWF PORTB
    NOP
    BTFSS PORTB, 4
    GOTO FOUND_1
    BTFSS PORTB, 5
    GOTO FOUND_4
    BTFSS PORTB, 6
    GOTO FOUND_7
    BTFSS PORTB, 7
    GOTO FOUND_STAR

    ; Sütun 2
    MOVLW 11111101B
    MOVWF PORTB
    NOP
    BTFSS PORTB, 4
    GOTO FOUND_2
    BTFSS PORTB, 5
    GOTO FOUND_5
    BTFSS PORTB, 6
    GOTO FOUND_8
    BTFSS PORTB, 7
    GOTO FOUND_0

    ; Sütun 3
    MOVLW 11111011B
    MOVWF PORTB
    NOP
    BTFSS PORTB, 4
    GOTO FOUND_3
    BTFSS PORTB, 5
    GOTO FOUND_6
    BTFSS PORTB, 6
    GOTO FOUND_9
    BTFSS PORTB, 7
    GOTO FOUND_HASH

    ; Sütun 4 (A Tu?u)
    MOVLW 11110111B    
    MOVWF PORTB
    NOP
    BTFSS PORTB, 4     
    GOTO FOUND_A
    
    GOTO SCAN_KEYS

FOUND_A:
    MOVLW 0x0A         
    GOTO KEY_CONFIRM
FOUND_1:
    MOVLW 1
    GOTO KEY_CONFIRM
FOUND_2:
    MOVLW 2
    GOTO KEY_CONFIRM
FOUND_3:
    MOVLW 3
    GOTO KEY_CONFIRM
FOUND_4:
    MOVLW 4
    GOTO KEY_CONFIRM
FOUND_5:
    MOVLW 5
    GOTO KEY_CONFIRM
FOUND_6:
    MOVLW 6
    GOTO KEY_CONFIRM
FOUND_7:
    MOVLW 7
    GOTO KEY_CONFIRM
FOUND_8:
    MOVLW 8
    GOTO KEY_CONFIRM
FOUND_9:
    MOVLW 9
    GOTO KEY_CONFIRM
FOUND_0:
    MOVLW 0
    GOTO KEY_CONFIRM
FOUND_STAR:
    MOVLW 0x0E
    GOTO KEY_CONFIRM
FOUND_HASH:
    MOVLW 0x0F
    GOTO KEY_CONFIRM

KEY_CONFIRM:
    MOVWF LAST_KEY          
    MOVLW 10                
    MOVWF DEBOUNCE_COUNT
DEB_PRESS:
    CALL DELAY_1MS
    DECFSZ DEBOUNCE_COUNT, F
    GOTO DEB_PRESS
    MOVF LAST_KEY, W        
    RETURN

; ==============================================================================
; EKRAN TARAMA (Senin Kodun: Multiplexing)
; ==============================================================================
REFRESH_INPUT_DISPLAY:
    MOVLW 2                 
    MOVWF DELAY_COUNT
RINPUT_LOOP:
    MOVF DISP_DIG1, W
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 2
    CALL DLY_US_SHORT
    BCF PORTA, 2
    CLRF PORTD

    MOVF DISP_DIG2, W
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 3
    CALL DLY_US_SHORT
    BCF PORTA, 3
    CLRF PORTD

    MOVLW 01100011B
    MOVWF PORTD
    BSF PORTA, 4
    CALL DLY_US_SHORT
    BCF PORTA, 4
    CLRF PORTD

    MOVF DISP_DIG4, W
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 5
    CALL DLY_US_SHORT
    BCF PORTA, 5
    CLRF PORTD

    DECFSZ DELAY_COUNT, F
    GOTO RINPUT_LOOP
    RETURN

REFRESH_DISPLAY_LOOP:
    MOVLW 4
    MOVWF DELAY_COUNT
REFRESH_L:
    MOVF DISP_DIG1, W
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 2
    CALL DLY_US
    BCF PORTA, 2
    CLRF PORTD

    MOVF DISP_DIG2, W
    CALL GET_SEG
    MOVWF PORTD         
    BTFSC DISPLAY_MODE, 1 
    GOTO SKIP_DOT
    BSF PORTD, 7        
SKIP_DOT:
    BSF PORTA, 3
    CALL DLY_US
    BCF PORTA, 3
    CLRF PORTD

    MOVF DISP_DIG3, W   
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 4
    CALL DLY_US
    BCF PORTA, 4
    CLRF PORTD

    MOVF DISP_DIG4, W   
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 5
    CALL DLY_US
    BCF PORTA, 5
    CLRF PORTD

    DECFSZ DELAY_COUNT, F
    GOTO REFRESH_L
    RETURN

; ==============================================================================
; UART ?LET???M? (Senin Kodun)
; ==============================================================================
ISR_UART_HANDLER:
    MOVF RCREG, W
    MOVWF RX_DATA
    BTFSS RX_DATA, 7
    GOTO CHECK_GET
    BTFSC RX_DATA, 6
    GOTO SET_INT
    MOVLW 0x3F
    ANDWF RX_DATA, W
    MOVWF DESIRED_TEMP_FRAC
    RETURN
SET_INT:
    MOVLW 0x3F
    ANDWF RX_DATA, W
    MOVWF DESIRED_TEMP_INT
    RETURN

CHECK_GET:
    MOVF RX_DATA, W
    XORLW 0x01
    BTFSC STATUS, 2
    GOTO SEND_DES_FRAC
    MOVF RX_DATA, W
    XORLW 0x02
    BTFSC STATUS, 2
    GOTO SEND_DES_INT
    MOVF RX_DATA, W
    XORLW 0x03
    BTFSC STATUS, 2
    GOTO SEND_AMB_FRAC
    MOVF RX_DATA, W
    XORLW 0x04
    BTFSC STATUS, 2
    GOTO SEND_AMB_INT
    MOVF RX_DATA, W
    XORLW 0x05
    BTFSC STATUS, 2
    GOTO SEND_FAN
    RETURN

SEND_DES_FRAC:
    MOVF DESIRED_TEMP_FRAC, W
    GOTO TX_BYTE
SEND_DES_INT:
    MOVF DESIRED_TEMP_INT, W
    GOTO TX_BYTE
SEND_AMB_FRAC:
    MOVF AMBIENT_TEMP_FRAC, W
    GOTO TX_BYTE
SEND_AMB_INT:
    MOVF AMBIENT_TEMP_INT, W
    GOTO TX_BYTE
SEND_FAN:
    MOVF FAN_SPEED, W
TX_BYTE:
    BTFSS PIR1, 4
    GOTO $-1
    MOVWF TXREG
    RETURN

; ==============================================================================
; INTERRUPT HANDLERS (Senin Kodun: A Tu?u Tetikleme)
; ==============================================================================
ISR_KEYPAD_HANDLER:
    MOVF SYSTEM_MODE, F
    BTFSS STATUS, 2      
    GOTO ISR_KEY_EXIT    
    MOVLW 11110111B      
    MOVWF PORTB
    NOP
    NOP
    BTFSC PORTB, 4       
    GOTO ISR_KEY_EXIT    
    MOVLW 1
    MOVWF SYSTEM_MODE
    CLRF INPUT_STEP
ISR_KEY_EXIT:
    BCF INTCON, 0        
    MOVF PORTB, W        
    RETURN

; ==============================================================================
; EKRAN VER?S? HAZIRLAMA (Senin Kodun)
; ==============================================================================
UPDATE_DISPLAY_DATA:
    MOVF DISPLAY_MODE, W
    XORLW 2
    BTFSC STATUS, 2
    GOTO PREP_FAN       
    MOVF DISPLAY_MODE, W
    XORLW 0
    BTFSC STATUS, 2
    GOTO LOAD_DESIRED   
    
    ; Ortam S?cakl??? Gösterimi (Veriler di?er üyeden gelir)
    MOVF AMBIENT_TEMP_INT, W
    MOVWF KEY_PRESSED   
    MOVF AMBIENT_TEMP_FRAC, W
    MOVWF DISP_DIG3     
    GOTO CONVERT_TEMP

LOAD_DESIRED:
    MOVF DESIRED_TEMP_INT, W
    MOVWF KEY_PRESSED
    MOVF DESIRED_TEMP_FRAC, W
    MOVWF DISP_DIG3     

CONVERT_TEMP:
    MOVF KEY_PRESSED, W
    CALL BIN_TO_BCD_RAW 
    MOVLW 11
    MOVWF DISP_DIG4
    RETURN

PREP_FAN:
    MOVF FAN_SPEED, W
    CALL BIN_TO_BCD_RAW 
    MOVF DISP_DIG2, W
    MOVWF DISP_DIG4     
    MOVF DISP_DIG1, W
    MOVWF DISP_DIG3     
    MOVLW 10
    MOVWF DISP_DIG1
    MOVWF DISP_DIG2
    MOVF DISP_DIG3, W
    BTFSC STATUS, 2     
    MOVWF DISP_DIG3     
    MOVF DISP_DIG3, W   
    BTFSS STATUS, 2     
    GOTO FAN_DONE       
    MOVLW 10            
    MOVWF DISP_DIG3
FAN_DONE:
    RETURN

BIN_TO_BCD_RAW:
    MOVWF KEY_PRESSED   
    CLRF DISP_DIG1      
BCD_L:
    MOVLW 10
    SUBWF KEY_PRESSED, W
    BTFSS STATUS, 0     
    GOTO BCD_END
    MOVWF KEY_PRESSED
    INCF DISP_DIG1, F
    GOTO BCD_L
BCD_END:
    MOVF KEY_PRESSED, W
    MOVWF DISP_DIG2     
    RETURN

; ==============================================================================
; YARDIMCI FONKS?YONLAR (Tablo ve Gecikme)
; ==============================================================================
GET_SEG:
    ANDLW 0x0F          
    MOVWF SEG_TEMP
    MOVLW 12            
    SUBWF SEG_TEMP, W   
    BTFSC STATUS, 0     
    RETLW 00000000B     
    MOVLW HIGH(SEG_TABLE)
    MOVWF PCLATH        
    MOVF SEG_TEMP, W    
    ADDWF PCL, F        

SEG_TABLE:
    RETLW 00111111B ; 0 
    RETLW 00000110B ; 1 
    RETLW 01011011B ; 2 
    RETLW 01001111B ; 3 
    RETLW 01100110B ; 4 
    RETLW 01101101B ; 5 
    RETLW 01111101B ; 6 
    RETLW 00000111B ; 7 
    RETLW 01111111B ; 8 
    RETLW 01101111B ; 9 
    RETLW 00000000B ; 10 (Bo?)
    RETLW 00111001B ; 11 (C)

DLY_US:
    MOVLW 250           
    MOVWF WAIT_VAR
DLY_US_LOOP:
    NOP
    DECFSZ WAIT_VAR, F
    GOTO DLY_US_LOOP
    RETURN

DLY_US_SHORT:
    MOVLW 100           
    MOVWF WAIT_VAR
DLY_SHORT_L:
    NOP
    DECFSZ WAIT_VAR, F
    GOTO DLY_SHORT_L
    RETURN

DELAY_1MS:
    MOVLW 200
    MOVWF WAIT_VAR
DLY_1MS_L:
    NOP
    NOP
    DECFSZ WAIT_VAR, F
    GOTO DLY_1MS_L
    RETURN

DELAY_UI_SHORT:
    MOVLW 20            
    MOVWF KEY_PRESSED   
UI_WAIT_LOOP:
    CALL REFRESH_INPUT_DISPLAY
    DECFSZ KEY_PRESSED, F
    GOTO UI_WAIT_LOOP
    RETURN

; ==============================================================================
; S?STEM KURULUMU (Senin Kodun)
; ==============================================================================
SYSTEM_INIT:
    BSF STATUS, 5       ; BANK 1'e geç

    ; Port Ayarlar?
    MOVLW 00000001B     ; RA0 Analog
    MOVWF TRISA
    MOVLW 11110000B     ; RB0-3 Out, RB4-7 In
    MOVWF TRISB
    MOVLW 11000001B     ; UART TX/RX
    MOVWF TRISC
    CLRF TRISD          ; Segment Out

    ; ADC Ayarlar?
    MOVLW 10001110B     
    MOVWF ADCON1

    ; UART Ayarlar? (9600 Baud)
    MOVLW 00100100B     
    MOVWF TXSTA
    MOVLW 25            
    MOVWF SPBRG
    
    ; Kesme ?zinleri
    BSF PIE1, 5         ; UART RX IE
    
    ; >>> PULL-UP AKT?F <<<
    BCF OPTION_REG, 7   
    
    BCF STATUS, 5       ; BANK 0

    ; Modül Aktifle?tirme
    MOVLW 10010000B     
    MOVWF RCSTA
    MOVLW 01000001B     
    MOVWF ADCON0

    ; Di?er Modüller (Ba?kalar? dolduracak)
    MOVLW 00000011B
    MOVWF T1CON
    MOVLW 0x07
    MOVWF CMCON

    CLRF PORTA
    CLRF PORTB
    CLRF PORTC
    CLRF PORTD
    
    ; Global Kesmeler
    BSF INTCON, 7       ; GIE
    BSF INTCON, 6       ; PEIE
    BSF INTCON, 3       ; RBIE
    BCF INTCON, 0       ; RBIF Temizle

    RETURN

    END