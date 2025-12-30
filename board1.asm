; ==============================================================================
; PROJE: Board #1 - Ev ?klimlendirme Sistemi (TAM DÜZELT?LM?? VERS?YON)
; ??LEMC?: PIC16F877A
; FREKANS: 4 MHz (XT)
; ==============================================================================
; DÜZELTMELER:
; 1. Keypad giri?i tamamen yeniden yaz?ld? (debounce + ad?m bazl?)
; 2. Interrupt sadece uyand?rma yap?yor, tu? okuma main'de
; 3. Giri? s?ras?nda gerçek zamanl? ekran güncellemesi
; 4. Fan mant??? hassas kontrol (25.0 vs 25.1 ayr?m?)
; ==============================================================================

#include <xc.inc>

; --- 1. KONFIGÜRASYON AYARLARI ---
config FOSC = XT        ; 4MHz Kristal
config WDTE = OFF       ; Watchdog Timer Kapal?
config PWRTE = ON       ; Power-up Timer Aç?k
config BOREN = ON       ; Brown-out Reset Aç?k
config LVP = OFF        ; Low Voltage Programming Kapal?
config CPD = OFF        ; Data Code Protection Kapal?
config CP = OFF         ; Code Protection Kapal?

; --- 2. HAFIZA (RAM) YÖNET?M? ---
; Genel De?i?kenler
DESIRED_TEMP_INT    EQU 0x20    ; ?stenen S?cakl?k (Tam)
DESIRED_TEMP_FRAC   EQU 0x21    ; ?stenen S?cakl?k (Ondal?k)
AMBIENT_TEMP_INT    EQU 0x22    ; Ortam S?cakl??? (Tam)
AMBIENT_TEMP_FRAC   EQU 0x23    ; Ortam S?cakl??? (Ondal?k)
FAN_SPEED           EQU 0x24    ; Fan H?z? (RPS)

; Sistem Durum De?i?kenleri
SYSTEM_MODE         EQU 0x25    ; 0: Normal, 1: Veri Giri? Modu
INPUT_BUFFER_INT    EQU 0x26    ; Giri? s?ras?nda tam say?y? tutar
INPUT_BUFFER_FRAC   EQU 0x27    ; Giri? s?ras?nda ondal??? tutar
DISPLAY_MODE        EQU 0x28    ; 0: ?stenen, 1: Ortam, 2: Fan
DISPLAY_TIMER       EQU 0x29    ; 2 saniye sayac?
RX_DATA             EQU 0x2A    ; UART gelen veri

; Geçici De?i?kenler
ADC_H               EQU 0x30
ADC_L               EQU 0x31
DISP_DIG1           EQU 0x32
DISP_DIG2           EQU 0x33
DISP_DIG3           EQU 0x34
DISP_DIG4           EQU 0x35
DELAY_COUNT         EQU 0x36
KEY_PRESSED         EQU 0x37
WAIT_VAR            EQU 0x38    ; Gecikme döngüsü için özel de?i?ken

; Yeni Keypad De?i?kenleri
INPUT_STEP          EQU 0x39    ; Hangi ad?mday?z (0-4)
DEBOUNCE_COUNT      EQU 0x3A    ; Tu? s?çrama önleyici
LAST_KEY            EQU 0x3B    ; Son bas?lan tu?

SEG_TEMP            EQU 0x7E    ; GET_SEG fonksiyonu için özel korumal? depo

; Interrupt Context Saving
W_TEMP              EQU 0x70
STATUS_TEMP         EQU 0x71

; --- PIN TANIMLAMALARI ---
#define HEATER_PIN      PORTC, 1    ; Is?t?c? Ç?k???
#define COOLER_PIN      PORTC, 2    ; Fan (Cooler) Ç?k???

; ==============================================================================
; RESET VEKTÖRÜ
; ==============================================================================
PSECT resetVec, class=CODE, delta=2
ORG 0x00
    GOTO MAIN

; ==============================================================================
; INTERRUPT SERV?S RUT?N? (ISR)
; ==============================================================================
PSECT isrVec, class=CODE, delta=2
ORG 0x04
    ; --- Context Save ---
    MOVWF W_TEMP
    SWAPF STATUS, W
    MOVWF STATUS_TEMP

    ; --- 1. UART KESMES? ---
    BCF STATUS, 5           ; Bank 0
    BTFSC PIR1, 5           ; RCIF
    CALL ISR_UART_HANDLER

    ; --- 2. KEYPAD KESMES? ---
    BTFSC INTCON, 0         ; RBIF
    CALL ISR_KEYPAD_HANDLER

ISR_EXIT:
    ; --- Context Restore ---
    SWAPF STATUS_TEMP, W
    MOVWF STATUS
    SWAPF W_TEMP, F
    SWAPF W_TEMP, W
    RETFIE

; ==============================================================================
; ANA PROGRAM (MAIN)
; ==============================================================================
MAIN:
    CALL SYSTEM_INIT        ; Donan?m Kurulumu
    
    ; Varsay?lan De?erler
    MOVLW 30
    MOVWF DESIRED_TEMP_INT
    MOVLW 5
    MOVWF DESIRED_TEMP_FRAC
    MOVLW 0
    MOVWF SYSTEM_MODE       ; Normal Mod
    CLRF INPUT_STEP

MAIN_LOOP:
    CALL SYSTEM_INIT
    ; --- MOD KONTROLÜ ---
    MOVF SYSTEM_MODE, W
    SUBLW 1
    BTFSC STATUS, 2         ; SYSTEM_MODE == 1 ise
    GOTO HANDLE_INPUT_MODE  ; Giri? Moduna Git
    
    ; --- NORMAL MOD ??LEMLER? ---

    ; 1. Sensör Oku
    CALL READ_TEMP_SENSOR
    
    ; 2. Fan H?z? Ölç
    MOVF TMR1L, W
    MOVWF FAN_SPEED
    CLRF TMR1L
    CLRF TMR1H

    ; 3. Mant?k Kontrolü
    CALL LOGIC_CONTROL

    ; 4. Ekran Yönetimi
    CALL UPDATE_DISPLAY_DATA
    
    ; 5. Ekran? Tara
    CALL REFRESH_DISPLAY_LOOP
    
    ; Döngü Sayac?
    INCF DISPLAY_TIMER, F
    MOVLW 100               ; Yakla??k 2 saniye
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
; MANTIK KONTROLÜ (HASSAS SÖNMADAN ÖNCEK? VERS?YON)
; ==============================================================================

LOGIC_CONTROL:
    ; --- 1. ADIM: TAM SAYILARI KAR?ILA?TIR ---
    MOVF AMBIENT_TEMP_INT, W
    SUBWF DESIRED_TEMP_INT, W   ; ??lem: ?stenen - Ortam
    
    BTFSS STATUS, 0
    GOTO ACTIVATE_COOLING       ; Ortam s?cak -> SO?UTUCUYU AÇ
    
    BTFSS STATUS, 2             ; Z (Zero) biti 1 mi?
    GOTO ACTIVATE_HEATING       ; Hay?r, ortam so?uk -> ISITICIYI AÇ
    
    ; --- 2. ADIM: TAM SAYILAR E??TSE ONDALIKLARA BAK ---
    MOVF AMBIENT_TEMP_FRAC, W
    SUBWF DESIRED_TEMP_FRAC, W  ; ??lem: ?stenen_Frac - Ortam_Frac
    
    BTFSS STATUS, 0
    GOTO ACTIVATE_COOLING       ; Hedef geçilmi? -> SO?UTUCUYU AÇ
    
    GOTO ACTIVATE_HEATING       ; Hedefin alt?nda veya e?it -> ISITICIYI AÇ

ACTIVATE_COOLING:
    BCF HEATER_PIN              ; 1. Önce Is?t?c?y? DURDUR
    BSF COOLER_PIN              ; 2. Sonra Fan? ÇALI?TIR
    RETURN

ACTIVATE_HEATING:
    BCF COOLER_PIN              ; 1. Önce Fan? DURDUR
    BSF HEATER_PIN              ; 2. Sonra Is?t?c?y? ÇALI?TIR
    RETURN

; ==============================================================================
; KEYPAD G?R?? S?STEM? (YEN?DEN YAZILDI)
; ==============================================================================

; ==============================================================================
; DE????KL?K 3: G?R?? MODU (00.0C -> SIRALI G?R??)
; ==============================================================================
HANDLE_INPUT_MODE:
    ; ?lk giri?te ekran? "00.0C" yap
    MOVF INPUT_STEP, F
    BTFSS STATUS, 2      ; Step 0 m??
    GOTO INPUT_STEP_HANDLER ; De?ilse devam et

    ; --- BA?LANGIÇ AYARLARI (00.0C) ---
    CLRF INPUT_BUFFER_INT   ; Tam say? buffer temizle
    CLRF INPUT_BUFFER_FRAC  ; Ondal?k buffer temizle
    
    MOVLW 0              ; 1. Hane: 0
    MOVWF DISP_DIG1
    MOVLW 0              ; 2. Hane: 0
    MOVWF DISP_DIG2
    MOVLW 0              ; 3. Hane: 0 (Ondal?k)
    MOVWF DISP_DIG4      ; Dikkat: Kodunda 4. hane ondal?k/C idi, burada yer de?i?tiriyoruz
    
    ; Mant?k: Ekranda DIG1(Onlar), DIG2(Birler), DIG3(Ondal?k), DIG4(C)
    ; Ba?lang?ç: 0 0 . 0 C

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

; --- ADIM 0: ONLAR BASAMA?I (?lk Rakam) ---
STEP_0_ONLAR:
    CALL GET_KEY_BLOCKING_NEW
    
    ; Rakam m?? (0-9)
    MOVWF LAST_KEY
    MOVLW 10
    SUBWF LAST_KEY, W
    BTFSC STATUS, 0     ; >= 10 ise (A,B,C,*,#)
    GOTO ABORT_INPUT    ; Hata

    ; Ekran? Güncelle: [X][0][0][C] -> ?lk rakam onlar hanesine
    MOVF LAST_KEY, W
    MOVWF INPUT_BUFFER_INT ; Geçici kaydet
    MOVWF DISP_DIG1        ; 1. Haneye yaz
    
    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

; --- ADIM 1: B?RLER BASAMA?I (?kinci Rakam) ---
STEP_1_BIRLER:
    CALL GET_KEY_BLOCKING_NEW
    
    MOVWF LAST_KEY
    MOVLW 10
    SUBWF LAST_KEY, W
    BTFSC STATUS, 0
    GOTO ABORT_INPUT

    ; Hesaplama: (Digit1 * 10) + Digit2
    ; Önceki buffer'? 10 ile çarp
    MOVF INPUT_BUFFER_INT, W
    MOVWF KEY_PRESSED
    MOVLW 9
    MOVWF DELAY_COUNT
MUL_LOOP:
    MOVF KEY_PRESSED, W
    ADDWF INPUT_BUFFER_INT, F
    DECFSZ DELAY_COUNT, F
    GOTO MUL_LOOP
    
    ; Yeniyi ekle
    MOVF LAST_KEY, W
    ADDWF INPUT_BUFFER_INT, F
    
    ; Ekrana Yaz: [D1][D2][0][C]
    MOVWF DISP_DIG2        ; 2. Haneye (Birler) yaz

    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

; --- ADIM 2: YILDIZ (*) BEKLEME ---
STEP_2_YILDIZ:
    CALL GET_KEY_BLOCKING_NEW
    
    XORLW 0x0E          ; * Tu?u mu?
    BTFSS STATUS, 2
    GOTO ABORT_INPUT    ; De?ilse iptal

    ; Y?ld?z bas?ld?, ekranda görsel bir de?i?im gerekmez 
    ; ama kullan?c?ya ondal?k k?sma geçti?ini hissettirebiliriz.
    ; Mevcut durum: [3][5][.][0][C]
    
    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

; --- ADIM 3: ONDALIK BASAMAK ---
STEP_3_ONDALIK:
    CALL GET_KEY_BLOCKING_NEW
    
    MOVWF LAST_KEY
    MOVLW 10
    SUBWF LAST_KEY, W
    BTFSC STATUS, 0
    GOTO ABORT_INPUT

    ; Sadece 0 veya 5 kabul edilecekse buraya kontrol koyabilirsin
    ; Biz ?imdilik her rakam? kabul edelim:
    MOVF LAST_KEY, W
    MOVWF INPUT_BUFFER_FRAC
    MOVWF DISP_DIG4     ; Dikkat: Senin kodunda DIG4 de?i?keni ondal?k için kullan?l?yordu
                        ; Ancak REFRESH_INPUT_DISPLAY k?sm?nda 
                        ; 3. Hane -> DIG3, 4. Hane -> DIG4/C harfi idi.
                        ; Burada kodu `REFRESH_INPUT_DISPLAY` ile uyumlu hale getirmelisin.
                        ; E?er DIG4 ekranda 3. s?radaki 7-segment ise oraya yaz.
    
    INCF INPUT_STEP, F
    CALL DELAY_UI_SHORT
    GOTO INPUT_STEP_HANDLER

; --- ADIM 4: KARE (#) ?LE KAYDET ---
STEP_4_KARE:
    CALL GET_KEY_BLOCKING_NEW
    
    XORLW 0x0F          ; # Tu?u mu?
    BTFSS STATUS, 2
    GOTO ABORT_INPUT
    
    ; --- KAYDETME ---
    MOVF INPUT_BUFFER_INT, W
    MOVWF DESIRED_TEMP_INT
    MOVF INPUT_BUFFER_FRAC, W
    MOVWF DESIRED_TEMP_FRAC
    
    ; Ç?k??
    CLRF SYSTEM_MODE
    CLRF INPUT_STEP
    GOTO MAIN_LOOP

; --- HATA DURUMU: ?PTAL ---
ABORT_INPUT:
    ; Eski de?erleri koru, modu s?f?rla
    CLRF SYSTEM_MODE
    CLRF DISPLAY_MODE
    CLRF INPUT_STEP
    GOTO MAIN_LOOP          ; Ana döngüye geri dön

; ==============================================================================
; YEN? TU? OKUMA FONKS?YONU (DEBOUNCE ?LE)
; ==============================================================================

GET_KEY_BLOCKING_NEW:
    ; Önce mevcut tu?lar?n b?rak?lmas?n? bekle
WAIT_RELEASE:
    CALL REFRESH_INPUT_DISPLAY  ; Ekran? güncelle
    
    MOVLW 11110000B
    MOVWF PORTB
    MOVLW 5
    MOVWF DEBOUNCE_COUNT
DEB_REL:
    MOVF PORTB, W
    ANDLW 11110000B
    XORLW 11110000B         ; Tüm sat?rlar HIGH m??
    BTFSS STATUS, 2
    GOTO WAIT_RELEASE       ; Hay?r, hala bas?l?
    DECFSZ DEBOUNCE_COUNT, F
    GOTO DEB_REL
    
    ; ?imdi yeni tu? bekle
; ==============================================================================
; DE????KL?K 1: 4. SÜTUN TARAMASI EKLEND? (A TU?U ?Ç?N)
; ==============================================================================
SCAN_KEYS:
    CALL REFRESH_INPUT_DISPLAY ; Beklerken ekran sönmesin

    ; --- SÜTUN 1 (1, 4, 7, *) ---
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

    ; --- SÜTUN 2 (2, 5, 8, 0) ---
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

    ; --- SÜTUN 3 (3, 6, 9, #) ---
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

    ; --- SÜTUN 4 (A, B, C, D) - YEN? EKLEND? ---
    MOVLW 11110111B    ; 4. Sütunu (RB3) Low yap
    MOVWF PORTB
    NOP
    BTFSS PORTB, 4     ; Sat?r 1 (RB4) Low mu? -> A Tu?u
    GOTO FOUND_A
    ; B, C, D tu?lar?na ihtiyac?m?z yoksa kontrol etmeyebiliriz
    
    GOTO SCAN_KEYS

; A Tu?u Bulundu Etiketi
FOUND_A:
    MOVLW 0x0A         ; A tu?u için 10 (0x0A) de?eri
    GOTO KEY_CONFIRM

; --- TU? BULUNAN DURUMLAR ---
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

; --- TU? ONAYLAMA (DEBOUNCE) ---
KEY_CONFIRM:
    MOVWF LAST_KEY          ; Tu?u kaydet
    MOVLW 10                ; Debounce sayac?
    MOVWF DEBOUNCE_COUNT
DEB_PRESS:
    CALL DELAY_1MS
    DECFSZ DEBOUNCE_COUNT, F
    GOTO DEB_PRESS
    
    MOVF LAST_KEY, W        ; Tu?u döndür
    RETURN

; ==============================================================================
; G?R?? MODU EKRAN TARAMA (4 HANE)
; ==============================================================================

REFRESH_INPUT_DISPLAY:
    MOVLW 2                 ; Daha h?zl? tarama
    MOVWF DELAY_COUNT

RINPUT_LOOP:
    ; --- HANE 1: ONLAR ---
    MOVF DISP_DIG1, W
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 2
    CALL DLY_US_SHORT
    BCF PORTA, 2
    CLRF PORTD

    ; --- HANE 2: B?RLER ---
    MOVF DISP_DIG2, W
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 3
    CALL DLY_US_SHORT
    BCF PORTA, 3
    CLRF PORTD

    ; --- HANE 3: DERECE ---
    MOVLW 01100011B
    MOVWF PORTD
    BSF PORTA, 4
    CALL DLY_US_SHORT
    BCF PORTA, 4
    CLRF PORTD

    ; --- HANE 4: ONDALIK veya 'C' ---
    MOVF INPUT_STEP, W
    SUBLW 3                 ; Ad?m >= 4 ise 'C' göster
    BTFSC STATUS, 0
    GOTO SHOW_FRAC_DIGIT
    
    MOVLW 00111001B         ; 'C' harfi
    GOTO SHOW_LAST_DIGIT
SHOW_FRAC_DIGIT:
    MOVF DISP_DIG4, W
    CALL GET_SEG
SHOW_LAST_DIGIT:
    MOVWF PORTD
    BSF PORTA, 5
    CALL DLY_US_SHORT
    BCF PORTA, 5
    CLRF PORTD

    DECFSZ DELAY_COUNT, F
    GOTO RINPUT_LOOP
    RETURN

; ==============================================================================
; UART ??LEY?C?S?
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
; DE????KL?K 2: INTERRUPT SADECE 'A' ?LE G?R?? MODUNU AÇAR
; ==============================================================================
ISR_KEYPAD_HANDLER:
    ; E?er zaten giri? modundaysak (SYSTEM_MODE=1), ç?k.
    MOVF SYSTEM_MODE, F
    BTFSS STATUS, 2      ; 0 m??
    GOTO ISR_KEY_EXIT    ; Hay?r, zaten mod 1, i?lem yapma.

    ; H?zl?ca 'A' tu?u mu kontrol et
    ; A tu?u: Sütun 4 (RB3=0) ve Sat?r 1 (RB4=0) olmal?.
    
    MOVLW 11110111B      ; Sütun 4 Low
    MOVWF PORTB
    NOP
    NOP
    BTFSC PORTB, 4       ; Sat?r 1 Low mu? (Bas?l? m??)
    GOTO ISR_KEY_EXIT    ; Hay?r (High), o zaman A de?il. Ç?k.

    ; Evet, A tu?una bas?lm??! Giri? modunu ba?lat.
    MOVLW 1
    MOVWF SYSTEM_MODE
    
    ; Giri? ad?mlar?n? s?f?rla
    CLRF INPUT_STEP
    
ISR_KEY_EXIT:
    BCF INTCON, 0        ; RBIF Temizle
    MOVF PORTB, W        ; Portu oku (Mismatch condition temizlemek için)
    RETURN
; ==============================================================================
; SENSÖR OKUMA
; ==============================================================================

READ_TEMP_SENSOR:
    BSF ADCON0, 2
WAIT_ADC:
    BTFSC ADCON0, 2
    GOTO WAIT_ADC
    
    BSF STATUS, 5
    MOVF ADRESL, W
    BCF STATUS, 5
    MOVWF ADC_L
    MOVF ADRESH, W
    MOVWF ADC_H
    
    BCF STATUS, 0
    RRF ADC_H, F
    RRF ADC_L, F
    MOVF ADC_L, W
    MOVWF AMBIENT_TEMP_INT
    
    CLRF AMBIENT_TEMP_FRAC
    BTFSC STATUS, 0
    MOVLW 5
    BTFSC STATUS, 0
    MOVWF AMBIENT_TEMP_FRAC
    RETURN

; ==============================================================================
; EKRAN VER?S? HAZIRLAMA
; ==============================================================================

; ==============================================================================
; EKRAN VER?S? HAZIRLAMA (GÜNCELLENM??)
; ==============================================================================
UPDATE_DISPLAY_DATA:
    MOVF DISPLAY_MODE, W
    XORLW 2
    BTFSC STATUS, 2
    GOTO PREP_FAN       ; Mod 2 ise Fan'a git
    
    ; --- SICAKLIK MODLARI (?stenen veya Ortam) ---
    ; Ad?m A: Hangi s?cakl?k?
    MOVF DISPLAY_MODE, W
    XORLW 0
    BTFSC STATUS, 2
    GOTO LOAD_DESIRED   ; Mod 0: ?stenen
    
    ; Mod 1: Ortam
    MOVF AMBIENT_TEMP_INT, W
    MOVWF KEY_PRESSED   ; Geçici sakla
    MOVF AMBIENT_TEMP_FRAC, W
    MOVWF DISP_DIG3     ; 3. Haneye ondal??? koy (0 veya 5)
    GOTO CONVERT_TEMP

LOAD_DESIRED:
    MOVF DESIRED_TEMP_INT, W
    MOVWF KEY_PRESSED
    MOVF DESIRED_TEMP_FRAC, W
    MOVWF DISP_DIG3     ; 3. Haneye ondal??? koy

CONVERT_TEMP:
    ; Ad?m B: Tam say?y? BCD'ye çevir (Dig1 ve Dig2 dolar)
    MOVF KEY_PRESSED, W
    CALL BIN_TO_BCD_RAW ; Dig1 ve Dig2'yi doldurur
    
    ; Ad?m C: 4. Haneye 'C' harfi koy (Tabloda 11. eleman)
    MOVLW 11
    MOVWF DISP_DIG4
    RETURN

PREP_FAN:
    ; --- FAN MODU (Sa?a Dayal?) ---
    MOVF FAN_SPEED, W
    CALL BIN_TO_BCD_RAW ; Sonuç Dig1(Onlar) ve Dig2(Birler)'de
    
    ; Kayd?rma ??lemi: [D1][D2][X][X] -> [Bo?][Bo?][D1][D2]
    MOVF DISP_DIG2, W
    MOVWF DISP_DIG4     ; Birler basama??n? en sa?a (Hane 4) al
    
    MOVF DISP_DIG1, W
    MOVWF DISP_DIG3     ; Onlar basama??n? Hane 3'e al
    
    ; ?lk iki haneyi temizle (Bo?luk = 10)
    MOVLW 10
    MOVWF DISP_DIG1
    MOVWF DISP_DIG2
    
    ; Estetik: E?er Fan h?z? < 10 ise (Onlar basama?? 0 ise), Hane 3'ü de bo?alt
    MOVF DISP_DIG3, W
    BTFSC STATUS, 2     ; 0 m??
    MOVWF DISP_DIG3     ; De?ilse dokunma (HATA: Buray? düzeltiyorum a?a??da)
    
    MOVF DISP_DIG3, W   ; Tekrar kontrol
    BTFSS STATUS, 2     ; 0 de?ilse atla
    GOTO FAN_DONE       ; 0 de?il, devam
    MOVLW 10            ; 0 ise Bo?luk yükle
    MOVWF DISP_DIG3
    
FAN_DONE:
    RETURN

; Yard?mc?: Sadece çeviri yapar, Dig1 ve Dig2'ye yazar
BIN_TO_BCD_RAW:
    MOVWF KEY_PRESSED   ; Çevrilecek say?
    CLRF DISP_DIG1      ; Onlar basama??
BCD_L:
    MOVLW 10
    SUBWF KEY_PRESSED, W
    BTFSS STATUS, 0     ; Negatif oldu mu?
    GOTO BCD_END
    MOVWF KEY_PRESSED
    INCF DISP_DIG1, F
    GOTO BCD_L
BCD_END:
    MOVF KEY_PRESSED, W
    MOVWF DISP_DIG2     ; Kalan? birler basama??na yaz
    RETURN

; ==============================================================================
; NORMAL MOD EKRAN TARAMA
; ==============================================================================

; ==============================================================================
; EKRAN TARAMA (NOKTA DESTEKL?)
; ==============================================================================
REFRESH_DISPLAY_LOOP:
    MOVLW 4
    MOVWF DELAY_COUNT

REFRESH_L:
    ; --- 1. HANE (En Sol) ---
    MOVF DISP_DIG1, W
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 2
    CALL DLY_US
    BCF PORTA, 2
    CLRF PORTD

    ; --- 2. HANE (Noktal? Alan) ---
    MOVF DISP_DIG2, W
    CALL GET_SEG
    MOVWF PORTD         ; Segment verisini yükle
    
    ; Nokta Kontrolü: E?er Fan modunda de?ilsek (Mod 0 veya 1), Noktay? yak
    BTFSC DISPLAY_MODE, 1 ; Mod 2 (10) veya 3 (11) ise atla -> Fan modu
    GOTO SKIP_DOT
    BSF PORTD, 7        ; PORTD'nin 7. biti DP varsay?lm??t?r (Gerekirse de?i?tirin)
SKIP_DOT:
    BSF PORTA, 3
    CALL DLY_US
    BCF PORTA, 3
    CLRF PORTD

    ; --- 3. HANE ---
    MOVF DISP_DIG3, W   ; Art?k de?i?ken! (Ondal?k veya Fan Onlar)
    CALL GET_SEG
    MOVWF PORTD
    BSF PORTA, 4
    CALL DLY_US
    BCF PORTA, 4
    CLRF PORTD

    ; --- 4. HANE (En Sa?) ---
    MOVF DISP_DIG4, W   ; Art?k de?i?ken! ('C' veya Fan Birler)
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
; YARDIMCI FONKS?YONLAR
; ==============================================================================

; ==============================================================================
; TABLO VE ÇEV?R?C? (TAM DÜZELT?LM?? VERS?YON)
; ==============================================================================
GET_SEG:
    ANDLW 0x0F          ; Sadece alt 4 biti al (0-15 aras? güvenlik)
    MOVWF SEG_TEMP

    ; --- SINIR KONTROLÜ GÜNCELLEMES? ---
    ; Tablomuzda art?k 12 eleman var (0-9 rakamlar, 10 bo?luk, 11 C harfi)
    ; Bu yüzden s?n?r? 12 yap?yoruz. 12 ve üzeri gelirse sönük (0x00) döner.
    MOVLW 12            
    SUBWF SEG_TEMP, W   ; W = SEG_TEMP - 12
    BTFSC STATUS, 0     ; Sonuç pozitif veya s?f?r m?? (Yani say? >= 12 mi?)
    RETLW 00000000B     ; Evet >= 12 ise, ekran? sönük tut (Hata korumas?)

    ; --- TABLOYA ATLAMA ---
    MOVLW HIGH(SEG_TABLE)
    MOVWF PCLATH        ; Tablonun bulundu?u haf?za sayfas?n? ayarla
    
    MOVF SEG_TEMP, W    ; ?ndis de?erini (0-11) W'ye al
    ADDWF PCL, F        ; Program sayac?na ekle ve ilgili RETLW'ye git

SEG_TABLE:
    RETLW 00111111B ; 0 (A-B-C-D-E-F)
    RETLW 00000110B ; 1 (B-C)
    RETLW 01011011B ; 2 (A-B-D-E-G)
    RETLW 01001111B ; 3 (A-B-C-D-G)
    RETLW 01100110B ; 4 (B-C-F-G)
    RETLW 01101101B ; 5 (A-C-D-F-G)
    RETLW 01111101B ; 6 (A-C-D-E-F-G)
    RETLW 00000111B ; 7 (A-B-C)
    RETLW 01111111B ; 8 (Hepsi aç?k)
    RETLW 01101111B ; 9 (A-B-C-D-F-G)
    RETLW 00000000B ; 10 -> BO?LUK (Tüm segmentler kapal?)
    RETLW 00111001B ; 11 -> C Harfi (A-D-E-F)

; ==============================================================================
; GEC?KME VE ZAMANLAMA FONKS?YONLARI
; ==============================================================================

; --- K?sa Gecikme (Ekran Tarama ?çin) ---
DLY_US:
    MOVLW 250           ; Ekran parlakl??? için bekleme
    MOVWF WAIT_VAR
DLY_US_LOOP:
    NOP
    DECFSZ WAIT_VAR, F
    GOTO DLY_US_LOOP
    RETURN

; --- Çok K?sa Gecikme (Giri? Ekran? ?çin) ---
DLY_US_SHORT:
    MOVLW 100           ; Daha h?zl? tarama
    MOVWF WAIT_VAR
DLY_SHORT_L:
    NOP
    DECFSZ WAIT_VAR, F
    GOTO DLY_SHORT_L
    RETURN

; --- 1ms Gecikme (Debounce ?çin) ---
DELAY_1MS:
    MOVLW 200
    MOVWF WAIT_VAR
DLY_1MS_L:
    NOP
    NOP
    DECFSZ WAIT_VAR, F
    GOTO DLY_1MS_L
    RETURN

; --- Kullan?c? Arayüzü Gecikmesi (Tu?lar Aras? Bekleme) ---
; Bu gecikme s?ras?nda ekran sönmemesi için sürekli REFRESH ça?r?l?r
DELAY_UI_SHORT:
    MOVLW 20            ; Yakla??k 0.2 saniye bekle
    MOVWF KEY_PRESSED   ; Geçici sayaç olarak kullan
UI_WAIT_LOOP:
    CALL REFRESH_INPUT_DISPLAY
    DECFSZ KEY_PRESSED, F
    GOTO UI_WAIT_LOOP
    RETURN

; ==============================================================================
; S?STEM KURULUMU (DONANIM AYARLARI)
; ==============================================================================
SYSTEM_INIT:
    BSF STATUS, 5       ; BANK 1'e geç

    ; 1. Port Ayarlar?
    MOVLW 00000001B     ; RA0 Giri? (Analog), RA2-5 Ç?k?? (Ekran)
    MOVWF TRISA
    
    MOVLW 11110000B     ; RB0-3 Ç?k?? (Tarama), RB4-7 Giri? (Okuma)
    MOVWF TRISB
    
    MOVLW 11000001B     ; RC6/TX, RC7/RX (UART), RC1, RC2 Ç?k??
    MOVWF TRISC
    
    CLRF TRISD          ; PORTD Tümü Ç?k?? (Segmentler)

    ; 2. ADC Ayarlar? (AN0 Analog, Di?erleri Dijital)
    MOVLW 10001110B     ; Sa?a yasl?, Fosc/64, Sadece AN0 Analog
    MOVWF ADCON1

    ; 3. UART Ayarlar? (9600 Baud @ 4MHz)
    MOVLW 00100100B     ; TXEN=1, BRGH=1 (Yüksek H?z)
    MOVWF TXSTA
    MOVLW 25            ; SPBRG de?eri (9600 baud için)
    MOVWF SPBRG
    
    ; 4. Kesme ?zinleri
    BSF PIE1, 5         ; RCIE (UART Al?m Kesmesi) Aç?k
    
    BCF STATUS, 5       ; BANK 0'a dön

    ; 5. Modül Aktifle?tirme
    MOVLW 10010000B     ; SPEN=1, CREN=1 (Seri Port Aç?k)
    MOVWF RCSTA
    
    MOVLW 01000001B     ; ADCS=01, CHS=000 (AN0), ADON=1
    MOVWF ADCON0

    ; 6. Fan H?z? ?çin Timer1
    MOVLW 00000011B     ; Prescaler 1:1, Harici Clock, Timer Aç?k
    MOVWF T1CON

    ; 7. Kar??la?t?r?c?lar? Kapat (CMCON)
    MOVLW 0x07          ; Port A'y? dijital G/Ç olarak kullanabilmek için
    MOVWF CMCON

    ; 8. Kesme Yönetimi
    CLRF PORTA
    CLRF PORTB
    CLRF PORTC
    CLRF PORTD
    
    BSF INTCON, 7       ; GIE (Global Interrupt) Aç?k
    BSF INTCON, 6       ; PEIE (Peripheral Interrupt) Aç?k
    BSF INTCON, 3       ; RBIE (Port B De?i?iklik Kesmesi) Aç?k
    BCF INTCON, 0       ; RBIF Bayra??n? temizle

    RETURN

    END

